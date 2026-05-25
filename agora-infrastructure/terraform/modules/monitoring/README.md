# Monitoring Module
# AWS-level infrastructure monitoring — CloudWatch dashboards, SNS alerting, AMP workspace.

## Phase Boundary
This module handles **AWS infrastructure-level monitoring** (CloudWatch, SNS, AMP).
**Prometheus + Grafana** are deployed inside Kubernetes in Phase 2.
The AMP workspace created here receives metrics from both CloudWatch metric streams and the K8s Prometheus.

## What It Creates
- CloudWatch dashboards: EKS, MSK, Aurora
- SNS topics: critical (PagerDuty), warning (Slack), info (log)
- CloudWatch composite alarms: SLO-based alerting
- Amazon Managed Prometheus workspace
- Email subscription for critical alerts

## Required Inputs
| Variable | Type | Description |
|----------|------|-------------|
| `environment` | `string` | Environment name |
| `alarm_notification_email` | `string` | Email for alerts |
| `sns_topic_prefix` | `string` | SNS topic name prefix |
| `amp_workspace_alias` | `string` | AMP workspace alias |

## Outputs
| Output | Description |
|--------|-------------|
| `sns_critical_topic_arn` | Critical SNS topic ARN |
| `sns_warning_topic_arn` | Warning SNS topic ARN |
| `sns_info_topic_arn` | Info SNS topic ARN |
| `amp_workspace_id` | AMP workspace ID |
| `dashboard_arns` | CloudWatch dashboard names |

## Example
```hcl
module "monitoring" {
  source = "../modules/monitoring"

  environment             = "production"
  alarm_notification_email = "prod-alerts@agora.woven-city.jp"
  sns_topic_prefix        = "agora-production"
  amp_workspace_alias     = "agora-production"
}
```
