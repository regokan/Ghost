#!/bin/bash
set -e

exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

echo "=========================================="
echo "Ghost Blog EC2 Setup"
echo "=========================================="

# From Terraform
AWS_REGION="${aws_region}"
PROJECT_NAME="${project_name}"
ENVIRONMENT="${environment}"
DOMAIN_NAME="${domain_name}"
DB_HOST="${db_host}"
DB_NAME="${db_name}"
DB_USERNAME="${db_username}"
S3_BUCKET="${s3_bucket}"
S3_REGION="${s3_region}"
CLOUDFRONT_URL="${cloudfront_url}"
SES_REGION="${ses_region}"
SES_FROM_EMAIL="${ses_from_email}"
SES_CREDENTIALS_SECRET_NAME="${ses_credentials_secret_name}"
SES_CREDENTIALS_SECRET_REGION="${ses_credentials_secret_region}"

# System update and Docker
dnf update -y
dnf install -y docker unzip
systemctl enable docker
systemctl start docker

# Docker Compose
DOCKER_COMPOSE_VERSION="v2.24.0"
curl -L "https://github.com/docker/compose/releases/download/$${DOCKER_COMPOSE_VERSION}/docker-compose-linux-x86_64" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose
ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose

# AWS CLI v2 + jq for parsing secrets
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o awscliv2.zip
unzip -q awscliv2.zip && ./aws/install && rm -rf awscliv2.zip aws
dnf install -y jq 2>/dev/null || true

# DB password from SSM (retry: IAM instance profile can take a moment at boot)
DB_PASSWORD=""
for i in 1 2 3 4 5 6 7 8 9 10; do
  DB_PASSWORD=$(aws ssm get-parameter \
    --name "/$${PROJECT_NAME}/$${ENVIRONMENT}/db-password" \
    --with-decryption --query 'Parameter.Value' --output text --region "$${AWS_REGION}" 2>/dev/null) && break
  echo "Waiting for SSM (attempt $i/10)..."
  sleep 15
done
if [ -z "$${DB_PASSWORD}" ]; then
  echo "ERROR: Could not get DB password from SSM. Check IAM and parameter name."
  exit 1
fi

mkdir -p /opt/ghost
cd /opt/ghost

# Ghost config
cat > config.production.json << 'GHOSTCONF'
{
  "url": "https://DOMAIN_PLACEHOLDER",
  "server": { "port": 2368, "host": "0.0.0.0" },
  "database": {
    "client": "mysql",
    "connection": {
      "host": "DBHOST_PLACEHOLDER",
      "port": 3306,
      "user": "DBUSER_PLACEHOLDER",
      "password": "DBPASS_PLACEHOLDER",
      "database": "DBNAME_PLACEHOLDER"
    }
  },
  "mail": {
    "transport": "SMTP",
    "options": {
      "host": "email-smtp.SESREGION_PLACEHOLDER.amazonaws.com",
      "port": 587,
      "secure": false,
      "auth": { "user": "SESUSER_PLACEHOLDER", "pass": "SESPASS_PLACEHOLDER" }
    },
    "from": "SESFROM_PLACEHOLDER"
  },
  "storage": {
    "active": "s3",
    "s3": {
      "bucket": "S3BUCKET_PLACEHOLDER",
      "region": "S3REGION_PLACEHOLDER",
      "cdnUrl": "CDNURL_PLACEHOLDER",
      "staticFileURLPrefix": "content/images",
      "multipartUploadThresholdBytes": 5242880,
      "multipartChunkSizeBytes": 5242880
    },
    "media": {
      "adapter": "s3",
      "bucket": "S3BUCKET_PLACEHOLDER",
      "region": "S3REGION_PLACEHOLDER",
      "cdnUrl": "CDNURL_PLACEHOLDER",
      "staticFileURLPrefix": "content/media",
      "multipartUploadThresholdBytes": 5242880,
      "multipartChunkSizeBytes": 5242880
    },
    "files": {
      "adapter": "s3",
      "bucket": "S3BUCKET_PLACEHOLDER",
      "region": "S3REGION_PLACEHOLDER",
      "cdnUrl": "CDNURL_PLACEHOLDER",
      "staticFileURLPrefix": "content/files",
      "multipartUploadThresholdBytes": 5242880,
      "multipartChunkSizeBytes": 5242880
    }
  }
}
GHOSTCONF

