# Operations Guide — Agora Platform

> **Day-2 operations: monitoring, incident response, capacity management, backup verification, and routine maintenance**
> **Last Updated**: May 2026

---

## Table of Contents

1. [Operations Overview](#1-operations-overview)
2. [Monitoring & Alerting](#2-monitoring--alerting)
3. [Incident Response](#3-incident-response)
4. [On-Call Responsibilities](#4-on-call-responsibilities)
5. [Capacity Management](#5-capacity-management)
6. [Backup Verification](#6-backup-verification)
7. [Routine Maintenance](#7-routine-maintenance)
8. [Terraform State Lock Management](#8-terraform-state-lock-management)
9. [Istio Operations](#9-istio-operations)
10. [DR Operations](#10-dr-operations)
11. [Change Management](#11-change-management)
12. [Cost Monitoring](#12-cost-monitoring)
13. [Vendor / AWS Support](#13-vendor--aws-support)

---

## 1. Operations Overview

### Supported Environments

| Environment | On-call | Backup Schedule | Support Hours |
|-------------|---------|----------------|---------------|
| Dev | None | Manual | Business hours only |
| Staging | Team rotation | Automated daily | Business hours + on-call for blocking issues |
| Production | 24/7 rotation | Automated daily + WAL | 24/7 PagerDuty |

### Service-Level Indicators (SLIs)

| SLI | Target | Measurement |
|-----|--------|-------------|
| Event processing latency P99 | < 100ms | Custom histogram (Prometheus) |
| Event processing error rate | < 0.1% | Error / total requests |
| Kafka consumer lag | < 1000 | MSK CloudWatch MaxOffsetLag |
| Aurora read replica lag | < 1s | CloudWatch AuroraReplicaLag |
| API gateway availability | 99.95% | ALB 5xx / total requests |
| S3 archive freshness | < 1 hour | Kafka Connect record send rate |

### Service-Level Objectives (SLOs)

| SLO | Target | Error Budget (28-day) |
|-----|--------|----------------------|
| Traffic optimizer P99 latency ≤ 100ms | 99.9% | ~40 minutes |
| Event processing availability | 99.95% | ~20 minutes |
| API gateway uptime | 99.99% | ~4 minutes |
| Data durability (Kafka messages) | 100% | 0 (no data loss) |

---

## 2. Monitoring & Alerting

### 2.1 Where to Monitor

| Tool | What It Monitors | URL / Access |
|------|-----------------|--------------|
| CloudWatch | AWS infrastructure (EKS, MSK, Aurora, ALB, VPC) | AWS Console → CloudWatch → Dashboards |
| Amazon Managed Prometheus | Aggregated metrics (CloudWatch + K8s Prometheus) | AWS Console → AMP |
| Grafana | K8s pod-level metrics, application metrics | `kubectl port-forward svc/grafana 3000:3000 -n monitoring` |
| PagerDuty | Critical incident notifications | PagerDuty dashboard |
| Slack | All alert levels (#agora-alerts) | Slack channel |

### 2.2 Dashboards Quick Reference

| Dashboard | Load Time | Expected Baseline | When to Investigate |
|-----------|-----------|-------------------|---------------------|
| MSK Overview | < 1s | CPU < 40%, lag < 100 | CPU > 60%, lag > 500 |
| Aurora Overview | < 1s | CPU < 30%, lag < 200ms | CPU > 60%, lag > 1s |
| EKS Overview | < 2s | Pods Running > 95% | Any Pending/CrashLoop pod |
| Pipeline Overview | < 3s | Latency P99 < 50ms, error < 0.05% | Latency > 80ms, error > 0.1% |
| System Health | < 2s | All green | Any yellow/red status |

### 2.3 Alert Tiers

#### Critical (P1 — PagerDuty, 24/7)

| Alert | Condition | Response Time | Runbook |
|-------|-----------|---------------|---------|
| MSKClusterOffline | Cluster status != ACTIVE | 5 min | DR → MSK Recovery |
| AuroraWriterDown | Writer endpoint unreachable | 5 min | DR → Aurora Failover |
| ConsumerLagHigh | Lag > 1000 for 5 min | 10 min | Troubleshooting → Consumer Lag |
| TrafficOptimizerLatencyBreach | P99 > 100ms for 5 min | 10 min | Troubleshooting → Processing Latency |
| ConnectorFailed | Kafka Connect connector FAILED | 15 min | Troubleshooting → Kafka Connect |
| PodCrashLooping | Restart rate > 0.1/s | 15 min | Troubleshooting → Pod CrashLoop |
| DeadLetterQueueAccumulating | > 1000 unprocessed | 15 min | Troubleshooting → DLQ |

#### Warning (P2 — Slack, business hours)

| Alert | Condition | Response Time | Action |
|-------|-----------|---------------|--------|
| BrokerCpuHigh | CPU > 60% for 15 min | 1 hour | Plan broker scale-out |
| AuroraReplicaLagWarning | Lag > 1s for 5 min | 1 hour | Investigate write workload |
| SchemaRegistryErrors | > 10 errors/min | 2 hours | Check schema compatibility |
| HighMemoryUsage | Pod memory > 90% | 2 hours | Increase memory limits |
| CertificateExpiryWarning | SSL cert < 30 days | 1 week | Renew certificate |

#### Informational (P3 — Slack, no immediate action)

| Alert | Condition | Action |
|-------|-----------|--------|
| Daily rollup | Summary of all events | Review during standup |
| Cost anomaly | > 20% cost increase | Investigate usage |
| Backup completed | RDS snapshot taken | Verify in console |
| Deployment completed | New version deployed | Verify smoke test |

### 2.4 Monitoring on-call checklist

```markdown
## Shift Handover Checklist
- [ ] Review alerts from past 24 hours (PagerDuty + Slack)
- [ ] Check CloudWatch dashboards (MSK, Aurora, EKS)
- [ ] Check Grafana pipeline dashboard
- [ ] Review any ongoing incidents
- [ ] Verify S3 archive freshness
- [ ] Check pending deployments
- [ ] Review capacity metrics (CPU, memory, storage)
- [ ] Update handover doc with findings
```

---

## 3. Incident Response

### 3.1 Incident Severity Levels

| Severity | Definition | Response Time | Examples |
|----------|-----------|---------------|----------|
| SEV-1 | City operations affected | 5 min | Traffic system down, Kafka cluster unavailable |
| SEV-2 | Degraded performance | 15 min | High latency, elevated error rate, single broker down |
| SEV-3 | Minor issue | 1 hour | Non-critical pod crash, warning alerts |
| SEV-4 | Informational | 1 day | Certificate expiry, cost anomaly |

### 3.2 Incident Response Process

```
DETECTION (automated alert OR manual report)
    │
    ▼
ACKNOWLEDGE (PagerDuty acknowledge OR Slack response)
    │
    ▼
TRIAGE (severity assessment, impact scope)
    │
    ├── SEV-1: Immediately escalate, open bridge call
    ├── SEV-2: Investigate, notify team via Slack
    ├── SEV-3: Add to backlog, investigate within 1 hour
    └── SEV-4: Log ticket, address within 1 day
    │
    ▼
MITIGATION (apply runbook OR develop workaround)
    │
    ├── Known issue → Apply runbook
    └── Unknown issue → Investigate, document findings
    │
    ▼
RESOLUTION (service restored)
    │
    ▼
POST-INCIDENT (within 48 hours)
    ├── Blameless post-mortem
    ├── Root cause identified
    ├── Action items created
    └── Runbook updated (if applicable)
```

### 3.3 Communication

| Role | Responsibility |
|------|---------------|
| Incident Commander | Coordinates response, decides severity, communicates status |
| Scribe | Documents timeline, actions, decisions |
| Subject Matter Expert | Investigates root cause, implements fix |
| Customer Liaison | Communicates with affected teams/inventors |

**Status update template:**
```
Status: INVESTIGATING | MITIGATING | RESOLVED | MONITORING
Severity: SEV-1 | SEV-2 | SEV-3 | SEV-4
Impact: [what's affected, scope]
Action: [what we're doing]
ETA: [estimated resolution time]
```

### 3.4 Incident Runbook Index

| Runbook | Location |
|---------|----------|
| Aurora failover | `docs/DISASTER-RECOVERY.md` §4.1 |
| MSK broker failure | `docs/DISASTER-RECOVERY.md` §4.2 |
| EKS pod failure | `docs/DISASTER-RECOVERY.md` §4.3 |
| Consumer lag | `docs/TROUBLESHOOTING.md` §2.2 |
| Kafka connectivity | `docs/TROUBLESHOOTING.md` §2.1 |
| Database connections | `docs/TROUBLESHOOTING.md` §3.1 |
| Processing latency | `docs/TROUBLESHOOTING.md` §5.1 |
| Connector failure | `docs/TROUBLESHOOTING.md` §6.1 |

---

## 4. On-Call Responsibilities

### 4.1 On-Call Engineer

- **Primary responsibility**: Respond to P1/P2 alerts within SLA
- **Monitor**: PagerDuty, Slack #agora-alerts, CloudWatch dashboards
- **Actions**:
  - Acknowledge alerts within 5 minutes (P1) or 15 minutes (P2)
  - Investigate and mitigate according to runbooks
  - Escalate if unable to resolve within 30 minutes
  - Document incident timeline in incident log
- **Shift**: 7 days, 24/7 (follow-the-sun handoff if team grows)

### 4.2 Handoff Procedure

```markdown
## On-Call Handoff
### From: [Previous on-call]
### To: [New on-call]
### Date: [Date]

### Current State
- [ ] Alarms firing: [list]
- [ ] Ongoing incidents: [IDs]
- [ ] Degraded components: [list]

### Recent Changes
- [ ] Deployments: [list with dates]
- [ ] Config changes: [list]
- [ ] Known issues: [list]

### Attention Items
- [ ] Items requiring action in next shift
- [ ] Scheduled maintenance
- [ ] Capacity alerts trending

### Environment Health
- MSK brokers: [Healthy/Deployed]
- Aurora cluster: [Healthy/Failover]
- EKS nodes: [Ready count / Total]
- Backups: [Verified/Pending]
```

### 4.3 Escalation Path

```
On-Call Engineer (L1)
    │ (30 min without resolution)
    ▼
Senior Engineer / Team Lead (L2)
    │ (1 hour without resolution)
    ▼
Engineering Manager (L3)
    │ (decision: rollback, engage AWS support)
    ▼
CTO / VP Engineering (L4 — city-wide incident only)
```

---

## 5. Capacity Management

### 5.1 Capacity Review Schedule

| Review | Frequency | Attendees | Focus |
|--------|-----------|-----------|-------|
| Daily standup | Daily | Team | Alert review, short-term capacity concerns |
| Weekly review | Weekly | Team + Manager | Trends, growth rates, cost |
| Monthly planning | Monthly | Team + Manager + Finance | Budget, scaling decisions, reservations |
| Quarterly review | Quarterly | All stakeholders | Long-term strategy, RI/SP purchases |

### 5.2 Capacity Metrics to Track

| Metric | Warning | Critical | Review Frequency |
|--------|---------|----------|-----------------|
| EKS node CPU | > 60% | > 80% | Daily |
| EKS node memory | > 70% | > 85% | Daily |
| MSK broker CPU | > 50% | > 70% | Daily |
| MSK storage | > 70% | > 85% | Weekly |
| Aurora CPU | > 50% | > 70% | Daily |
| Aurora storage | > 70% | > 85% | Weekly |
| Aurora connections | > 70% of max | > 85% of max | Daily |
| Kafka consumer lag | > 500 | > 1000 | Continuous |
| S3 data lake size | > 50 TB | > 100 TB | Monthly |
| VPC IP utilisation | > 60% | > 80% | Quarterly |

### 5.3 Scaling Actions

| Metric | Warning Action | Critical Action |
|--------|---------------|----------------|
| EKS node CPU 60% | Increase max_node_count by 20% | Karpenter adds nodes automatically |
| MSK broker CPU 50% | Plan broker addition | Add Express broker via Terraform |
| Aurora CPU 50% | Add reader replica | Scale up instance class |
| Consumer lag 500 | Plan HPA adjustment | Scale processors manually |

### 5.4 Reserved Instances & Savings Plans

| Service | Recommendation | Savings |
|---------|---------------|---------|
| EKS nodes (m7g.xlarge) | 1-year Compute Savings Plan (prod) | ~30% |
| EKS nodes (m7g.xlarge) | Spot instances (dev/staging) | ~60-70% |
| Aurora (r6g.xlarge) | 1-year RDS RI (prod, writer only) | ~30% |
| MSK Express | No RI available (pay-as-you-go) | N/A |

---

## 6. Backup Verification

### 6.1 Daily Verification

```bash
#!/bin/bash
# scripts/verify-backups.sh
# Run daily via cron

ENV=${1:-production}

echo "=== Backup Verification: ${ENV} ==="

# 1. Verify RDS snapshot exists (last 24 hours)
LATEST_SNAPSHOT=$(aws rds describe-db-cluster-snapshots \
  --db-cluster-identifier agora-${ENV} \
  --query 'DBClusterSnapshots[-1].SnapshotCreateTime' \
  --output text)

SNAPSHOT_AGE=$(($(date +%s) - $(date -d "$LATEST_SNAPSHOT" +%s)))
if [ $SNAPSHOT_AGE -gt 86400 ]; then
  echo "WARNING: Latest snapshot is > 24 hours old"
else
  echo "OK: Latest snapshot from $LATEST_SNAPSHOT"
fi

# 2. Verify S3 data lake has recent data
RECENT_FILES=$(aws s3 ls s3://agora-${ENV}-data-lake/raw/ \
  --recursive --summarize 2>/dev/null | tail -1)
echo "S3 data lake: $RECENT_FILES"

# 3. Verify Kafka Connect connectors are running
CONNECTORS=$(curl -s http://kafka-connect:8083/connectors 2>/dev/null)
echo "Kafka Connect connectors: $CONNECTORS"

# 4. Verify Terraform state in S3
aws s3api head-object \
  --bucket agora-terraform-state \
  --key ${ENV}/terraform.tfstate \
  --query 'VersionId' --output text
echo "OK: Terraform state versioned"
```

### 6.2 Weekly Verification

```bash
# Restore snapshot to test cluster (weekly)
# This validates that snapshots are not corrupt

# 1. Get latest snapshot
SNAPSHOT=$(aws rds describe-db-cluster-snapshots \
  --db-cluster-identifier agora-production \
  --query 'DBClusterSnapshots[-1].DBClusterSnapshotIdentifier' \
  --output text)

# 2. Restore to test cluster
aws rds restore-db-cluster-from-snapshot \
  --db-cluster-identifier agora-backup-test \
  --snapshot-identifier $SNAPSHOT \
  --engine aurora-postgresql

# 3. Verify connection
aws rds create-db-instance \
  --db-instance-identifier agora-backup-test-instance \
  --db-cluster-identifier agora-backup-test \
  --db-instance-class db.r6g.large \
  --engine aurora-postgresql

# 4. Run data validation queries
# (e.g., row counts match expected)

# 5. Delete test cluster
aws rds delete-db-instance \
  --db-instance-identifier agora-backup-test-instance \
  --skip-final-snapshot
aws rds delete-db-cluster \
  --db-cluster-identifier agora-backup-test \
  --skip-final-snapshot
```

### 6.3 Monthly Verification

- Full DR drill (see `docs/DISASTER-RECOVERY.md` §12)
- Test S3 data recovery from Glacier
- Test Kafka replay from S3 archive
- Update RPO/RTO targets based on actual measured times

---

## 7. Routine Maintenance

### 7.1 Weekly Tasks

| Task | Who | Time | Notes |
|------|-----|------|-------|
| Review CloudWatch alarms | On-call | 15 min | Check for flapping/already-known issues |
| Check EKS node health | On-call | 10 min | `kubectl get nodes -o wide` |
| Verify all pods Running | On-call | 5 min | `kubectl get pods --all-namespaces` |
| Review MSK broker health | On-call | 10 min | CloudWatch MSK dashboard |
| Check Aurora replica lag | On-call | 5 min | CloudWatch Aurora dashboard |
| Verify S3 lifecycle execution | On-call | 10 min | Check S3 metrics for transition counts |

### 7.2 Monthly Tasks

| Task | Who | Time | Notes |
|------|-----|------|-------|
| Aurora failover test | SRE | 1 hour | Schedule during maintenance window |
| Karpenter node rotation | SRE | 30 min | `kubectl cordon` old nodes, drain, delete |
| Certificate review | SRE | 15 min | Check expiry dates in Secrets Manager |
| Capacity review | Team | 1 hour | Review trends, plan scaling |
| Terraform state audit | SRE | 15 min | Verify state matches real infra |
| Cost review | Team + Finance | 1 hour | Review AWS Cost Explorer |
| Security patching | SRE | 2 hours | Apply K8s patches, node AMI updates |

### 7.3 Quarterly Tasks

| Task | Who | Time | Notes |
|------|-----|------|-------|
| Full DR drill | SRE + Team | 4 hours | Cross-region failover simulation |
| EKS version upgrade | SRE | 4 hours | Plan: minor version upgrade (1.28 → 1.29) |
| MSK version upgrade | SRE | 2 hours | Express handles upgrades automatically |
| RDS engine upgrade | SRE | 2 hours | Apply minor version patches |
| Karpenter upgrade | SRE | 1 hour | Update provisioner configuration |
| Security audit | Security + SRE | 4 hours | IAM policy review, network audit, penetration test |
| Cost optimisation review | Team + Finance | 2 hours | RI/SP recommendations, unused resource cleanup |
| Runbook review | Team | 2 hours | Update runbooks based on incident learnings |

### 7.4 Patching Strategy

| Component | Patching Approach | Expected Downtime |
|-----------|------------------|-------------------|
| EKS nodes | Rolling update via Karpenter (replace AMI) | Zero (Karpenter drains + replaces) |
| EKS control plane | AWS-managed (minor versions) | Zero (HA control plane) |
| Stream processors | Rolling update (maxSurge=1, maxUnavailable=0) | Zero |
| Kafka Connect | Rolling update (distributed mode, tasks redistribute) | Zero |
| Schema Registry | Rolling update (read-only during transition) | < 30s |
| Aurora PostgreSQL | Apply patch during maintenance window | < 30s failover |
| Worker nodes AMI | Karpenter auto-replaces when new AMI available | Zero |

### 7.5 Maintenance Windows

| Environment | Window | Reason |
|-------------|--------|--------|
| Dev | Any time | No SLA |
| Staging | Tues/Thu 10:00-14:00 JST | Before prod changes |
| Production | Sundays 02:00-05:00 JST | Lowest city activity |

---

## 8. Terraform State Lock Management

Terraform uses DynamoDB-based state locking to prevent concurrent modifications. A lock is acquired at the start of `terraform apply` or `terraform plan` and released on completion.

### 8.1 Check Lock Status

```bash
# List all current locks across environments
aws dynamodb scan \
  --table-name terraform-lock \
  --region ap-northeast-1

# Sample output:
# {
#     "Items": [
#         {
#             "LockID": {"S": "agora-terraform-state/dev/terraform.tfstate"},
#             "Info": {"S": "{\"ID\":\"abc123\",\"Operation\":\"Plan\",\"Who\":\"pipeline-456\",\"Version\":\"1.5.0\",\"Created\":\"2026-05-24T10:30:00Z\"}"}
#         }
#     ]
# }
```

Each lock record contains:
- `LockID`: S3 key path for the state file
- `Info.Who`: CI/CD pipeline or user that acquired the lock
- `Info.Operation`: Plan or Apply
- `Info.Created`: Timestamp when lock was acquired

### 8.2 Force-Unlock Procedure

Force-unlock is a last resort. Follow the documented procedure in `docs/DISASTER-RECOVERY.md` or the detailed walkthrough:

- **Reference**: [Force-Unlock Procedure](../prep/woven-technical-prep/02-terraform-blast-radius/force-unlock-procedure.md)

Safe force-unlock checklist:

| Step | Action |
|------|--------|
| 1 | Verify lock exists via DynamoDB scan |
| 2 | Check state serial in S3 — must be unchanged |
| 3 | Confirm lock creator is offline or pipeline is dead |
| 4 | Run `terraform force-unlock -force <LOCK_ID>` |
| 5 | Validate with `terraform plan -refresh-only` |

Never force-unlock if the state serial has advanced — the apply may have partially succeeded despite the lock being held.

### 8.3 Lock Timeout Patterns

| Pattern | Configuration | Use Case |
|---------|--------------|----------|
| Short timeout | `-lock-timeout=60s` | CI/CD pipelines (retry on transient contention) |
| Default | `-lock-timeout=5m` | Interactive `terraform apply` |
| Long timeout | `-lock-timeout=10m` | Large state files with many resources |
| No lock | `-lock-timeout=0s` | Read-only operations (`terraform show`, `terraform state list`) |

All CI/CD pipelines should use `-lock-timeout=60s` to avoid hanging on stale locks. If the lock does not clear within 60 seconds, the pipeline fails fast and alerts via the DR SNS topic.

### 8.4 IAM Deny Policy

An IAM policy prevents non-admin users from force-unlocking:

```hcl
# Applied to all non-admin IAM roles and users
Deny force-unlock from non-admin roles:
  Effect: Deny
  Action: dynamodb:DeleteItem
  Resource: arn:aws:dynamodb:*:*:table/terraform-lock
  Condition: aws:PrincipalTag/Role not in ["admin", "senior-sre"]
```

This ensures only engineers with the `admin` or `senior-sre` IAM tag can delete lock items. All other users must request unlock through an admin.

---

## 9. Istio Operations

### 9.1 Check mTLS Status

Verify that STRICT mTLS is enforced on all pods:

```bash
# Check PeerAuthentication resources
kubectl get peerauthentication -A

# Verify mTLS metrics (from Prometheus or Grafana)
# istio_requests_total{connection_security_policy="mutual_tls"}

# Check if any request is using plaintext (should be zero in STRICT mode)
kubectl exec -n city-services deploy/traffic-optimizer -c istio-proxy -- \
  curl -s http://localhost:15000/stats | grep "ssl.*handshake"
```

Expected: `connection_security_policy="mutual_tls"` on all inter-pod traffic.

### 9.2 View Authorization Denials

When Istio AuthorizationPolicy blocks a request, it returns HTTP 403:

```bash
# Check Envoy access logs for 403 responses
kubectl logs -n city-services -l app.kubernetes.io/name=traffic-optimizer \
  -c istio-proxy --tail=100 | grep "403"

# Query Istio metrics for authz denials
# istio_requests_total{response_code="403", response_flags="RBAC"}

# Check the authorization policy dry-run (if enabled)
kubectl get authorizationpolicy -A
```

Common 403 causes:

| Cause | Symptom | Fix |
|-------|---------|-----|
| Missing source principal | Request from unknown SA | Add source principal to allow rule |
| Wrong namespace | Cross-namespace request not in policy | Verify namespace in from block |
| Path not listed | Request to unmapped endpoint | Add path pattern to policy |
| Expired JWT | Token validation failed | Verify JWKS URI is reachable |

### 9.3 Verify Sidecar Injection

```bash
# Check if a pod has the Istio sidecar injected
kubectl get pods -n city-services -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[*].name}{"\n"}{end}'

# Verify envoy sidecar status
kubectl exec -n city-services deploy/traffic-optimizer -c istio-proxy \
  -- curl -s http://localhost:15000/server_info | jq .

# Check injection namespace labels
kubectl get namespace city-services -o yaml | grep istio-injection
```

Expected output for sidecar-injected pods: container list includes `istio-proxy`. The namespace must have label `istio-injection: enabled`.

### 9.4 Verify Telemetry

```bash
# Check Envoy access log output
kubectl logs -n city-services deploy/traffic-optimizer -c istio-proxy \
  --tail=10 | jq '.authority, .response_code'

# Verify tracing data reaches Zipkin
# Port-forward to Zipkin UI:
kubectl port-forward -n istio-system svc/zipkin 9411:9411
# Open http://localhost:9411

# Check Istio telemetry resources
kubectl get telemetry -A
```

---

## 10. DR Operations

### 10.1 State Backup Verification

The nightly CronJob `terraform-state-backup` runs in `city-services` namespace. Verify its health:

```bash
# Check CronJob status
kubectl get cronjobs -n city-services terraform-state-backup

# View last backup job logs
kubectl logs -n city-services -l app.kubernetes.io/component=backup \
  --tail=20

# Check S3 for recent backups
aws s3 ls s3://agora-prod-backups/terraform-state-backups/production/ \
  --human-readable | tail -5

# Verify CloudWatch DR dashboard
# https://console.aws.amazon.com/cloudwatch/home?region=ap-northeast-1#dashboards:name=agora-prod-dr
```

### 10.2 DR Alert Response

| Alert | Severity | Response | Action |
|-------|----------|----------|--------|
| SafetyCriticalComponentDegraded | Critical | 30s | Emergency response per runbook |
| TerraformStaleLock | Warning | 5 min | Follow force-unlock procedure |
| StateBackupStale | Warning | 1 hour | Investigate CronJob, manually trigger backup |
| PotentialAZFailure | Critical | 1 min | Assess AZ impact, trigger failover |
| RTOBreachRisk | Critical | 1 min | Escalate to incident commander |
| KafkaBrokerCountLow | Critical | 1 min | Check MSK console, verify broker auto-recovery |
| IstioMTLSFailureRate | Warning | 15 min | Check certificate expiry, verify Istio config |

### 10.3 RTO/RPO Monitoring

| Objective | Target | Monitoring Method | Alert if |
|-----------|--------|-------------------|----------|
| Safety-critical RTO | 30s | Failover test timing | Test duration > 30s |
| City-operational RTO | 5 min | Pod recovery time | Pod not ready > 5 min |
| Cross-region RTO | 4 hours | Full drill timing | Drill duration > 4 hours |
| Safety-critical RPO | 0 | WAL streaming | Any data loss event |
| City-operational RPO | 1 min | Kafka consumer lag | Lag > processing window |
| Cross-region RPO | 5 min | S3 CRR lag | Replication lag > 5 min |

### 10.4 Test Failover Procedures

Run DR tests against the staging environment. Production tests are read-only validation.

```bash
# Aurora failover test (staging)
./prep/woven-technical-prep/03-sre-incident-cuj-dr/dr-test-failover.sh aurora-failover staging

# AZ outage simulation (staging only — drains one AZ)
./prep/woven-technical-prep/03-sre-incident-cuj-dr/dr-test-failover.sh az-outage staging

# Terraform state restore test
./prep/woven-technical-prep/03-sre-incident-cuj-dr/dr-test-failover.sh terraform-state staging

# Full DR drill (timed, staging only)
./prep/woven-technical-prep/03-sre-incident-cuj-dr/dr-test-failover.sh full-drill staging
```

For production, run read-only validation:

```bash
# Verify 3-broker health
./prep/woven-technical-prep/03-sre-incident-cuj-dr/dr-test-failover.sh kafka-broker production

# Verify AZ spread
./prep/woven-technical-prep/03-sre-incident-cuj-dr/dr-test-failover.sh az-outage production
```

### 10.5 Runbook Testing Schedule

| Test Type | Frequency | Environment | Owner |
|-----------|-----------|-------------|-------|
| Tabletop review | Quarterly | All | SRE lead |
| Chaos engineering (staging) | Monthly | Staging | SRE team |
| Aurora failover | Monthly | Staging | On-call |
| Kafka broker failure | Quarterly | Staging | SRE team |
| AZ outage simulation | Quarterly | Staging | SRE team |
| Terraform state restore | Bi-annual | Staging | Platform team |
| Full DR drill | Annual | Staging + Production (read-only) | All |

All DR test results are logged in `dr-results/` with timestamps. Review results within 48 hours and update runbooks based on findings.

---

## 11. Change Management

### 8.1 Change Types

| Type | Examples | Approval | Notice |
|------|----------|----------|--------|
| Standard | Terraform apply (non-prod), config update | None (auto) | Slack notification |
| Normal | Terraform apply (prod), new service deployment | Peer review | 24h notice |
| Emergency | Security patch, incident mitigation | Emergency approval | ASAP |
| Major | EKS upgrade, Aurora major version, DR drill | Team + Manager | 1 week notice |

### 8.2 Standard Change Process

```markdown
## Change Request Template
### Summary
- Description: [what and why]
- Type: [Standard/Normal/Emergency/Major]
- Environment: [dev/staging/prod]
- Risk: [Low/Medium/High]

### Technical Details
- Components affected: [list]
- Rollback plan: [describe]
- Verification: [smoke test / E2E test]
- Duration: [estimated time]

### Approval
- [ ] Peer reviewed: [name]
- [ ] Manager approved: [name] (for major changes)
- [ ] Change advisory board: [date] (for major changes)

### Timeline
- Start: [datetime]
- End: [datetime]
- Actual duration: [fill after change]
```

---

## 12. Cost Monitoring

### 9.1 Cost Allocation

| Tag | Value | Purpose |
|-----|-------|---------|
| `Environment` | dev/staging/production | Environment cost tracking |
| `Project` | agora | Project-level cost aggregation |
| `ManagedBy` | terraform | IaC vs manual resource tracking |
| `Service` | msk/eks/rds/s3/etc. | Per-service cost breakdown |

### 9.2 Monthly Cost Targets

| Service | Dev | Staging | Production | Total |
|---------|-----|---------|------------|-------|
| MSK | ~$10 | ~$1,500 | ~$4,500 | ~$6,010 |
| EKS | ~$150 | ~$1,200 | ~$8,000 | ~$9,350 |
| Aurora | ~$30 | ~$400 | ~$2,500 | ~$2,930 |
| S3 | ~$20 | ~$100 | ~$600 | ~$720 |
| Data transfer | ~$20 | ~$100 | ~$500 | ~$620 |
| Other | ~$20 | ~$100 | ~$100 | ~$220 |
| **Total** | **~$250** | **~$3,400** | **~$16,200** | **~$19,850** |

### 9.3 Cost Anomaly Thresholds

| Metric | Threshold | Action |
|--------|-----------|--------|
| Daily cost change | > 20% vs 7-day average | Investigate via Cost Explorer |
| Service cost spike | > 50% for any tagged service | Check for scale events |
| Data transfer | > 30% increase | Check for cross-AZ traffic, S3 replication |
| Spot instance savings | < 50% of on-demand | Check spot availability in region |

---

## 13. Vendor / AWS Support

### 10.1 AWS Support Plan

| Plan | Level | Response Time | Use Case |
|------|-------|---------------|----------|
| Developer | Basic | 12 hours | Dev environment |
| Business | Standard | 1 hour (critical) | Staging environment |
| Enterprise | Premium | 15 min (critical) | Production + TAM |

### 10.2 AWS Support Contacts

| Service | Support Channel | Notes |
|---------|----------------|-------|
| MSK | AWS Support / re:Post | Express is newer, may need escalation |
| Aurora | AWS Support / TAM | Well-documented, most issues self-service |
| EKS | AWS Support / K8s community | Use AWS EKS best practices guide |
| General | TAM (if Enterprise plan) | Monthly business reviews |

### 10.3 Useful AWS References

| Resource | URL |
|----------|-----|
| MSK Express documentation | [AWS Docs](https://docs.aws.amazon.com/msk/latest/developerguide/msk-express.html) |
| Aurora PostgreSQL best practices | [AWS Docs](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/AuroraPostgreSQL.BestPractices.html) |
| EKS best practices | [AWS Docs](https://docs.aws.amazon.com/eks/latest/best-practices/) |
| Karpenter documentation | [Karpenter Docs](https://karpenter.sh/) |
| AWS Well-Architected Framework | [AWS WA](https://aws.amazon.com/architecture/well-architected/) |
