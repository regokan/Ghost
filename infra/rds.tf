# RDS MySQL Instance for Ghost

resource "aws_db_instance" "ghost" {
  identifier = "${var.project_name}-db"

  # Engine
  engine                = "mysql"
  engine_version        = "8.0"
  instance_class        = var.db_instance_class
  allocated_storage     = var.db_allocated_storage
  max_allocated_storage = 100 # Enable autoscaling up to 100GB

  # Database
  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  # Network
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false
  multi_az               = false # Single AZ for cost savings

  # Storage
  storage_type      = "gp3"
  storage_encrypted = true

  # Backup
  backup_retention_period = 7
  backup_window           = "03:00-04:00"
  maintenance_window      = "Mon:04:00-Mon:05:00"

  # Performance Insights not supported on db.t4g.micro
  performance_insights_enabled = false

  # Other settings
  auto_minor_version_upgrade = true
  deletion_protection        = true # Prevent accidental deletion
  skip_final_snapshot        = false
  final_snapshot_identifier  = "${var.project_name}-final-snapshot"

  # Parameter group for MySQL 8.0 optimizations
  parameter_group_name = aws_db_parameter_group.ghost.name

  tags = {
    Name = "${var.project_name}-db"
  }
}

# Custom parameter group for Ghost optimizations
resource "aws_db_parameter_group" "ghost" {
  name   = "${var.project_name}-mysql80"
  family = "mysql8.0"

  description = "MySQL 8.0 parameter group optimized for Ghost"

  # Character set for proper Unicode support
  parameter {
    name  = "character_set_server"
    value = "utf8mb4"
  }

  parameter {
    name  = "collation_server"
    value = "utf8mb4_unicode_ci"
  }

  # Performance tuning for small instance
  parameter {
    name  = "max_connections"
    value = "100"
  }

  parameter {
    name         = "innodb_buffer_pool_size"
    value        = "{DBInstanceClassMemory*3/4}"
    apply_method = "pending-reboot"
  }

  tags = {
    Name = "${var.project_name}-mysql80-params"
  }
}
