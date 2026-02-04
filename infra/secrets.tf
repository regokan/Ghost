## Secrets Manager

# DB credentials secret (separate from SMTP secret); name derived from project
resource "aws_secretsmanager_secret" "db_credentials" {
  name        = "${var.project_name}/${var.environment}/db-credentials"
  description = "Ghost DB credentials JSON (key: db_password)"

  tags = {
    Name = "${var.project_name}-db-credentials"
  }
}

resource "aws_secretsmanager_secret_version" "db_credentials" {
  secret_id = aws_secretsmanager_secret.db_credentials.id
  secret_string = jsonencode({
    db_password = var.db_password
  })
}

# S3 credentials secret (for ghost-storage-adapter-s3)
# NOTE: Values come from Terraform variables and are stored encrypted in Secrets Manager.
resource "aws_secretsmanager_secret" "s3_credentials" {
  name        = "${var.project_name}/${var.environment}/s3-credentials"
  description = "Ghost S3 credentials JSON (keys: accessKeyId, secretAccessKey)"

  tags = {
    Name = "${var.project_name}-s3-credentials"
  }
}

resource "aws_secretsmanager_secret_version" "s3_credentials" {
  secret_id = aws_secretsmanager_secret.s3_credentials.id
  secret_string = jsonencode({
    accessKeyId     = var.s3_access_key_id
    secretAccessKey = var.s3_secret_access_key
  })
}
