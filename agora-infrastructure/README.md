# Agora Infrastructure

**Terraform IaC for Woven City's cloud foundation — 3 AZs in `ap-northeast-1`, 60K+ events/sec.**

## Overview

Agora is the operating system of Woven City — Toyota's smart city at the base of Mount Fuji. This directory contains the infrastructure-as-code for the city's cloud foundation:

- **VPC** — 3 Availability Zones, public/private/database subnets, NAT Gateways, VPC Endpoints
- **EKS** — Kubernetes with Karpenter auto-scaler, OIDC, IRSA, cluster add-ons
- **MSK** — Express (prod/staging) or Serverless (dev), IAM Access Control, 3 brokers
- **Aurora** — PostgreSQL 15.4, Multi-AZ, read replicas, KMS encryption, Secrets Manager
- **S3** — Data lake buckets with lifecycle policies (raw/processed/archive/backup)
- **IAM** — IRSA roles per service, service-linked roles, least-privilege policies
- **KMS** — Customer-managed keys for EBS, S3, RDS, MSK
- **Monitoring** — CloudWatch dashboards, SNS alerting, AMP workspace

## Quick Start

```bash
# Prerequisites: terraform >= 1.0, aws-cli >= 2.0, kubectl >= 1.28

# 1. Bootstrap S3 + DynamoDB state backend (one-time)
cd terraform/bootstrap
terraform init && terraform apply

# 2. Deploy dev environment
cd terraform/environments/dev
terraform init && terraform plan -out=tfplan
terraform apply tfplan

# 3. Configure kubectl
aws eks update-kubeconfig --name agora-dev --region ap-northeast-1
```

## Project Structure

```
terraform/
├── main.tf              # Root module — ties all child modules together
├── variables.tf          # Root-level variables
├── outputs.tf            # Root-level outputs
├── versions.tf           # Terraform >= 1.0, AWS ~> 5.0, K8s ~> 2.20
├── terraform.tfvars.example
├── modules/
│   ├── vpc/              # Network (3 AZ, subnets, NAT, endpoints)
│   ├── eks/              # K8s cluster (Karpenter, addons, OIDC)
│   ├── msk/              # Kafka (Express/Serverless, IAM auth)
│   ├── rds/              # Aurora PostgreSQL (Multi-AZ, replicas, secrets)
│   ├── s3/               # Data lake (4 buckets, lifecycle, versioning)
│   ├── iam/              # IRSA roles, service-linked roles, policies
│   ├── kms/              # Customer-managed keys (EBS, S3, RDS, MSK)
│   └── monitoring/       # CloudWatch dashboards, SNS, AMP
├── environments/
│   ├── dev/              # Serverless MSK, Aurora Serverless v2
│   ├── staging/          # Express MSK, Aurora provisioned + 1 reader
│   └── production/       # Express MSK, Aurora Multi-AZ + 2 readers
└── bootstrap/            # S3 backend + DynamoDB locking (one-time)
```

## Environments

| Environment | MSK | Aurora | EKS Nodes | Est. Cost |
|---|---|---|---|---|
| dev | Serverless | Serverless v2 (0.5-2 ACU) | t3.large (1-5) | ~$250/mo |
| staging | Express 3x m7g.large | r5.large + 1 reader | m7g.xlarge (3-12) | ~$3,400/mo |
| production | Express 3x m7g.xlarge | r6g.xlarge + 2 readers | m7g.xlarge/2xl (5-30) | ~$16,200/mo |

## Key Decisions

| Decision | Why |
|---|---|
| MSK Express > Provisioned | 3x throughput, 20x faster scaling, 90% faster recovery |
| MSK Serverless for dev | $0 idle, pay-per-use, no cluster management |
| Aurora PostgreSQL > RDS | ~30s failover vs ~120s, auto-scaling to 128 TB |
| IAM Access Control > mTLS | No cert rotation; IRSA gives pod-level Kafka auth |
| CloudWatch + Prometheus split | Terraform manages infra monitoring; Prometheus in K8s |

