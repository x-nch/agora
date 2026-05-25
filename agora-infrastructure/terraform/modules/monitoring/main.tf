# Monitoring module — CloudWatch dashboards, SNS alerting, AMP workspace
# NOTE: Prometheus + Grafana are deployed inside Kubernetes (Phase 2)

# SNS Topics — tiered alerting
resource "aws_sns_topic" "critical" {
  name = "${var.sns_topic_prefix}-critical"

  tags = merge(var.tags, {
    Name = "${var.sns_topic_prefix}-critical"
  })
}

resource "aws_sns_topic" "warning" {
  name = "${var.sns_topic_prefix}-warning"

  tags = merge(var.tags, {
    Name = "${var.sns_topic_prefix}-warning"
  })
}

resource "aws_sns_topic" "info" {
  name = "${var.sns_topic_prefix}-info"

  tags = merge(var.tags, {
    Name = "${var.sns_topic_prefix}-info"
  })
}

# Email subscription for critical alerts
resource "aws_sns_topic_subscription" "critical_email" {
  topic_arn = aws_sns_topic.critical.arn
  protocol  = "email"
  endpoint  = var.alarm_notification_email
}

# DR-specific SNS topic for state lock and backup alerts
resource "aws_sns_topic" "dr" {
  name = "${var.sns_topic_prefix}-dr"

  tags = merge(var.tags, {
    Name = "${var.sns_topic_prefix}-dr"
  })
}

# Amazon Managed Prometheus workspace
resource "aws_prometheus_workspace" "main" {
  alias = var.amp_workspace_alias

  tags = merge(var.tags, {
    Name = var.amp_workspace_alias
  })
}

# CloudWatch Dashboards

resource "aws_cloudwatch_dashboard" "eks" {
  dashboard_name = "${var.sns_topic_prefix}-eks"

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/EKS", "node_count", { stat = "Average" }],
            ["AWS/EKS", "pod_capacity", { stat = "Average" }],
          ]
          period = 300
          stat   = "Average"
          region = data.aws_region.current.name
          title  = "EKS Overview"
        }
      },
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/EKS", "apiserver_request_duration_seconds_bucket", { stat = "p99" }],
          ]
          period = 300
          stat   = "p99"
          region = data.aws_region.current.name
          title  = "API Server Latency P99"
        }
      },
    ]
  })
}

resource "aws_cloudwatch_dashboard" "msk" {
  dashboard_name = "${var.sns_topic_prefix}-msk"

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/Kafka", "CpuUser", { stat = "Average" }],
            ["AWS/Kafka", "CpuSystem", { stat = "Average" }],
          ]
          period = 300
          stat   = "Average"
          region = data.aws_region.current.name
          title  = "MSK Broker CPU"
        }
      },
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/Kafka", "BytesInPerSec", { stat = "Sum" }],
            ["AWS/Kafka", "BytesOutPerSec", { stat = "Sum" }],
          ]
          period = 300
          stat   = "Sum"
          region = data.aws_region.current.name
          title  = "MSK Network Throughput"
        }
      },
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/Kafka", "MaxOffsetLag", { stat = "Maximum" }],
          ]
          period = 300
          stat   = "Maximum"
          region = data.aws_region.current.name
          title  = "MSK Consumer Lag"
        }
      },
    ]
  })
}

resource "aws_cloudwatch_dashboard" "aurora" {
  dashboard_name = "${var.sns_topic_prefix}-aurora"

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/RDS", "CPUUtilization", { stat = "Average" }],
          ]
          period = 300
          stat   = "Average"
          region = data.aws_region.current.name
          title  = "Aurora CPU"
        }
      },
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/RDS", "DatabaseConnections", { stat = "Average" }],
          ]
          period = 300
          stat   = "Average"
          region = data.aws_region.current.name
          title  = "Aurora Connections"
        }
      },
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/RDS", "AuroraReplicaLagMaximum", { stat = "Maximum" }],
          ]
          period = 300
          stat   = "Maximum"
          region = data.aws_region.current.name
          title  = "Aurora Replica Lag"
        }
      },
    ]
  })
}

