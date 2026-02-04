# Ghost Blog AWS Infrastructure

Terraform configuration for deploying Ghost blog on AWS.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                   EC2 t3.small (2GB RAM)                    │
│  ┌────────────┐  ┌─────────────┐  ┌─────────────┐          │
│  │   Ghost    │  │    Redis    │  │    Caddy    │          │
│  │  (Docker)  │  │   (Docker)  │  │   (Docker)  │          │
│  └────────────┘  └─────────────┘  └─────────────┘          │
└─────────────────────────────────────────────────────────────┘
         │                                    
         ▼                                    
┌─────────────────┐    ┌─────────────────┐    
│  RDS t4g.micro  │    │       S3        │    
│   (MySQL 8.0)   │    │   + CloudFront  │    
│      1GB RAM    │    │                 │    
└─────────────────┘    └─────────────────┘    
```

## Cost Estimate

| Service | Monthly Cost |
|---------|--------------|
| EC2 t3.small | ~$15 |
| RDS db.t4g.micro | ~$12 |
| S3 + CloudFront | ~$2-5 |
| Elastic IP | ~$3.65 |
| **Total** | **~$33-36/month** |

## Prerequisites

1. **AWS CLI** configured with appropriate credentials
2. **Terraform** >= 1.0 installed
3. **Domain** with DNS access (for pointing to EC2 IP)
4. **SES** verified domain/email for transactional emails

Terraform creates the EC2 key pair and writes the private key to **infra/{project_name}-environment-key.pem** at apply (file is gitignored). A copy is also stored in Secrets Manager as backup.

## Quick Start

### 1. Configure Variables

```bash
cd infra
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values
```

### 2. Initialize Terraform

```bash
terraform init
```

### 3. Review Plan

```bash
terraform plan
```

### 4. Deploy

```bash
terraform apply
```

### 5. Configure DNS

Add an A record where your domain is managed (Squarespace, Cloudflare, Namecheap, etc.):

- **Type:** A  
- **Name:** `blog` (or the subdomain you use)  
- **Value:** the EC2 public IP from `terraform output ec2_public_ip`

No Route53 is required—use your existing DNS provider.

### 6. SES SMTP (transactional email) – automatic

SES SMTP credentials are read from **AWS Secrets Manager** at instance boot. Set `ses_credentials_secret_name` and ensure that secret in the configured region contains:

- **`ses_smtp_user`** (or `SES_SMTP_USER`) – SES SMTP username  
- **`ses_smtp_password`** (or `SES_SMTP_PASSWORD`) – SES SMTP password  

User-data fetches the secret and injects these into Ghost’s config. No manual edit on the server is needed.

### 7. SSH key

Terraform **creates the key and writes it locally** when you run `terraform apply`. The file `infra/ghost-key.pem` is created (or updated) at apply time and is gitignored. No separate retrieve step.

If you lose the file, you can get it from Secrets Manager: `terraform output ec2_ssh_key_secret_name` then use AWS CLI `get-secret-value` for that secret.

### 8. Access Ghost Admin

Visit `https://your-domain.com/ghost/` to set up your Ghost admin account. No need to SSH/SSM unless you want to check logs or change something on the server.

## Connecting to EC2

### Via SSH

After `terraform apply`, the key is at `infra/${project_name}-${environment}.pem`. From `infra/`:

```bash
cd infra
ssh -i ${project_name}-${environment}.pem ec2-user@<EC2_PUBLIC_IP>
```

Or run: `terraform output ssh_connect_command` and use that.

## Managing Ghost

```bash
# Connect to EC2 first, then:
cd /opt/ghost

# View logs
sudo docker-compose logs -f

# Restart Ghost
sudo docker-compose restart ghost

# Restart all services
sudo docker-compose restart

# Update Ghost
sudo docker-compose pull ghost
sudo docker-compose up -d
```

## Mailgun for Newsletters (Future)

When ready to enable newsletters:

1. Sign up at [mailgun.com](https://mailgun.com)
2. Add your domain and verify DNS records
3. Get API key from Mailgun dashboard
4. Add to Ghost config:

```json
{
  "bulkEmail": {
    "mailgun": {
      "apiKey": "your-mailgun-api-key",
      "domain": "mg.yourdomain.com",
      "baseUrl": "https://api.mailgun.net/v3"
    }
  }
}
```

5. Restart Ghost

## Backups

### Database (RDS)
- Automated daily backups with 7-day retention
- Point-in-time recovery enabled

### Content (S3)
- Versioning enabled
- Old versions deleted after 30 days

### Manual Backup

```bash
# Export Ghost content
cd /opt/ghost
sudo docker-compose exec ghost ghost backup
```

## Destroying Infrastructure

```bash
# First, disable deletion protection on RDS (in AWS Console or via CLI)
terraform destroy
```

## Troubleshooting

### Ghost not starting
```bash
cd /opt/ghost
sudo docker-compose logs ghost
```

### Database connection issues
```bash
# Check RDS security group allows EC2
# Check database credentials in config.production.json
```

### SSL certificate issues
```bash
# Caddy auto-provisions Let's Encrypt certificates
# Check Caddy logs:
sudo docker-compose logs caddy
```

### View all logs
```bash
cd /opt/ghost
sudo docker-compose logs -f
```

## Security Notes

- RDS is in private subnets (no public access)
- Database password stored in SSM Parameter Store
- S3 bucket blocks public access (CloudFront serves content)
- SSL/TLS handled by Caddy with Let's Encrypt
- SSM Session Manager available (no need to open SSH port)
