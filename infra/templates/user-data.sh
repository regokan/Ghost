#!/bin/bash
set -e

exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

echo "=========================================="
echo "Ghost Blog EC2 Setup"
echo "=========================================="

# From Terraform (needed at runtime)
DB_CREDENTIALS_SECRET_NAME="${db_credentials_secret_name}"
DB_CREDENTIALS_SECRET_REGION="${db_credentials_secret_region}"
SES_CREDENTIALS_SECRET_NAME="${ses_credentials_secret_name}"
SES_CREDENTIALS_SECRET_REGION="${ses_credentials_secret_region}"
S3_CREDENTIALS_SECRET_NAME="${s3_credentials_secret_name}"
S3_CREDENTIALS_SECRET_REGION="${s3_credentials_secret_region}"

# System update and Docker
dnf update -y
dnf install -y docker unzip
systemctl enable docker
systemctl start docker

# Docker Compose
DOCKER_COMPOSE_VERSION="v5.0.2"
curl -L "https://github.com/docker/compose/releases/download/$${DOCKER_COMPOSE_VERSION}/docker-compose-linux-x86_64" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose
ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose

# AWS CLI v2 + jq for parsing secrets
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o awscliv2.zip
unzip -q awscliv2.zip && ./aws/install && rm -rf awscliv2.zip aws
dnf install -y jq 2>/dev/null || true

# DB secret JSON (key: db_password)
DB_SECRET_JSON=""
for i in 1 2 3 4 5 6 7 8 9 10; do
  DB_SECRET_JSON=$(aws secretsmanager get-secret-value \
    --secret-id "$${DB_CREDENTIALS_SECRET_NAME}" \
    --region "$${DB_CREDENTIALS_SECRET_REGION}" \
    --query SecretString --output text 2>/dev/null) && break
  echo "Waiting for Secrets Manager (attempt $i/10)..."
  sleep 15
done
if [ -z "$${DB_SECRET_JSON}" ] || [ "$${DB_SECRET_JSON}" = "null" ]; then
  echo "ERROR: Could not get DB secret from Secrets Manager. Check IAM and secret name."
  exit 1
fi
DB_PASSWORD=$(echo "$${DB_SECRET_JSON}" | jq -r '.db_password // empty')
if [ -z "$${DB_PASSWORD}" ]; then
  echo "ERROR: Secret must contain 'db_password'."
  exit 1
fi

# SMTP secret JSON (keys: ses_smtp_username, ses_smtp_password)
SMTP_SECRET_JSON=""
for i in 1 2 3 4 5 6 7 8 9 10; do
  SMTP_SECRET_JSON=$(aws secretsmanager get-secret-value \
    --secret-id "$${SES_CREDENTIALS_SECRET_NAME}" \
    --region "$${SES_CREDENTIALS_SECRET_REGION}" \
    --query SecretString --output text 2>/dev/null) && break
  echo "Waiting for Secrets Manager SMTP secret (attempt $i/10)..."
  sleep 15
done
if [ -z "$${SMTP_SECRET_JSON}" ] || [ "$${SMTP_SECRET_JSON}" = "null" ]; then
  echo "ERROR: Could not get SMTP secret from Secrets Manager. Check IAM and secret name."
  exit 1
fi
SES_USER=$(echo "$${SMTP_SECRET_JSON}" | jq -r '.ses_smtp_username // empty')
SES_PASS=$(echo "$${SMTP_SECRET_JSON}" | jq -r '.ses_smtp_password // empty')

# S3 credentials secret JSON (keys: accessKeyId, secretAccessKey)
S3_SECRET_JSON=""
for i in 1 2 3 4 5 6 7 8 9 10; do
  S3_SECRET_JSON=$(aws secretsmanager get-secret-value \
    --secret-id "$${S3_CREDENTIALS_SECRET_NAME}" \
    --region "$${S3_CREDENTIALS_SECRET_REGION}" \
    --query SecretString --output text 2>/dev/null) && break
  echo "Waiting for Secrets Manager S3 credentials (attempt $i/10)..."
  sleep 15
done
if [ -z "$${S3_SECRET_JSON}" ] || [ "$${S3_SECRET_JSON}" = "null" ]; then
  echo "ERROR: Could not get S3 credentials secret from Secrets Manager. Check IAM and secret name."
  exit 1
fi
S3_ACCESS_KEY_ID=$(echo "$${S3_SECRET_JSON}" | jq -r '.accessKeyId // empty')
S3_SECRET_ACCESS_KEY=$(echo "$${S3_SECRET_JSON}" | jq -r '.secretAccessKey // empty')

mkdir -p /opt/ghost
cd /opt/ghost