# Composite CloudWatch alarms
# DR Dashboard
resource "aws_cloudwatch_dashboard" "dr" {
  dashboard_name = "${var.sns_topic_prefix}-dr"

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric"
        properties = {
          metrics = [
            ["Agora/DR", "StateBackupAgeSeconds", { stat = "Maximum", label = "State Backup Age" }],
            ["Agora/DR", "StaleLocks", { stat = "Sum", label = "Stale Locks" }],
          ]
          period = 300
          stat   = "Maximum"
          region = data.aws_region.current.name
          title  = "DR Readiness"
        }
      },
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/DynamoDB", "ConditionalCheckFailedRequests", { stat = "Sum", label = "Lock Contention" }],
          ]
          period = 300
          stat   = "Sum"
          region = data.aws_region.current.name
          title  = "Terraform Lock Contention"
        }
      },
    ]
  })
}

resource "aws_cloudwatch_composite_alarm" "eks_critical" {
  alarm_name        = "${var.sns_topic_prefix}-eks-critical"
  alarm_description = "EKS cluster has critical issues"
  alarm_rule        = "ALARM(\"${aws_cloudwatch_metric_alarm.eks_node_down.alarm_name}\")"

  alarm_actions = [aws_sns_topic.critical.arn]
}

resource "aws_cloudwatch_metric_alarm" "eks_node_down" {
  alarm_name          = "${var.sns_topic_prefix}-eks-node-down"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "node_count"
  namespace           = "AWS/EKS"
  period              = "300"
  statistic           = "Average"
  threshold           = "2"
  alarm_description   = "EKS node count below threshold"

  alarm_actions = [aws_sns_topic.critical.arn]
}

resource "aws_cloudwatch_metric_alarm" "msk_broker_cpu" {
  alarm_name          = "${var.sns_topic_prefix}-msk-broker-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "3"
  metric_name         = "CpuUser"
  namespace           = "AWS/Kafka"
  period              = "300"
  statistic           = "Average"
  threshold           = "70"
  alarm_description   = "MSK broker CPU > 70%"

  alarm_actions = [aws_sns_topic.warning.arn]
}

resource "aws_cloudwatch_metric_alarm" "msk_consumer_lag" {
  alarm_name          = "${var.sns_topic_prefix}-msk-consumer-lag"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "MaxOffsetLag"
  namespace           = "AWS/Kafka"
  period              = "300"
  statistic           = "Maximum"
  threshold           = "1000"
  alarm_description   = "MSK consumer lag > 1000"

  alarm_actions = [aws_sns_topic.critical.arn]
}

resource "aws_cloudwatch_metric_alarm" "aurora_cpu" {
  alarm_name          = "${var.sns_topic_prefix}-aurora-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "3"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = "70"
  alarm_description   = "Aurora CPU > 70%"

  alarm_actions = [aws_sns_topic.warning.arn]
}

resource "aws_cloudwatch_metric_alarm" "aurora_replica_lag" {
  alarm_name          = "${var.sns_topic_prefix}-aurora-replica-lag"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "AuroraReplicaLagMaximum"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Maximum"
  threshold           = "1000"
  alarm_description   = "Aurora replica lag > 1000ms"

  alarm_actions = [aws_sns_topic.warning.arn]
}

# DR: Stale Terraform state lock alarm
resource "aws_cloudwatch_metric_alarm" "terraform_stale_lock" {
  alarm_name          = "${var.sns_topic_prefix}-terraform-stale-lock"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "3"
  metric_name         = "ConditionalCheckFailedRequests"
  namespace           = "AWS/DynamoDB"
  period              = "300"
  statistic           = "Sum"
  threshold           = "50"
  alarm_description   = "Terraform state lock contention detected — possible stale lock"

  alarm_actions = [aws_sns_topic.dr.arn]
}

# DR: State backup age alarm (fires if backup CronJob hasn't run)
resource "aws_cloudwatch_metric_alarm" "state_backup_age" {
  alarm_name          = "${var.sns_topic_prefix}-state-backup-age"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "3"
  metric_name         = "BackupAgeSeconds"
  namespace           = "Agora/DR"
  period              = "86400"
  statistic           = "Maximum"
  threshold           = "90000"
  alarm_description   = "State backup age > 25 hours — backup may have failed"

  alarm_actions = [aws_sns_topic.dr.arn]
}

data "aws_region" "current" {}
