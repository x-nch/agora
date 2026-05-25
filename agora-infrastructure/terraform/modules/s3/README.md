# S3 Module
# Creates 4 S3 buckets with KMS encryption, versioning, lifecycle policies, and TLS enforcement.

## What It Creates
| Bucket | Purpose | Lifecycle |
|--------|---------|-----------|
| data-lake | Kafka archives, processed data | 30d → IA → Glacier 90d → delete 7yr |
| app-logs | CloudTrail, flow logs, ALB logs | 7d → Glacier → delete 1yr |
| access-logs | S3 server access logs | 90d → Glacier → delete 7yr |
| backups | Terraform state, DR artifacts | 30d → Glacier → delete 3yr |

## Features
- KMS encryption (SSE-KMS) with bucket key
- Versioning enabled on all buckets
- Block public access (account + bucket)
- TLS enforcement bucket policy
- Lifecycle policies for cost optimisation

## Required Inputs
| Variable | Type | Description |
|----------|------|-------------|
| `environment` | `string` | Environment name |
| `bucket_prefix` | `string` | Bucket name prefix |

## Outputs
| Output | Description |
|--------|-------------|
| `data_lake_bucket_arn` | Data lake bucket ARN |
| `app_logs_bucket_arn` | App logs bucket ARN |
| `access_logs_bucket_arn` | Access logs bucket ARN |
| `backups_bucket_arn` | Backups bucket ARN |

## Example
```hcl
module "s3" {
  source = "../modules/s3"

  environment        = "production"
  bucket_prefix      = "agora"
  versioning_enabled = true
  encryption_enabled = true
}
```