# Ghost config (values from Terraform; DB password and SES auth filled at runtime below)
# paths.contentPath must point at the volume so custom adapters (e.g. S3) in content/adapters are found
cat > config.production.json << 'GHOSTCONF'
{
  "url": "https://${domain_name}",
  "server": { "port": 2368, "host": "0.0.0.0" },
  "paths": { "contentPath": "/var/lib/ghost/content" },
  "database": {
    "client": "mysql",
    "connection": {
      "host": "${db_host}",
      "port": 3306,
      "user": "${db_username}",
      "password": "",
      "database": "${db_name}"
    }
  },
  "mail": {
    "transport": "SMTP",
    "options": {
      "host": "email-smtp.${ses_region}.amazonaws.com",
      "port": 587,
      "secure": false,
      "auth": { "user": "", "pass": "" }
    },
    "from": "${ses_from_email}"
  },
  "storage": {
    "active": "s3",
    "s3": {
      "bucket": "${s3_bucket}",
      "region": "${s3_region}",
      "accessKeyId": "",
      "secretAccessKey": "",
      "assetHost": "${cloudfront_url}",
      "staticFileURLPrefix": "content/images",
      "multipartUploadThresholdBytes": 5242880,
      "multipartChunkSizeBytes": 5242880
    },
    "media": {
      "adapter": "s3",
      "bucket": "${s3_bucket}",
      "region": "${s3_region}",
      "assetHost": "${cloudfront_url}",
      "staticFileURLPrefix": "content/media",
      "multipartUploadThresholdBytes": 5242880,
      "multipartChunkSizeBytes": 5242880
    },
    "files": {
      "adapter": "s3",
      "bucket": "${s3_bucket}",
      "region": "${s3_region}",
      "assetHost": "${cloudfront_url}",
      "staticFileURLPrefix": "content/files",
      "multipartUploadThresholdBytes": 5242880,
      "multipartChunkSizeBytes": 5242880
    }
  },
  "logging": { "level": "info", "transports": ["stdout"] }
}
GHOSTCONF

# DB password, SES auth, and S3 credentials from secrets (jq so special chars in secrets don't break JSON)
jq --arg p "$${DB_PASSWORD}" '.database.connection.password = $p' config.production.json > config.production.json.tmp && mv config.production.json.tmp config.production.json
jq --arg u "$${SES_USER}" --arg p "$${SES_PASS}" '.mail.options.auth.user = $u | .mail.options.auth.pass = $p' config.production.json > config.production.json.tmp && mv config.production.json.tmp config.production.json
jq --arg ak "$${S3_ACCESS_KEY_ID}" --arg sk "$${S3_SECRET_ACCESS_KEY}" '.storage.s3.accessKeyId = $ak | .storage.s3.secretAccessKey = $sk' config.production.json > config.production.json.tmp && mv config.production.json.tmp config.production.json

# Docker Compose: Ghost + Redis
cat > docker-compose.yml << 'COMPOSE'
services:
  ghost:
    image: ghost:${ghost_version}-alpine
    restart: unless-stopped
    command: ["node", "current/index.js"]
    environment:
      NODE_ENV: production
      url: https://${domain_name}
      GHOST_STORAGE_ADAPTER_S3_ACL: private
    volumes:
      - ./config.production.json:/var/lib/ghost/config.production.json
      - ghost-content:/var/lib/ghost/content
    ports:
      - "2368:2368"
    depends_on:
      - redis
  redis:
    image: redis:7-alpine
    restart: unless-stopped
    command: redis-server --appendonly yes
    volumes:
      - redis-data:/data
volumes:
  ghost-content:
  redis-data:
COMPOSE

# Caddy reverse proxy on port 80 (static binary – works on AL2023 without extra repos)
CADDY_VERSION="2.7.6"
if ! command -v caddy &>/dev/null; then
  curl -L "https://github.com/caddyserver/caddy/releases/download/v$${CADDY_VERSION}/caddy_$${CADDY_VERSION}_linux_amd64.tar.gz" -o /tmp/caddy.tar.gz
  tar -xzf /tmp/caddy.tar.gz -C /usr/bin caddy
  rm /tmp/caddy.tar.gz
  chmod +x /usr/bin/caddy
  groupadd --system caddy 2>/dev/null || true
  useradd --system --gid caddy --shell /usr/sbin/nologin caddy 2>/dev/null || true
  mkdir -p /etc/caddy
  mkdir -p /var/lib/caddy
  chown -R caddy:caddy /var/lib/caddy
  cat > /etc/systemd/system/caddy.service << 'CADDYUNIT'
[Unit]
Description=Caddy reverse proxy
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/caddy run --config /etc/caddy/Caddyfile --adapter caddyfile
Restart=on-failure
User=caddy
Group=caddy
Environment=HOME=/var/lib/caddy
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
CADDYUNIT
  systemctl daemon-reload
fi
# Serve domain with automatic HTTPS (Let's Encrypt). Requires ports 80 (ACME + redirect) and 443 (HTTPS).
cat > /etc/caddy/Caddyfile << 'CADDYEOF'
${domain_name} {
    reverse_proxy localhost:2368
}
CADDYEOF
systemctl enable caddy
systemctl start caddy

cd /opt/ghost
# Install S3 storage adapter before starting Ghost (Ghost requires adapter present when storage.active is s3)
sudo docker-compose run --rm ghost sh -c '\
  set -e; \
  mkdir -p /var/lib/ghost/content/adapters/storage; \
  cd /var/lib/ghost/content/adapters/storage; \
  npm install --silent ghost-storage-adapter-s3; \
  rm -rf s3; \
  cp -r node_modules/ghost-storage-adapter-s3 ./s3; \
  cd s3 && npm install --production --silent && cd ..; \
  chown -R node:node /var/lib/ghost/content \
'
sudo docker-compose up -d
