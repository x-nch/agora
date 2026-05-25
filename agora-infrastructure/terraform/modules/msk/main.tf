locals {
  # Express requires 3 AZs, serverless can work with 2
  is_express  = var.broker_type == "express"
  broker_name = "agora-${var.environment}-msk"
}

# Security group for MSK
resource "aws_security_group" "msk" {
  name        = "agora-${var.environment}-msk"
  description = "Security group for MSK cluster"
  vpc_id      = var.vpc_id

  ingress {
    description     = "IAM auth from EKS cluster"
    from_port       = 9098
    to_port         = 9098
    protocol        = "tcp"
    security_groups = var.eks_cluster_security_group_id != null ? [var.eks_cluster_security_group_id] : []
    cidr_blocks     = var.eks_cluster_security_group_id != null ? [] : [data.aws_vpc.selected.cidr_block]
  }

  ingress {
    description     = "TLS from EKS cluster"
    from_port       = 9096
    to_port         = 9096
    protocol        = "tcp"
    security_groups = var.eks_cluster_security_group_id != null ? [var.eks_cluster_security_group_id] : []
    cidr_blocks     = var.eks_cluster_security_group_id != null ? [] : [data.aws_vpc.selected.cidr_block]
  }

  ingress {
    description     = "ZooKeeper from EKS cluster (Express only)"
    from_port       = 2181
    to_port         = 2181
    protocol        = "tcp"
    security_groups = var.eks_cluster_security_group_id != null ? [var.eks_cluster_security_group_id] : []
    cidr_blocks     = var.eks_cluster_security_group_id != null ? [] : [data.aws_vpc.selected.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "agora-${var.environment}-msk-sg"
  })
}

data "aws_vpc" "selected" {
  id = var.vpc_id
}

# MSK Express cluster (staging/production)
resource "aws_msk_cluster" "express" {
  count                  = local.is_express ? 1 : 0
  cluster_name           = local.broker_name
  kafka_version          = var.kafka_version
  number_of_broker_nodes = var.broker_node_count

  broker_node_group_info {
    instance_type   = var.instance_type
    client_subnets  = var.subnet_ids
    security_groups = [aws_security_group.msk.id]

    storage_info {
      ebs_storage_info {
        provisioned_throughput {
          enabled           = true
          volume_throughput = 250
        }
      }
    }
  }

  encryption_info {
    encryption_in_transit {
      client_broker = "TLS"
      in_cluster    = true
    }
  }

  client_authentication {
    unauthenticated = false
    sasl {
      iam = true
    }
  }

  configuration_info {
    arn      = aws_msk_configuration.express_config[0].arn
    revision = aws_msk_configuration.express_config[0].latest_revision
  }

  logging_info {
    broker_logs {
      cloudwatch_logs {
        enabled   = true
        log_group = aws_cloudwatch_log_group.msk_broker[0].name
      }
    }
  }

  enhanced_monitoring = "PER_TOPIC_PER_PARTITION"

  tags = merge(var.tags, {
    Name = local.broker_name
  })
}

resource "aws_msk_configuration" "express_config" {
  count          = local.is_express ? 1 : 0
  name           = "${local.broker_name}-config"
  kafka_versions = [var.kafka_version]

  server_properties = <<-EOF
auto.create.topics.enable = false
default.replication.factor = 3
min.insync.replicas = 2
num.io.threads = 8
num.network.threads = 8
log.retention.hours = 168
log.segment.bytes = 1073741824
compression.type = snappy
EOF
}

resource "aws_cloudwatch_log_group" "msk_broker" {
  count             = local.is_express ? 1 : 0
  name              = "/aws/msk/${local.broker_name}/broker"
  retention_in_days = 30

  tags = merge(var.tags, {
    Name = "${local.broker_name}-broker-logs"
  })
}

# MSK Serverless cluster (dev)
resource "aws_msk_serverless_cluster" "serverless" {
  count        = local.is_express ? 0 : 1
  cluster_name = local.broker_name

  client_authentication {
    sasl {
      iam {
        enabled = true
      }
    }
  }

  vpc_config {
    subnet_ids         = var.subnet_ids
    security_group_ids = [aws_security_group.msk.id]
  }

  tags = merge(var.tags, {
    Name = local.broker_name
  })
}
