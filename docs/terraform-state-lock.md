# Terraform State Lock — Agora Platform

> **DynamoDB-backed state locking for safe multi-engineer Terraform collaboration.**
> **Design principle**: Serialize all state writes — no two applies can race.
> **Last Updated**: May 2026

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [DynamoDB Lock Table Design](#2-dynamodb-lock-table-design)
3. [S3 State Bucket Lifecycle](#3-s3-state-bucket-lifecycle)
4. [Stale Lock Detection](#4-stale-lock-detection)
5. [State Backup Automation](#5-state-backup-automation)
6. [Force Unlock Procedure](#6-force-unlock-procedure)
7. [Prevention & Hardening](#7-prevention--hardening)
8. [Related Documentation](#8-related-documentation)

---

## 1. Architecture Overview

```
┌──────────────┐    ┌──────────────────┐    ┌──────────────┐
│  Engineer A   │    │  CI/CD Pipeline  │    │  Engineer B   │
│  terraform    │    │  GitLab CI       │    │  terraform    │
│  apply        │    │  terraform apply │    │  apply        │
└──────┬───────┘    └────────┬─────────┘    └──────┬───────┘
       │                     │                      │
       │         ┌───────────▼───────────┐          │
       └────────►│  DynamoDB Lock Table  │◄─────────┘
                 │  (terraform-lock)     │
                 │  ConditionalWrite     │
                 │  → Mutex semantics    │
                 └───────────┬───────────┘
                             │ (lock acquired)
                             ▼
                 ┌───────────────────────┐
                 │  S3 State Bucket      │
                 │  (agora-terraform-    │
                 │   state-{env})        │
                 │  Versioning enabled   │
                 │  SSE-KMS encrypted    │
                 └───────────────────────┘
```

### How It Works

1. **Before any state operation**, Terraform attempts a `ConditionalPut` on the DynamoDB `LockID` item
2. The hash key is the S3 key path (e.g., `agora-terraform-state-production/terraform.tfstate`)
3. If the item already exists, the `ConditionalPut` fails — Terraform waits (configurable `lock-timeout`)
4. After the state write completes, Terraform releases the lock via `DeleteItem`
5. If the process crashes mid-apply, the lock remains — monitored by a CloudWatch alarm

---

## 2. DynamoDB Lock Table Design

### Table Properties

| Property | Value | Rationale |
|----------|-------|-----------|
| Table name | `terraform-lock` | Single table per AWS account |
| Billing mode | `PAY_PER_REQUEST` | Lock operations are infrequent and low-volume |
| Hash key | `LockID` (String) | S3 key path of the state file |
| PITR | Enabled | Point-in-time recovery for lock audit trail |
| Streams | `KEYS_ONLY` | Enables monitoring for stale lock detection |
| TTL attribute | `TimeToExist` | Auto-expires lock entries after configurable duration |
| SSE | Enabled | Encryption at rest |

### LockEntry Schema

| Attribute | Type | Description |
|-----------|------|-------------|
| `LockID` | String (partition key) | S3 state path, e.g., `agora-terraform-state-dev/terraform.tfstate` |
| `Operation` | String | Which operation holds the lock (`apply`, `plan`, `destroy`) |
| `Info` | String | Who/what acquired the lock and when |
| `Created` | Number | Epoch timestamp when lock was acquired |
| `Path` | String | Full S3 path |
| `Version` | String | State version serial at time of lock |
| `TimeToExist` | Number | Epoch timestamp for TTL auto-expiry (if configured) |

### Bootstrap

The lock table is created during Phase 1 bootstrap:

```bash
cd agora-infrastructure/terraform/bootstrap
terraform init && terraform apply
```

This creates both:
- S3 bucket `agora-terraform-state-{env}` for state storage
- DynamoDB table `terraform-lock` for state locking

### Source

[`terraform/bootstrap/`](https://github.com/woven-by-toyota/agora/tree/main/agora-infrastructure/terraform/bootstrap)

---

## 3. S3 State Bucket Lifecycle

| Rule | Action | Purpose |
|------|--------|---------|
| Noncurrent version expiration | Delete after 90 days | Prevent state version accumulation |
| Abort incomplete multipart upload | After 7 days | Clean up failed uploads |
| Versioning | Enabled | Rollback to any previous state version |
| SSE-KMS | Enabled | Encryption at rest with KMS CMK |
| Block Public Access | All enabled | Prevent accidental exposure |

### State File Layout

```
agora-terraform-state-production/
├── terraform.tfstate          # Current state
├── terraform.tfstate.lock.info # DynamoDB lock info (debug)
└── (versioned copies via S3 versioning)
```

Each environment gets its own state path via backend config:

```hcl
terraform {
  backend "s3" {
    bucket         = "agora-terraform-state-production"
    key            = "terraform.tfstate"
    region         = "ap-northeast-1"
    dynamodb_table = "terraform-lock"
    encrypt        = true
  }
}
```

---

## 4. Stale Lock Detection

A CloudWatch alarm monitors DynamoDB for lock contention:

| Metric | Threshold | Evaluation | Action |
|--------|-----------|------------|--------|
| `ConditionalCheckFailedRequests` (Sum) | > 50 over 3 x 5-minute periods | 3 consecutive periods | SNS → `#dr-alerts` Slack channel |

### What Triggers the Alarm

- A `terraform apply` that times out without releasing the lock
- A CI/CD pipeline crash mid-apply
- Manual `terraform apply` from a developer's laptop (blocked by IAM, but still recorded)

### Monitoring Command

```bash
aws cloudwatch describe-alarms --alarm-name-prefix terraform-stale-lock
```

### Alert Response

1. Identify the lock holder via DynamoDB:
   ```bash
   aws dynamodb get-item --table-name terraform-lock \
     --key '{"LockID": {"S": "agora-terraform-state-production/terraform.tfstate"}}'
   ```
2. Check if the process is still running (CI/CD job, terminal session)
3. Follow the [Force Unlock Procedure](#6-force-unlock-procedure)

---

## 5. State Backup Automation

A CronJob runs nightly at 02:00 JST in the `city-services` namespace:

```yaml
# agora-kubernetes-components/kustomization/base/dr/backup-cronjob.yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: terraform-state-backup
spec:
  schedule: "0 2 * * *"
```

### What It Does

1. **Copies state files** for dev, staging, and production to `agora-prod-backups/terraform-state-backups/{env}/{timestamp}.tfstate`
2. **Scans DynamoDB** for active locks and warns if any are found
3. **Emits a CloudWatch metric** `Agora/DR.BackupAgeSeconds` (reset to 0 on success)
4. **Uses IRSA** role `agora-dr-backup-role` for least-privilege S3 access

### DR ConfigMap

The DR automation is configured via a ConfigMap:

```yaml
# agora-kubernetes-components/kustomization/base/dr/dr-configmap.yaml
data:
  dr.rto.safety-critical: "30s"
  dr.rpo.safety-critical: "0"
  dr.slo.safety-critical: "99.999"
  dr.backup.state-s3-bucket: "agora-prod-backups"
  dr.backup.state-s3-prefix: "terraform-state-backups/"
  dr.backup.cron-schedule: "0 2 * * *"
  dr.test.tabletop-frequency: "quarterly"
  dr.test.chaos-staging-frequency: "monthly"
  dr.test.full-drill-frequency: "annual"
  dr.notify.slack-channel: "#dr-alerts"
```

This ConfigMap is the single source of truth for all DR SLOs, backup schedules, and testing cadences.

### Sources

- [`kustomization/base/dr/backup-cronjob.yaml`](https://github.com/woven-by-toyota/agora/blob/main/agora-kubernetes-components/kustomization/base/dr/backup-cronjob.yaml)
- [`kustomization/base/dr/dr-configmap.yaml`](https://github.com/woven-by-toyota/agora/blob/main/agora-kubernetes-components/kustomization/base/dr/dr-configmap.yaml)

---

## 6. Force Unlock Procedure

### Step 1: Identify the Lock

```bash
aws dynamodb get-item \
  --table-name terraform-lock \
  --key '{"LockID": {"S": "agora-terraform-state-production/terraform.tfstate"}}'
```

### Step 2: Verify the Process Is Dead

- Check CI/CD pipeline status (GitLab CI, Jenkins)
- Check active SSH sessions or terminal windows
- Check for running `terraform` processes on any jump box

### Step 3: Force Unlock

```bash
# Method A: terraform force-unlock (preferred)
terraform force-unlock \
  -force \
  LOCK_ID_FROM_STEP_1

# Method B: Direct DynamoDB delete (fallback — use only if terraform fails)
aws dynamodb delete-item \
  --table-name terraform-lock \
  --key '{"LockID": {"S": "agora-terraform-state-production/terraform.tfstate"}}'
```

### Step 4: Verify State Integrity

```bash
# Check the state serial hasn't changed
terraform plan

# If state is stale, restore from S3 versioning
aws s3api list-object-versions \
  --bucket agora-terraform-state-production \
  --key terraform.tfstate

# Download and push a previous version
aws s3api get-object \
  --bucket agora-terraform-state-production \
  --key terraform.tfstate \
  --version-id <VersionId> \
  terraform.tfstate.restored
terraform state push terraform.tfstate.restored
```

### ⚠️ Important

`force-unlock` does **not** fix state drift. If the apply that held the lock partially wrote to S3, the state may be inconsistent. Always run `terraform plan` after force-unlocking to verify.

---

## 7. Prevention & Hardening

### CI/CD Gates

| Gate | Implementation | Purpose |
|------|---------------|---------|
| Two-approval production applies | GitLab CI approval stage | Prevents single-person production changes |
| No local `terraform apply` for production | IAM policy denies `s3:PutObject` on state bucket from non-CI roles | Forces all production changes through CI/CD |
| Lock timeout | `-lock-timeout=600s` in deploy scripts | Prevents indefinite blocking |
| Plan before apply | Required CI step | Detects unexpected changes before writing state |

### IAM Policy for CI/CD (Deny Local Apply)

```hcl
{
  "Effect": "Deny",
  "Action": ["s3:PutObject", "dynamodb:PutItem"],
  "Resource": [
    "arn:aws:s3:::agora-terraform-state-production/*",
    "arn:aws:dynamodb:*:*:table/terraform-lock"
  ],
  "Condition": {
    "StringNotLike": {
      "aws:userid": "AROA*:gitlab-ci-*"
    }
  }
}
```

### Incident History

The Terraform state lock mechanism was hardened after a production incident where a `terraform apply` timed out mid-write, the lock was force-unlocked without verifying state integrity, and a subsequent auto-drift-remediation destroyed an EKS node group.

<small>See: `prep/stories/06-incident-terraform-state-lock.md` for the full incident narrative.</small>

---

## 8. Related Documentation

- [Architecture Overview — §11 Disaster Recovery](ARCHITECTURE.md#11-disaster-recovery-architecture) — Full DR architecture context
- [Disaster Recovery — §9.2 Terraform State Recovery](DISASTER-RECOVERY.md#92-terraform-state-recovery) — Recovery runbook
- [Deployment Guide — §4 Bootstrap](DEPLOYMENT.md#4-phase-1-terraform-iac-deployment) — Bootstrap the state backend
- [`agora-infrastructure/terraform/bootstrap/`](https://github.com/woven-by-toyota/agora/tree/main/agora-infrastructure/terraform/bootstrap) — Bootstrap Terraform config
