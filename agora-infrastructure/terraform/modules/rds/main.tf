locals {
  is_serverless = var.instance_class == "db.serverless"
  cluster_id    = "agora-${var.environment}-aurora"
}

# Random password for database master
resource "random_password" "db_master" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

# DB subnet group
resource "aws_db_subnet_group" "aurora" {
  name        = "agora-${var.environment}-aurora-subnets"
  description = "Database subnet group for Aurora PostgreSQL"
  subnet_ids  = var.subnet_ids

  tags = merge(var.tags, {
    Name = "agora-${var.environment}-aurora-subnets"
  })
}

# Parameter group
resource "aws_rds_cluster_parameter_group" "aurora" {
  name        = "agora-${var.environment}-aurora-params"
  family      = "aurora-postgresql15"
  description = "Aurora PostgreSQL parameter group for Agora"

  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }

  parameter {
    name  = "log_statement"
    value = "ddl"
  }

  parameter {
    name  = "log_min_duration_statement"
    value = "1000"
  }

  parameter {
    name         = "shared_preload_libraries"
    value        = "pg_stat_statements"
    apply_method = "pending-reboot"
  }

  tags = merge(var.tags, {
    Name = "agora-${var.environment}-aurora-params"
  })
}

# Aurora cluster
resource "aws_rds_cluster" "aurora" {
  cluster_identifier = local.cluster_id
  engine             = "aurora-postgresql"
  engine_mode        = var.engine_mode
  engine_version     = "15.4"
  database_name      = var.db_name
  master_username    = var.master_username
  master_password    = random_password.db_master.result

  db_subnet_group_name   = aws_db_subnet_group.aurora.name
  vpc_security_group_ids = [aws_security_group.aurora.id]

  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.aurora.name

  backup_retention_period = var.backup_retention_days
  preferred_backup_window = "03:00-04:00"
  copy_tags_to_snapshot   = true
  deletion_protection     = var.multi_az
  storage_encrypted       = true
  kms_key_id              = var.kms_key_id

  enabled_cloudwatch_logs_exports = [
    "postgresql",
  ]

  dynamic "serverlessv2_scaling_configuration" {
    for_each = local.is_serverless ? [1] : []
    content {
      min_capacity = var.serverless_min_capacity
      max_capacity = var.serverless_max_capacity
    }
  }

  tags = merge(var.tags, {
    Name = local.cluster_id
  })
}

variable "kms_key_id" {
  description = "KMS key ARN for storage encryption"
  type        = string
  default     = null
}

# Aurora instances
resource "aws_rds_cluster_instance" "writer" {
  identifier         = "${local.cluster_id}-writer"
  cluster_identifier = aws_rds_cluster.aurora.id
  instance_class     = var.instance_class
  engine             = aws_rds_cluster.aurora.engine
  engine_version     = aws_rds_cluster.aurora.engine_version

  performance_insights_enabled          = true
  performance_insights_retention_period = 7

  auto_minor_version_upgrade = true
  monitoring_role_arn        = var.monitoring_role_arn
  monitoring_interval        = 10

  tags = merge(var.tags, {
    Name = "${local.cluster_id}-writer"
  })
}

variable "monitoring_role_arn" {
  description = "IAM role ARN for enhanced monitoring"
  type        = string
  default     = null
}

# Reader replicas
resource "aws_rds_cluster_instance" "reader" {
  count              = var.reader_count
  identifier         = "${local.cluster_id}-reader-${count.index + 1}"
  cluster_identifier = aws_rds_cluster.aurora.id
  instance_class     = var.instance_class
  engine             = aws_rds_cluster.aurora.engine
  engine_version     = aws_rds_cluster.aurora.engine_version

  performance_insights_enabled          = true
  performance_insights_retention_period = 7

  auto_minor_version_upgrade = true
  monitoring_role_arn        = var.monitoring_role_arn
  monitoring_interval        = 10

  tags = merge(var.tags, {
    Name = "${local.cluster_id}-reader-${count.index + 1}"
  })
}

# Secrets Manager for DB credentials
resource "aws_secretsmanager_secret" "db_credentials" {
  name        = "agora-${var.environment}-db-credentials"
  description = "Aurora PostgreSQL master credentials for Agora ${var.environment}"
  kms_key_id  = var.kms_key_id

  tags = merge(var.tags, {
    Name = "agora-${var.environment}-db-credentials"
  })
}

resource "aws_secretsmanager_secret_version" "db_credentials" {
  secret_id = aws_secretsmanager_secret.db_credentials.id
  secret_string = jsonencode({
    username = var.master_username
    password = random_password.db_master.result
    engine   = "aurora-postgresql"
    host     = aws_rds_cluster.aurora.endpoint
    port     = aws_rds_cluster.aurora.port
    dbname   = var.db_name
  })
}

# Enhanced monitoring IAM role
resource "aws_iam_role" "rds_monitoring" {
  name = "agora-${var.environment}-rds-monitoring"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "monitoring.rds.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  force_detach_policies = true

  tags = merge(var.tags, {
    Name = "agora-${var.environment}-rds-monitoring"
  })
}

resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
  role       = aws_iam_role.rds_monitoring.name
}
