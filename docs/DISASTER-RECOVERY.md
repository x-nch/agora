# Disaster Recovery — Agora Platform

> **Target Recovery Objectives:**
> - **RPO (Recovery Point Objective)**: 5 minutes (maximum data loss tolerated)
> - **RTO (Recovery Time Objective)**: 15 minutes (maximum downtime tolerated)
> - **Availability SLO**: 99.95% (~4.38 hours downtime/year for critical services)
> - **Last Updated**: May 2026

---

## Table of Contents

1. [DR Architecture Overview](#1-dr-architecture-overview)
2. [Failure Mode Analysis](#2-failure-mode-analysis)
3. [Data Backup Strategy](#3-data-backup-strategy)
4. [Multi-AZ Failover](#4-multi-az-failover)
5. [EKS Cluster Recovery](#5-eks-cluster-recovery)
6. [MSK Cluster Recovery](#6-msk-cluster-recovery)
7. [Aurora Database Recovery](#7-aurora-database-recovery)
8. [S3 Data Lake Recovery](#8-s3-data-lake-recovery)
9. [Secrets & Configuration Recovery](#9-secrets--configuration-recovery)
10. [DR Alerting and Monitoring](#10-dr-alerting-and-monitoring)
11. [Cross-Region DR (Future)](#11-cross-region-dr-future)
12. [DR Runbooks](#12-dr-runbooks)
13. [Regular DR Testing](#13-regular-dr-testing)
14. [Appendix: Key SLOs and DR Budget](#14-appendix-key-slos-and-dr-budget)

---

## 1. DR Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│                    aws (ap-northeast-1)                  │
│                                                          │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐              │
│  │  AZ 1a   │  │  AZ 1c   │  │  AZ 1d   │              │
│  │          │  │          │  │          │              │
│  │ MSK br1  │  │ MSK br2  │  │ MSK br3  │  ← 3-AZ HA │
│  │ Aurora W │  │ Aurora R1│  │ Aurora R2│  ← Writer+2 │
│  │ EKS ng1  │  │ EKS ng2  │  │ EKS ng3   │  ← Spread  │
│  │ NAT GW   │  │ NAT GW   │  │ NAT GW   │              │
│  └──────────┘  └──────────┘  └──────────┘              │
│                                                          │
│  ┌──────────────────────────────────────────────────┐   │
│  │               S3 (Region-redundant)               │   │
│  │  data-lake │ app-logs │ access-logs │ backups    │   │
│  └──────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────┘
         ↓ (Future: Cross-Region Replication)
┌─────────────────────────────────────────────────────────┐
│              aws (ap-southeast-1) DR Region               │
│  (Standby: read-only replicas, S3 CRR, RDS snapshot)     │
└─────────────────────────────────────────────────────────┘
```

### Single-AZ Failure Tolerance

Agora can lose any **single AZ** without impact:
| Layer | Behaviour During AZ Failure |
|-------|----------------------------|
| MSK Express | Built-in 3-way replication; remaining 2 brokers continue; recovery within 90% less time |
| Aurora | Failover to reader replica in surviving AZ (~30 seconds) |
| EKS | Karpenter launches nodes in surviving AZs; pods reschedule via PDB |
| S3 | S3 Standard is region-redundant — no impact |

### Two-AZ Failure (Catastrophic)

Losing 2 of 3 AZs triggers DR procedures:
- MSK: Brokers in 2 AZs lost → cluster unavailable → restore from S3 archive
- Aurora: Losing both replicas + writer → restore from snapshot
- EKS: etcd quorum may break → cluster recovery needed

---

## 2. Failure Mode Analysis

### Failure Mode Matrix

| Failure | Detection | Impact | RTO | RPO | Recovery Strategy |
|---------|-----------|--------|-----|-----|-------------------|
| Single MSK broker failure | CloudWatch alarm `KafkaBrokerHealth` | Performance degradation (2/3 replicas) | 0 (auto) | 0 | Express auto-recovery (~90% faster than Standard) |
| 2+ MSK brokers failure | CloudWatch alarm `MSKClusterOffline` | Cluster unavailable | 10 min | 5 min | Restore from S3 archive + Terraform re-create |
| Aurora writer failure | CloudWatch alarm `AuroraWriterDown` | Write outage | ~30s | 0 | Automatic failover to reader replica |
| All Aurora nodes failure | RDS event `ClusterDown` | Database unavailable | 30 min | 5 min | Restore from latest snapshot |
| EKS control plane failure | AWS Health Dashboard | API server unavailable (running pods unaffected) | 15 min | 0 | AWS-managed control plane auto-recovery |
| EKS node group failure | CloudWatch alarm `NodeGroupUnhealthy` | Pod evictions, capacity loss | 5 min | 0 | Karpenter launches replacement nodes |
| S3 bucket corruption | Manual detection (alerts on delete/overwrite) | Data loss (versioned — recoverable) | 15 min | 0 | Restore from version history or cross-region replica |
| VPC / NAT Gateway failure | CloudWatch alarm `NatGatewayDown` | Egress connectivity loss | 5 min | 0 | Multi-AZ NAT GW — traffic reroutes to surviving AZ |
| Region-wide failure | AWS Service Health Dashboard | Complete outage | 4 hours | 5 min | Cross-region DR (see Section 10) |

### SLO-to-Incident Mapping

| SLO Metric | Target | DR Implication |
|------------|--------|----------------|
| Event processing latency P99 | < 100ms | 15-second disruption tolerable before SLO breach |
| Event processing error rate | < 0.1% | Any data loss event requires investigation + replay |
| Data durability (Kafka messages) | 100% | Must restore from S3 archive if brokers fail |
| System availability | 99.95% | ~4.38 hours/year downtime budget across all failures |

---

## 3. Data Backup Strategy

### 3.1 Kafka Data (MSK → S3 Archival)

Kafka topics have **7-day retention** (30 for incidents). Data older than retention is NOT recoverable from MSK — it must be restored from the S3 archive.

| Archive Method | Tool | Latency | Coverage |
|---------------|------|---------|----------|
| Kafka Connect S3 sink | 4 connectors in distributed mode | Near-real-time (flush every 10K msgs or 1 hour) | All raw topics: vehicle.telemetry, sensor.environmental, signal.events, incidents |
| S3 path format | `raw/{topic}/year=YYYY/month=MM/day=dd/hour=HH/` | Partitioned by hour for efficient query/restore |
| Format | AVRO (schema included) | Self-describing, schema-compatible |

#### Verification

```bash
# Check latest S3 archive
aws s3 ls s3://agora-prod-data-lake/raw/vehicle.telemetry/year=2026/month=05/day=16/hour=14/ --recursive

# Verify connector status
curl http://kafka-connect:8083/connectors/s3-sink-vehicle-telemetry/status

# Alert if archive is stale (> 1 hour behind)
# Prometheus rule: kafka_connect_sink_record_send_rate < threshold
```

### 3.2 Aurora PostgreSQL Backups

| Backup Type | Frequency | Retention | Recovery Mechanism |
|-------------|-----------|-----------|-------------------|
| Automated snapshots | Daily (backup window) | 7d (dev), 14d (staging), 30d (prod) | Restore to new cluster |
| Transaction logs (WAL) | Continuous | Point-in-time recovery within retention | PITR to any second |
| Manual snapshots (pre-deploy) | Before major deployments | Indefinite (named snapshot) | Restore to new cluster |
| Export to S3 | Daily | Same as snapshot retention | `aws rds export-task` → S3 backups bucket |

#### Restore from Snapshot

```bash
# List available snapshots
aws rds describe-db-cluster-snapshots \
  --db-cluster-identifier agora-production \
  --query 'DBClusterSnapshots[?SnapshotCreateTime!=null].[SnapshotCreateTime,DBClusterSnapshotIdentifier]' \
  --output table

# Restore to new cluster
aws rds restore-db-cluster-from-snapshot \
  --db-cluster-identifier agora-production-restored \
  --snapshot-identifier rds:agora-production-2026-05-16-04-00 \
  --engine aurora-postgresql \
  --engine-version 15.4

# Create reader instance
aws rds create-db-instance \
  --db-instance-identifier agora-production-restored-instance-1 \
  --db-cluster-identifier agora-production-restored \
  --db-instance-class db.r6g.xlarge \
  --engine aurora-postgresql
```

### 3.3 S3 Data Lake Backups

S3 buckets are already the **destination** for Kafka archives. For S3 itself:

| Bucket | Backup Strategy | RPO |
|--------|----------------|-----|
| data-lake | S3 Versioning + CRR (future) | Versioning: any object version; CRR: ~15 min |
| app-logs | S3 Versioning | Versioning covers accidental deletion |
| access-logs | S3 Versioning | Versioning covers accidental deletion |
| backups | S3 Versioning + cross-region | Versioning + potential replication to DR region |

```bash
# Enable versioning (already configured in Terraform)
# List deleted objects (recoverable if versioning was enabled)
aws s3api list-object-versions \
  --bucket agora-prod-data-lake \
  --prefix raw/vehicle.telemetry/ \
  --query 'DeleteMarkers[?IsLatest==`true`]'

# Restore deleted object (remove delete marker)
aws s3api delete-object \
  --bucket agora-prod-data-lake \
  --key raw/vehicle.telemetry/year=2026/month=05/day=16/hour=14/topic+0+001234.avro \
  --version-id <delete-marker-version-id>
```

### 3.4 Terraform State Backups

Terraform state is stored in S3 with DynamoDB locking:

```hcl
backend "s3" {
  bucket         = "agora-terraform-state"
  key            = "terraform.tfstate"
  region         = "ap-northeast-1"
  encrypt        = true
  dynamodb_table = "terraform-lock"
}
```

- **S3 Versioning**: Enabled on the state bucket. Noncurrent versions expire after 90 days.
- **Backup CronJob**: `terraform-state-backup` runs nightly at 02:00 JST in `city-services` namespace
- **Backup destination**: `agora-prod-backups/terraform-state-backups/{env}/{timestamp}.tfstate`
- **Recovery**: `terraform state pull > terraform.tfstate` or restore from S3 backup

#### Automated Backup CronJob

```yaml
# Runs nightly in city-services namespace
schedule: "0 2 * * *"
serviceAccountName: dr-backup-sa   # IRSA role for S3 access
```

The backup script (embedded in the CronJob):
1. Copies state for all environments (dev, staging, production) to the backups bucket
2. Checks for active DynamoDB locks and warns if any are found
3. Emits a CloudWatch custom metric `BackupAgeSeconds` (set to 0 on success)

#### Recovery from Backup

```bash
# List available backups
aws s3 ls s3://agora-prod-backups/terraform-state-backups/production/

# Restore latest backup
LATEST=$(aws s3 ls s3://agora-prod-backups/terraform-state-backups/production/ \
  --sort-by last-modified | tail -1 | awk '{print $4}')
aws s3 cp "s3://agora-prod-backups/terraform-state-backups/production/${LATEST}" \
  /tmp/restored.tfstate

# Validate backup integrity
python3 -c "import json; json.load(open('/tmp/restored.tfstate')); print('Valid')"

# Push restored state
terraform state push /tmp/restored.tfstate
```

---

## 4. Multi-AZ Failover

### 4.1 Aurora Automatic Failover

```
Normal:  Writer (AZ-1a) → Reader (AZ-1c) → Reader (AZ-1d)
             │
Failure: Writer (AZ-1a) DOWN
             │
Failover: ~30 seconds
             │
Result:  Reader (AZ-1c) promotes to Writer
         New Reader launched in AZ-1a (or 1d)
```

#### What happens during failover

1. Aurora detects writer instance failure
2. DB cluster reader endpoint DNS updated to new writer (< 30 seconds)
3. Existing connections to writer are dropped (applications must retry)
4. New reader instance created to maintain replica count
5. Full cluster operational within ~60 seconds

#### Application Resilience

```yaml
# Applications must handle connection drops and retry:
# - Use the Aurora cluster reader/writer endpoints (not individual instance endpoints)
# - Implement exponential backoff on connection failure
# - Connection poolers (PgBouncer / RDS Proxy) handle failover transparently

# Recommended connection string (uses cluster endpoint, not instance)
jdbc:postgresql://agora-production.cluster-xxxxxxxxxxxx.ap-northeast-1.rds.amazonaws.com:5432/agora_production
```

### 4.2 MSK Express Broker Failover

```
Normal:  3 brokers across 3 AZs
             │
Failure: 1 broker DOWN
             │
Auto-recovery: Express auto-heals (~90% faster than Standard, typically < 2 min)
             │
Impact:  2 brokers serving reads/writes; ISR (in-sync replica) count drops to 2
             │
Recovery: New broker provisioned, data replicated from existing ISR set
```

#### Producer/Consumer Resilience

- **Producers**: Set `acks=all` to ensure all ISRs acknowledge
- **Consumers**: Consumer groups auto-rebalance when brokers return
- **No data loss**: Messages replicated to at least `min.insync.replicas=2`

### 4.3 EKS Pod Failover

```
Failure: EC2 node (AZ-1a) DOWN
             │
Signal:   Node becomes NotReady → PDB violation possible
             │
Reaction: Karpenter detects unschedulable pods → launches replacement node in surviving AZs
             │
Recovery: Pods rescheduled on new nodes (respecting podAntiAffinity)
```

PDB and anti-affinity ensure pods are distributed across AZs:

```yaml
# traffic-optimizer PDB
minAvailable: 2   # At least 2 pods must be running
                   # If 3 pods across 3 AZs, losing 1 AZ means 2 pods remain → meets PDB

# Anti-affinity in deployment
podAntiAffinity:
  preferredDuringSchedulingIgnoredDuringExecution:
    - weight: 100
      podAffinityTerm:
        labelSelector:
          matchExpressions:
            - key: app
              operator: In
              values: [traffic-optimizer]
        topologyKey: kubernetes.io/hostname  # Spread across nodes (= AZs)
```

---

## 5. EKS Cluster Recovery

### 5.1 Control Plane Recovery

EKS control plane is AWS-managed. Recovery paths:

| Issue | Recovery |
|-------|----------|
| API server unavailable | AWS auto-recovers; check `aws eks describe-cluster --name agora-production` |
| etcd corruption | AWS handles etcd backup/restore (managed) |
| Cluster unavailable > 15 min | Open AWS support ticket; prepare to rebuild from Terraform |

### 5.2 Full EKS Cluster Rebuild (Worst Case)

If the cluster must be rebuilt:

```bash
# Step 1: Terraform destroy (save state if possible)
cd terraform/environments/production
terraform destroy -target=module.eks

# Step 2: Re-create
terraform apply -target=module.eks

# Step 3: Re-apply K8s manifests
kubectl apply -k kubernetes/kustomization/overlays/production

# Step 4: Restore PersistentVolumeClaims (if any)
# PVCs backed by EBS — re-attach via volume IDs from backup

# Step 5: Verify
kubectl get nodes
kubectl get pods --all-namespaces
kubectl get svc --all-namespaces
```

### 5.3 IRSA Role Recovery

If IAM roles for service accounts are lost, Terraform re-creates them:

```bash
# Terraform re-creates IAM roles + OIDC provider
terraform apply -target=module.iam

# Verify OIDC provider
aws eks describe-cluster --name agora-production --query "cluster.identity.oidc.issuer"
```

---

## 6. MSK Cluster Recovery

### 6.1 Single Broker Failure (Auto-Recovery)

No action needed. Express auto-recovers:

```bash
# Monitor recovery
aws kafka list-nodes --cluster-arn $CLUSTER_ARN

# Check broker health
aws kafka describe-cluster --cluster-arn $CLUSTER_ARN \
  --query 'ClusterInfo.State'
```

Expected recovery time: < 2 minutes.

### 6.2 Full Cluster Failure

If the entire MSK cluster is lost:

```bash
# Step 1: Terraform re-create MSK cluster
cd terraform/environments/production
terraform apply -target=module.msk

# Step 2: Re-create topics (Terraform or script)
kafka-topics.sh --create \
  --topic vehicle.telemetry \
  --partitions 12 \
  --replication-factor 3 \
  --bootstrap-server $NEW_BOOTSTRAP

# Step 3: Re-start Kafka Connect connectors
curl -X POST http://kafka-connect:8083/connectors/s3-sink-vehicle-telemetry/start

# Step 4: Verify data flow from producers
# Devices reconnect automatically (bootstrap addresses updated via ConfigMap)

# Step 5: Verify S3 archive is still intact
aws s3 ls s3://agora-prod-data-lake/raw/vehicle.telemetry/
```

**Data loss scenario**: Messages produced between last S3 flush and cluster failure are lost (max 1 hour of data). Source devices must replay from local buffers.

### 6.3 Replaying Data from S3 Archive

If data must be replayed from S3 back into Kafka:

```bash
# Use the S3 Sink connector's reverse (S3 Source connector):
# 1. Deploy S3 Source connector reading from archive
# 2. Select time range to replay
# 3. Write back to the original topic

# Alternative: Kafka Connect S3SourceConnector
curl -X POST http://kafka-connect:8083/connectors -H "Content-Type: application/json" -d '{
  "name": "s3-source-replay",
  "config": {
    "connector.class": "io.confluent.connect.s3.S3SourceConnector",
    "s3.bucket.name": "agora-prod-data-lake",
    "s3.region": "ap-northeast-1",
    "topics.dir": "raw/vehicle.telemetry",
    "format.class": "io.confluent.connect.s3.format.avro.AvroFormat"
  }
}'
```

---

## 7. Aurora Database Recovery

### 7.1 Point-in-Time Recovery (PITR)

Recover to any second within the backup retention window:

```bash
# Identify target recovery time
# e.g., "I need the database as it was at 14:23:00 on May 16, 2026"

# Step 1: Restore cluster to specific time
aws rds restore-db-cluster-to-point-in-time \
  --source-db-cluster-identifier agora-production \
  --db-cluster-identifier agora-production-pitr \
  --restore-to-time "2026-05-16T14:23:00+09:00" \
  --engine aurora-postgresql \
  --engine-version 15.4

# Step 2: Create reader instance
aws rds create-db-instance \
  --db-instance-identifier agora-production-pitr-instance-1 \
  --db-cluster-identifier agora-production-pitr \
  --db-instance-class db.r6g.xlarge \
  --engine aurora-postgresql

# Step 3: Verify data integrity
psql -h agora-production-pitr.cluster-xxxx.ap-northeast-1.rds.amazonaws.com \
  -U agora_admin -d agora_production \
  -c "SELECT count(*) FROM device_registry;"

# Step 4: Promote to production (update Terraform, redirect traffic)
# Update Terraform db_name to point to new cluster, or update DNS
```

### 7.2 Snapshot Restore

```bash
# Step 1: List snapshots
aws rds describe-db-cluster-snapshots \
  --db-cluster-identifier agora-production \
  --query 'DBClusterSnapshots[*].[DBClusterSnapshotIdentifier,SnapshotCreateTime]' \
  --output table

# Step 2: Restore
aws rds restore-db-cluster-from-snapshot \
  --db-cluster-identifier agora-production-restored \
  --snapshot-identifier rds:agora-production-2026-05-16-04-00 \
  --engine aurora-postgresql

# Step 3: Create instance(s)
aws rds create-db-instance \
  --db-instance-identifier agora-production-restored-1 \
  --db-cluster-identifier agora-production-restored \
  --db-instance-class db.r6g.xlarge \
  --engine aurora-postgresql
```

### 7.3 Cross-Region Snapshot Copy

```bash
# Copy snapshot to DR region
aws rds copy-db-cluster-snapshot \
  --source-db-cluster-snapshot-identifier arn:aws:rds:ap-northeast-1:ACCOUNT:cluster-snapshot:rds:agora-production-2026-05-16-04-00 \
  --target-db-cluster-snapshot-identifier agora-production-dr-snapshot \
  --source-region ap-northeast-1 \
  --region ap-southeast-1
```

---

## 8. S3 Data Lake Recovery

### 8.1 Accidental Deletion

S3 Versioning is enabled on all buckets. Recovery steps:

```bash
# Step 1: Identify deleted objects
aws s3api list-object-versions \
  --bucket agora-prod-data-lake \
  --prefix raw/vehicle.telemetry/ \
  --query 'DeleteMarkers[?IsLatest==`true`]'

# Step 2: Remove delete markers
aws s3api delete-objects \
  --bucket agora-prod-data-lake \
  --delete "$(aws s3api list-object-versions \
    --bucket agora-prod-data-lake \
    --prefix raw/vehicle.telemetry/ \
    --query '{Objects: DeleteMarkers[?IsLatest==`true`].[{Key:Key,VersionId:VersionId}]}' \
    --output json)"
```

### 8.2 Bucket Corruption (Malicious or Accidental)

```bash
# Step 1: Enable S3 Object Lock (Terraform — already configured)
# This makes objects immutable (WORM) — prevents deletion/modification

# Step 2: If Object Lock is not enabled, restore from:
#   a) S3 Versioning (point-in-time restore not possible — restore individual objects)
#   b) Cross-Region Replication (if configured)
#   c) Glacier backup (if objects transitioned)

# Step 3: Audit via S3 Access Logs
# Access logs bucket shows who deleted/modified objects
aws athena start-query-execution \
  --query-string "SELECT * FROM s3_access_logs WHERE bucket='agora-prod-data-lake' AND operation='REST.DELETE.OBJECT'" \
  --work-group agora-audit
```

### 8.3 Lifecycle Policy Recovery

If lifecycle policies incorrectly transition/delete objects:

```bash
# Step 1: Disable lifecycle policy (Terraform)
# Comment out lifecycle_rule in main.tf and apply

# Step 2: Check Glacier for archived objects
aws s3api list-objects-v2 \
  --bucket agora-prod-data-lake \
  --prefix raw/vehicle.telemetry/ \
  --query 'Contents[?StorageClass==`GLACIER`]'

# Step 3: Restore from Glacier (takes 1-12 hours)
aws s3api restore-object \
  --bucket agora-prod-data-lake \
  --key raw/vehicle.telemetry/year=2026/month=05/day=16/vehicle.telemetry+0+0001234.avro \
  --restore-request '{"Days":7,"GlacierJobParameters":{"Tier":"Standard"}}'
```

---

## 9. Secrets & Configuration Recovery

### 9.1 Secrets Manager Recovery

Aurora database credentials are stored in AWS Secrets Manager with auto-rotation:

```bash
# List secrets
aws secretsmanager list-secrets --filter Key="name",Values="agora-production"

# Retrieve secret value
aws secretsmanager get-secret-value \
  --secret-id agora-production-db-credentials \
  --query SecretString

# Rotate secret manually (if compromised)
aws secretsmanager rotate-secret \
  --secret-id agora-production-db-credentials

# Restore deleted secret (30-day recovery window)
aws secretsmanager restore-secret \
  --secret-id arn:aws:secretsmanager:ap-northeast-1:ACCOUNT:secret:agora-production-db-credentials-XXXXX
```

### 9.2 Terraform State Recovery

```bash
# If state is corrupted:
# Step 1: Check S3 versioning for previous state versions
aws s3api list-object-versions \
  --bucket agora-terraform-state \
  --key terraform.tfstate

# Step 2: Download previous version
aws s3api get-object \
  --bucket agora-terraform-state \
  --key terraform.tfstate \
  --version-id <VersionId> \
  terraform.tfstate.backup

# Step 3: Push restored state
terraform state push terraform.tfstate.backup

# If DynamoDB lock is stuck:
aws dynamodb delete-item \
  --table-name terraform-lock \
  --key '{"LockID": {"S": "agora-terraform-state/terraform.tfstate"}}'
```

---

## 10. DR Alerting and Monitoring

### 10.1 DR SNS Topic

A dedicated SNS topic `agora-{env}-dr` handles all disaster recovery alerts:

| Topic | Purpose | Subscribers |
|-------|---------|-------------|
| `agora-{env}-dr` | State lock contention, backup failures, DR readiness | Slack #dr-alerts, PagerDuty DR escalation |

Alarms routed to this topic:

| Alarm | Metric | Threshold | Severity |
|-------|--------|-----------|----------|
| Terraform stale lock | DynamoDB `ConditionalCheckFailedRequests` | Sum > 50 | Warning |
| State backup age | `Agora/DR` custom metric `BackupAgeSeconds` | > 90000 (25h) | Warning |
| DR readiness | Composite: backup age + lock contention | Any alarm | Info |

### 10.2 DR CloudWatch Dashboard

The `agora-{env}-dr` CloudWatch dashboard provides a single-pane view of DR readiness:

| Widget | Metric | Purpose |
|--------|--------|---------|
| Backup Age | `Agora/DR.StateBackupAgeSeconds` (Maximum) | Shows time since last successful state backup |
| Stale Locks | `Agora/DR.StaleLocks` (Sum) | Count of active locks from DynamoDB |
| Lock Contention | `AWS/DynamoDB.ConditionalCheckFailedRequests` (Sum) | Rate of lock acquisition failures |

Access: AWS Console → CloudWatch → Dashboards → `agora-prod-dr`

### 10.3 Grafana DR Readiness Dashboard

A Grafana dashboard in the `monitoring` namespace provides application-level DR visibility:

| Panel | Query | Source |
|-------|-------|--------|
| State Backup Age | `time() - dr_backup_timestamp_seconds` | Prometheus (from backup CronJob) |
| mTLS Failure Rate | `istio_requests_total{response_code=~"401|403|503", connection_security_policy="mutual_tls"}` | Istio metrics |
| Consumer Lag by Group | `kafka_consumergroup_lag` | kafka-exporter |
| Pod Recovery Time | `time() - kube_pod_start_time` after rollouts | kube-state-metrics |
| AZ Node Count | `count by (topology_kubernetes_io_zone) (node_boot_time_seconds)` | node-exporter |

Access: `kubectl port-forward -n monitoring svc/grafana 3000:3000` → DR Readiness dashboard

### 10.4 DR Prometheus Alert Rules

Alert rules are defined in `agora-observability/kustomization/base/alert-rules/dr-rules.yaml` and evaluated by the in-cluster Prometheus.

| Alert | Expression | For | Severity | RTO Impact |
|-------|-----------|-----|----------|------------|
| `SafetyCriticalComponentDegraded` | `up{app="emergency-router"} == 0 or up{app="emergency-dispatch"} == 0` | 5s | Critical | 30s |
| `PotentialAZFailure` | `count(node_boot_time_seconds) by (zone) < 2` | 2m | Critical | 5m |
| `RTOBreachRisk` | `sum(rate(http_requests_total{status=~"5.."}[1m])) / sum(rate(http_requests_total[1m])) > 0.05` | 1m | Critical | 5m |
| `KafkaBrokerCountLow` | `count(kafka_broker_info) < 3` | 1m | Critical | 10m |
| `TerraformStaleLock` | `tf_lock_age_seconds > 900` | 1m | Warning | 15m |
| `StateBackupStale` | `time() - dr_backup_timestamp_seconds > 90000` | 5m | Warning | 1h |
| `IstioMTLSFailureRate` | `sum(rate(istio_requests_total{response_code=~"401|403|503", connection_security_policy="mutual_tls"}[5m])) / sum(rate(istio_requests_total{connection_security_policy="mutual_tls"}[5m])) > 0.01` | 5m | Warning | 15m |
| `CityOperationalSLOTracking` | error rate breaching 99.9% SLO | 5m | Warning | 5m |

All DR alerts include a `dr_tier` label for routing and a runbook annotation pointing to the appropriate recovery procedure.

---

## 11. Cross-Region DR (Future)

...existing content...

---

## 12. DR Runbooks

### Runbook 1: Database Failover Test

```bash
#!/bin/bash
# scripts/dr-test-failover.sh
# Purpose: Verify Aurora automatic failover
# Expected downtime: ~30 seconds

set -euo pipefail

ENV=${1:-production}
echo "=== DR Test: Aurora Failover ==="

# Step 1: Identify writer
WRITER=$(aws rds describe-db-clusters \
  --db-cluster-identifier agora-${ENV} \
  --query 'DBClusters[0].DBClusterMembers[?IsClusterWriter==`true`].DBInstanceIdentifier' \
  --output text)
echo "Current writer: $WRITER"

# Step 2: Reboot writer with failover (triggers failover)
TIMESTAMP=$(date +%s)
echo "Triggering failover at: $(date)"
aws rds failover-db-cluster \
  --db-cluster-identifier agora-${ENV} \
  --target-db-instance-identifier $WRITER &
FAILOVER_PID=$!

# Step 3: Wait and measure downtime
sleep 5
START=$(date +%s)
while ! pg_isready -h agora-${ENV}.cluster-xxxx.ap-northeast-1.rds.amazonaws.com -q 2>/dev/null; do
  sleep 1
done
END=$(date +%s)
DOWNTIME=$((END - START))
echo "Failover complete in ${DOWNTIME}s"

# Step 4: Verify new writer
NEW_WRITER=$(aws rds describe-db-clusters \
  --db-cluster-identifier agora-${ENV} \
  --query 'DBClusters[0].DBClusterMembers[?IsClusterWriter==`true`].DBInstanceIdentifier' \
  --output text)
echo "New writer: $NEW_WRITER"

# Step 5: Assert test results
if [ "$DOWNTIME" -gt 60 ]; then
  echo "FAIL: Failover took ${DOWNTIME}s (threshold: 60s)"
  exit 1
fi

if [ "$WRITER" = "$NEW_WRITER" ]; then
  echo "FAIL: Writer did not change (failover not triggered)"
  exit 1
fi

echo "PASS: Failover completed in ${DOWNTIME}s, writer changed to $NEW_WRITER"
```

### Runbook 2: Kafka Data Replay from S3

```bash
#!/bin/bash
# scripts/dr-kafka-replay.sh
# Purpose: Replay archived data from S3 back into MSK
# Use case: Recover lost messages after cluster failure

set -euo pipefail

TOPIC=${1:-vehicle.telemetry}
S3_PREFIX=${2:-raw/$TOPIC}
BOOTSTRAP=${3:-b-1:9098,b-2:9098,b-3:9098}

echo "=== Replaying $TOPIC from S3 ==="

# Step 1: Verify S3 archive exists
echo "Checking S3 archive..."
aws s3 ls s3://agora-prod-data-lake/$S3_PREFIX/ --recursive --summarize | tail -5

# Step 2: Deploy S3 Source connector
echo "Deploying S3 Source connector..."
curl -X POST http://kafka-connect:8083/connectors -H "Content-Type: application/json" -d '{
  "name": "s3-source-replay-'$TOPIC'",
  "config": {
    "connector.class": "io.confluent.connect.s3.S3SourceConnector",
    "s3.bucket.name": "agora-prod-data-lake",
    "s3.region": "ap-northeast-1",
    "topics.dir": "'$S3_PREFIX'",
    "format.class": "io.confluent.connect.s3.format.avro.AvroFormat",
    "tasks.max": "12"
  }
}'

# Step 3: Monitor replay progress
echo "Monitoring replay (waiting for consumer lag to drop)..."
while true; do
  LAG=$(kafka-consumer-groups.sh --bootstrap-server $BOOTSTRAP \
    --group s3-source-replay-$TOPIC \
    --describe 2>/dev/null | awk '{sum+=$5} END {print sum}')
  
  if [ -z "$LAG" ] || [ "$LAG" -eq 0 ]; then
    echo "Replay complete!"
    break
  fi
  echo "Remaining lag: $LAG messages"
  sleep 10
done

# Step 4: Clean up replay connector
curl -X DELETE http://kafka-connect:8083/connectors/s3-source-replay-$TOPIC
echo "Replay complete."
```

### Runbook 3: Full Region Recovery Drill

```bash
#!/bin/bash
# scripts/dr-full-recovery.sh
# Purpose: Full DR drill — simulate region recovery
# WARNING: Do not run in production without coordination

set -euo pipefail
echo "=== Full DR Drill: Region Recovery ==="

# Phase 1: Verify backups exist
echo "Phase 1: Verify backups..."
aws s3 ls s3://agora-prod-backups/terraform-state/ --recursive | head -5
aws rds describe-db-cluster-snapshots --db-cluster-identifier agora-production --query 'length(DBClusterSnapshots)'

# Phase 2: Restore database
echo "Phase 2: Restore database from latest snapshot..."
LATEST_SNAPSHOT=$(aws rds describe-db-cluster-snapshots \
  --db-cluster-identifier agora-production \
  --query 'DBClusterSnapshots[-1].DBClusterSnapshotIdentifier' \
  --output text)

aws rds restore-db-cluster-from-snapshot \
  --db-cluster-identifier agora-production-dr \
  --snapshot-identifier $LATEST_SNAPSHOT \
  --engine aurora-postgresql

# Phase 3: Restore infrastructure from Terraform
echo "Phase 3: Rebuild infrastructure..."
cd terraform/environments/production
terraform init -reconfigure \
  -backend-config="bucket=agora-terraform-state-dr" \
  -backend-config="key=terraform.tfstate" \
  -backend-config="region=ap-southeast-1"
terraform apply -auto-approve

# Phase 4: Deploy applications
echo "Phase 4: Deploy applications..."
kubectl apply -k kubernetes/kustomization/overlays/production

# Phase 5: Verify data flow
echo "Phase 5: Verify data flow..."
kubectl get pods --all-namespaces
kubectl get svc --all-namespaces
echo "=== DR Drill Complete ==="
```

---

## 13. Regular DR Testing

### Testing Schedule

| Test Type | Frequency | Scope | Success Criteria |
|-----------|-----------|-------|-----------------|
| Aurora failover | Monthly | Writer → reader failover | < 60s downtime, no data loss |
| EKS node drain | Quarterly | Simulate AZ failure | Pods reschedule within 5 min |
| S3 backup restore | Quarterly | Restore from Glacier | Data intact, < 4 hours |
| Kafka replay | Quarterly | Replay S3 → MSK | All messages recovered, no gaps |
| Terraform state restore | Bi-annual | Restore from S3 versioning | State consistent, plan matches infra |
| Full DR drill | Annual | Complete region rebuild | RTO < 4 hours, RPO < 5 min |

### DR Test Log

| Date | Test Type | Result | Duration | Notes |
|------|-----------|--------|----------|-------|
| 2026-05-16 | Baseline | N/A | N/A | DR plan documented |
| TBD | Aurora failover | | | |
| TBD | Kafka replay | | | |
| TBD | Full DR drill | | | |

---

## 14. Appendix: Key SLOs and DR Budget

| Metric | Target | DR Budget |
|--------|--------|-----------|
| Monthly uptime | 99.95% | ~4.38 hours/month total |
| Aurora failover time | < 30s | Within budget |
| MSK broker recovery | < 2 min | Within budget |
| EKS pod reschedule | < 5 min | Within budget |
| Cross-region RTO | < 4 hours | Separate budget (catastrophic only) |
| Cross-region RPO | < 5 min | Based on S3 CRR + Aurora Global DB lag |
