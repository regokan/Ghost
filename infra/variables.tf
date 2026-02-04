# Variables for Ghost Infrastructure

variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "ap-southeast-2"
}

variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
  default     = "ghost-blog"
}

variable "environment" {
  description = "Environment (dev, staging, prod)"
  type        = string
  default     = "prod"
}

# Domain Configuration
variable "domain_name" {
  description = "Primary domain for the blog (e.g., blog.example.com)"
  type        = string
}

# EC2 Configuration
variable "ec2_instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.small" # 2 vCPU, 2GB RAM
}

variable "ec2_volume_size" {
  description = "Root volume size in GB (must be >= 30 for Amazon Linux 2023 AMI)"
  type        = number
  default     = 30
}

# RDS Configuration
variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t4g.micro" # 2 vCPU, 1GB RAM - cheapest option
}

variable "db_allocated_storage" {
  description = "RDS allocated storage in GB"
  type        = number
  default     = 20
}

variable "db_name" {
  description = "Database name"
  type        = string
  default     = "ghost"
}

variable "db_username" {
  description = "Database master username"
  type        = string
  default     = "ghost_admin"
}

variable "db_password" {
  description = "Database master password (stored in Secrets Manager; used for RDS and EC2 bootstrapping)"
  type        = string
  sensitive   = true
}

# S3 Configuration
variable "s3_bucket_name" {
  description = "S3 bucket name for Ghost content (must be globally unique)"
  type        = string
}

variable "s3_access_key_id" {
  description = "AWS access key ID for S3 uploads (IAM user with access limited to the Ghost content bucket)"
  type        = string
  sensitive   = true
}

variable "s3_secret_access_key" {
  description = "AWS secret access key for S3 uploads (matches s3_access_key_id; stored in Secrets Manager)"
  type        = string
  sensitive   = true
}

# Email Configuration
variable "ses_region" {
  description = "AWS region for SES (where SES is configured)"
  type        = string
  default     = "us-east-1"
}

variable "ses_from_email" {
  description = "Email address for sending transactional emails via SES"
  type        = string
}

variable "ses_credentials_secret_name" {
  description = "Secrets Manager secret name containing SES SMTP credentials (keys: ses_smtp_user, ses_smtp_password)"
  type        = string
}

variable "ses_credentials_secret_region" {
  description = "AWS region where the SES credentials secret is stored"
  type        = string
}

# Network Configuration
variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "allowed_ssh_cidrs" {
  description = "CIDR blocks allowed to SSH to EC2 (your IP address)"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# Ghost Configuration
variable "ghost_version" {
  description = "Ghost version to deploy (Docker image tag, e.g. 6.16.1 or 6)"
  type        = string
  default     = "6.16.1"
}
