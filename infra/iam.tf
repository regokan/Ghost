# IAM Roles and Policies

# EC2 Instance Role
resource "aws_iam_role" "ec2" {
  name = "${var.project_name}-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-ec2-role"
  }
}

# EC2 Instance Profile
resource "aws_iam_instance_profile" "ec2" {
  name = "${var.project_name}-ec2-profile"
  role = aws_iam_role.ec2.name
}

# S3 Access Policy for Ghost content
resource "aws_iam_role_policy" "ec2_s3" {
  name = "${var.project_name}-ec2-s3-policy"
  role = aws_iam_role.ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = [
          aws_s3_bucket.content.arn,
          "${aws_s3_bucket.content.arn}/*"
        ]
      }
    ]
  })
}

# SES Send Email Policy
resource "aws_iam_role_policy" "ec2_ses" {
  name = "${var.project_name}-ec2-ses-policy"
  role = aws_iam_role.ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ses:SendEmail",
          "ses:SendRawEmail"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "ses:FromAddress" = var.ses_from_email
          }
        }
      }
    ]
  })
}

# SSM Parameter Store Access (for secrets)
resource "aws_iam_role_policy" "ec2_ssm" {
  name = "${var.project_name}-ec2-ssm-policy"
  role = aws_iam_role.ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:GetParametersByPath"
        ]
        Resource = "arn:aws:ssm:${var.aws_region}:*:parameter/${var.project_name}/${var.environment}/*"
      }
    ]
  })
}

# CloudWatch Logs Policy
resource "aws_iam_role_policy" "ec2_cloudwatch" {
  name = "${var.project_name}-ec2-cloudwatch-policy"
  role = aws_iam_role.ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = "arn:aws:logs:${var.aws_region}:*:log-group:/ghost/*"
      }
    ]
  })
}

# Secrets Manager: read SES SMTP credentials
resource "aws_iam_role_policy" "ec2_secrets_ses" {
  name = "${var.project_name}-ec2-secrets-ses-policy"
  role = aws_iam_role.ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = "arn:aws:secretsmanager:${var.ses_credentials_secret_region}:*:secret:${var.ses_credentials_secret_name}*"
      }
    ]
  })
}

# Secrets Manager: read DB credentials (Terraform-created secret)
resource "aws_iam_role_policy" "ec2_secrets_db" {
  name = "${var.project_name}-ec2-secrets-db-policy"
  role = aws_iam_role.ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = aws_secretsmanager_secret.db_credentials.arn
      }
    ]
  })
}

# Secrets Manager: read S3 credentials (Terraform-created secret)
resource "aws_iam_role_policy" "ec2_secrets_s3" {
  name = "${var.project_name}-ec2-secrets-s3-policy"
  role = aws_iam_role.ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = aws_secretsmanager_secret.s3_credentials.arn
      }
    ]
  })
}

# SSM Session Manager (for secure shell access without SSH)
resource "aws_iam_role_policy_attachment" "ec2_ssm_managed" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}