# Replace placeholders (DB host may include :3306)
DB_HOST_ONLY="$${DB_HOST%%:*}"
sed -i "s|DOMAIN_PLACEHOLDER|$${DOMAIN_NAME}|g" config.production.json
sed -i "s|DBHOST_PLACEHOLDER|$${DB_HOST_ONLY}|g" config.production.json
sed -i "s|DBUSER_PLACEHOLDER|$${DB_USERNAME}|g" config.production.json
sed -i "s|DBPASS_PLACEHOLDER|$${DB_PASSWORD}|g" config.production.json
sed -i "s|DBNAME_PLACEHOLDER|$${DB_NAME}|g" config.production.json
sed -i "s|SESREGION_PLACEHOLDER|$${SES_REGION}|g" config.production.json
sed -i "s|SESFROM_PLACEHOLDER|$${SES_FROM_EMAIL}|g" config.production.json
sed -i "s|S3BUCKET_PLACEHOLDER|$${S3_BUCKET}|g" config.production.json
sed -i "s|S3REGION_PLACEHOLDER|$${S3_REGION}|g" config.production.json
sed -i "s|CDNURL_PLACEHOLDER|$${CLOUDFRONT_URL}|g" config.production.json

# SES SMTP from Secrets Manager (affine-secrets: ses_smtp_username, ses_smtp_password)
SES_JSON=$(aws secretsmanager get-secret-value --secret-id "$${SES_CREDENTIALS_SECRET_NAME}" --region "$${SES_CREDENTIALS_SECRET_REGION}" --query SecretString --output text 2>/dev/null || echo "{}")
if command -v jq &>/dev/null; then
  SES_USER=$(echo "$${SES_JSON}" | jq -r '.ses_smtp_username // empty')
  SES_PASS=$(echo "$${SES_JSON}" | jq -r '.ses_smtp_password // empty')
  jq --arg u "$${SES_USER}" --arg p "$${SES_PASS}" '.mail.options.auth.user = $u | .mail.options.auth.pass = $p' config.production.json > config.production.json.tmp && mv config.production.json.tmp config.production.json
else
  sed -i 's|SESUSER_PLACEHOLDER|""|g; s|SESPASS_PLACEHOLDER|""|g' config.production.json
fi

# Docker Compose: Ghost + Redis
cat > docker-compose.yml << 'COMPOSE'
services:
  ghost:
    image: ghost:5-alpine
    restart: unless-stopped
    environment:
      NODE_ENV: production
      url: https://DOMAIN_PLACEHOLDER
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
sed -i "s|DOMAIN_PLACEHOLDER|$${DOMAIN_NAME}|g" docker-compose.yml

# Caddy reverse proxy (optional - if not using ALB)
dnf install -y caddy 2>/dev/null || true
if command -v caddy &>/dev/null; then
  echo ":80 { reverse_proxy localhost:2368 }" > /etc/caddy/Caddyfile
  systemctl enable caddy
  systemctl start caddy 2>/dev/null || true
fi

cd /opt/ghost
sudo docker-compose up -d

# Install S3 storage adapter into the content volume and fix permissions
sudo docker-compose run --rm ghost sh -c '\
  set -e; \
  mkdir -p /var/lib/ghost/content/adapters/storage; \
  cd /var/lib/ghost/content/adapters/storage; \
  npm install --silent ghost-storage-adapter-s3; \
  rm -rf s3; \
  cp -r node_modules/ghost-storage-adapter-s3 ./s3; \
  chown -R node:node /var/lib/ghost/content; \
  if [ -d /var/lib/ghost/versions ]; then \
    for d in /var/lib/ghost/versions/*; do \
      [ -d "$d" ] || continue; \
      rm -rf "$d/content"; \
      ln -s /var/lib/ghost/content "$d/content"; \
    done; \
  fi \
'
