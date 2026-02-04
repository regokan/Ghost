# EC2 Instance for Ghost

# Get latest Amazon Linux 2023 AMI
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
}

# EC2 Instance
resource "aws_instance" "ghost" {
  ami                         = data.aws_ami.amazon_linux_2023.id
  instance_type               = var.ec2_instance_type
  key_name                    = aws_key_pair.ghost.key_name
  vpc_security_group_ids      = [aws_security_group.ec2.id]
  subnet_id                   = aws_subnet.public[0].id
  iam_instance_profile        = aws_iam_instance_profile.ec2.name
  user_data_replace_on_change = true

  root_block_device {
    volume_size           = var.ec2_volume_size
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  user_data = templatefile("${path.module}/templates/user-data.sh", {
    aws_region                    = var.aws_region
    project_name                  = var.project_name
    environment                   = var.environment
    domain_name                   = var.domain_name
    db_host                       = split(":", aws_db_instance.ghost.endpoint)[0]
    db_name                       = var.db_name
    db_username                   = var.db_username
    s3_bucket                     = aws_s3_bucket.content.id
    s3_region                     = var.aws_region
    cloudfront_url                = "https://${aws_cloudfront_distribution.content.domain_name}"
    ses_region                    = var.ses_region
    ses_from_email                = var.ses_from_email
    ses_credentials_secret_name   = var.ses_credentials_secret_name
    ses_credentials_secret_region = var.ses_credentials_secret_region
    ghost_version                 = var.ghost_version
    db_credentials_secret_name    = aws_secretsmanager_secret.db_credentials.name
    db_credentials_secret_region  = var.aws_region
  })

  tags = {
    Name = "${var.project_name}-ec2"
  }

  depends_on = [aws_db_instance.ghost, aws_key_pair.ghost, aws_secretsmanager_secret_version.db_credentials]
}

# Elastic IP for consistent public IP
resource "aws_eip" "ghost" {
  instance = aws_instance.ghost.id
  domain   = "vpc"

  tags = {
    Name = "${var.project_name}-eip"
  }
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "ghost" {
  name              = "/ghost/${var.environment}"
  retention_in_days = 30

  tags = {
    Name = "${var.project_name}-logs"
  }
}
