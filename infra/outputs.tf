# Terraform Outputs

# EC2 Outputs
output "ec2_public_ip" {
  description = "Public IP of the Ghost EC2 instance"
  value       = aws_eip.ghost.public_ip
}

output "ec2_instance_id" {
  description = "Instance ID of the Ghost EC2 instance"
  value       = aws_instance.ghost.id
}

# RDS Outputs
output "rds_endpoint" {
  description = "RDS instance endpoint"
  value       = aws_db_instance.ghost.endpoint
}

output "rds_port" {
  description = "RDS instance port"
  value       = aws_db_instance.ghost.port
}

# S3 Outputs
output "s3_bucket_name" {
  description = "S3 bucket name for Ghost content"
  value       = aws_s3_bucket.content.id
}

output "s3_bucket_arn" {
  description = "S3 bucket ARN"
  value       = aws_s3_bucket.content.arn
}

# CloudFront Outputs
output "cloudfront_domain" {
  description = "CloudFront distribution domain name"
  value       = aws_cloudfront_distribution.content.domain_name
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID"
  value       = aws_cloudfront_distribution.content.id
}

# Connection Information
output "ghost_url" {
  description = "URL to access Ghost"
  value       = "https://${var.domain_name}"
}

output "ghost_admin_url" {
  description = "URL to access Ghost Admin"
  value       = "https://${var.domain_name}/ghost/"
}

# SSH key in Secrets Manager (retrieve when you need to SSH)
output "ec2_ssh_key_path" {
  description = "Path to SSH private key (created by Terraform at apply; gitignored)"
  value       = "${path.module}/ghost-key.pem"
}

output "ec2_ssh_key_secret_name" {
  description = "Secrets Manager secret name (backup if you lose the local key)"
  value       = aws_secretsmanager_secret.ec2_private_key.name
}

output "ssh_connect_command" {
  description = "Command to SSH to EC2 (run from infra/; key is at ghost-key.pem after apply)"
  value       = "ssh -i ghost-key.pem ec2-user@${aws_eip.ghost.public_ip}"
}

# Database Password Location
output "db_password_ssm_path" {
  description = "SSM Parameter Store path for database password"
  value       = aws_ssm_parameter.db_password.name
}

# Next Steps
output "next_steps" {
  description = "Next steps after deployment"
  value       = <<-EOT

    ============================================
    Ghost Deployment Complete!
    ============================================

    1. Point your domain to the EC2 public IP:
       Domain: ${var.domain_name}
       IP: ${aws_eip.ghost.public_ip}

    2. Wait for DNS propagation (5-30 minutes)

    3. Connect via SSH (from infra/; key at ghost-key.pem after apply):
       ssh -i ghost-key.pem ec2-user@${aws_eip.ghost.public_ip}

    4. Check Ghost status:
       sudo docker compose -f /opt/ghost/docker-compose.yml logs -f

    5. Access Ghost Admin:
       https://${var.domain_name}/ghost/

    Content CDN: https://${aws_cloudfront_distribution.content.domain_name}

  EOT
}