## State Lock & Bootstrap

The Terraform state backend uses S3 for storage and DynamoDB for state locking, with hardened features:

### DynamoDB Lock Table Features

| Feature | Configuration | Purpose |
|---------|---------------|---------|
| **Point-in-Time Recovery (PITR)** | Enabled (`point_in_time_recovery`) | Recover lock table from any point in last 35 days |
| **Streams** | Enabled, `KEYS_ONLY` | Drive external automation on lock state changes |
| **TTL** | Enabled on `TimeToExist` attribute | Auto-expire stale lock entries |
| **Encryption** | SSE enabled (default AWS KMS) | At-rest encryption of lock items |
| **Billing** | `PAY_PER_REQUEST` | No capacity planning needed for lock traffic |

### S3 State Bucket Lifecycle

| Rule | Action | Purpose |
|------|--------|---------|
| `state-version-cleanup` | Delete noncurrent versions after 90 days | Prevent unbounded version growth |
| Incomplete multipart upload cleanup | Abort after 7 days | Clean up failed state writes |
| Versioning | Enabled | Recover from accidental state corruption |

### Stale Lock Monitoring

A CloudWatch alarm (`terraform-lock-stale-lock`) monitors `ConditionalCheckFailedRequests` on the DynamoDB lock table:

```bash
# Check stale lock alarm state
aws cloudwatch describe-alarms \
  --alarm-names "terraform-lock-stale-lock" \
  --query 'MetricAlarms[0].StateValue'

# Manually clear a stuck lock (verify first!)
aws dynamodb delete-item \
  --table-name terraform-lock \
  --key '{"LockID": {"S": "agora-terraform-state/terraform.tfstate"}}'
```

## DR Infrastructure

Dedicated DR infrastructure is provisioned alongside the standard monitoring stack:

### DR SNS Topic

A separate `*-dr` SNS topic (see [`outputs.tf`](terraform/outputs.tf) → `sns_dr_topic_arn`) routes DR-specific alerts:

```bash
# Get DR topic ARN
terraform output sns_dr_topic_arn
# Output: arn:aws:sns:ap-northeast-1:ACCOUNT:agora-production-dr
```

Subscribed alarms:
- `*-terraform-stale-lock` — Fires when DynamoDB lock contention exceeds threshold (50 failed requests over 3 evaluation periods)
- `*-state-backup-age` — Fires when `BackupAgeSeconds` > 90,000 (25 hours) indicating the CronJob may have failed

### DR CloudWatch Dashboard

A dedicated DR dashboard (`*-dr`) shows:
- **State Backup Age** — Time since last Terraform state backup (`Agora/DR` namespace)
- **Stale Locks** — Active lock count from DynamoDB
- **Lock Contention** — `ConditionalCheckFailedRequests` from DynamoDB

### S3 Backups Bucket Object Lock

The `*-backups` bucket has **Object Lock** enabled with GOVERNANCE mode (7-day default retention):

```hcl
object_lock_enabled = true

default_retention {
  mode = "GOVERNANCE"   # Can override with s3:PutObjectLegalHold
  days = 7              # Immutable for 7 days
}
```

Backups bucket lifecycle:
| Transition | Days | Storage Class |
|------------|------|---------------|
| First transition | 30 | STANDARD_IA |
| Second transition | 90 | GLACIER |
| Third transition | 365 | DEEP_ARCHIVE |
| Expiration | 2,555 (7 years) | Delete |

## Gotchas

- **MSK IAM port is 9098** (not 9092) — all bootstrap configs use `b-1:9098,b-2:9098,b-3:9098`
- **Terraform S3 backend** — must bootstrap `terraform/bootstrap/` first to create state bucket
- **MSK topic configs** in apply scripts use `&` separators (not newlines)
- **State backups bucket** has Object Lock (GOVERNANCE mode, 7 days) — you must have `s3:PutObjectLegalHold` permission to override retention

See root-level [`docs/`](/docs) for deployment guide, security, and operations documentation.
