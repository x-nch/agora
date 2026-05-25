# Operations Runbook — Agora Platform

> **Day-to-day operations, incident response procedures, escalation contacts, and post-incident review for the Woven City Agora platform.**
> **Target**: 60K events/sec, 10K devices, 3-AZ multi-tenant city OS
> **Last Updated**: May 2026

---

## Table of Contents

1. [Daily Operations Checklist](#1-daily-operations-checklist)
2. [Weekly Operations Checklist](#2-weekly-operations-checklist)
3. [Monitoring Dashboards Reference](#3-monitoring-dashboards-reference)
4. [Key Metrics & Alert Thresholds](#4-key-metrics--alert-thresholds)
5. [Incident Severity Levels](#5-incident-severity-levels)
6. [Incident Response Procedures](#6-incident-response-procedures)
7. [High Consumer Lag](#7-high-consumer-lag)
8. [Stream Processor Crash](#8-stream-processor-crash)
9. [Kafka Broker Failure](#9-kafka-broker-failure)
10. [Schema Registry Outage](#10-schema-registry-outage)
11. [S3 Data Corruption](#11-s3-data-corruption)
12. [Data Broker Failure](#12-data-broker-failure)
13. [Aurora Database Failover](#13-aurora-database-failover)
14. [EKS Node Failure](#14-eks-node-failure)
15. [Escalation Contacts](#15-escalation-contacts)
16. [Post-Incident Post-Mortem Template](#16-post-incident-post-mortem-template)
17. [Communications Template](#17-communications-template)

---

## 1. Daily Operations Checklist

```markdown
## Daily Ops Checklist — [Date]
### Performed by: [Name]
### Shift: [Morning/Afternoon/Night]

### 1. Alert Review
- [ ] Review PagerDuty incidents (past 24 hours)
- [ ] Review Slack #agora-alerts (past 24 hours)
- [ ] Confirm no unresolved critical alarms

### 2. CloudWatch Dashboard Review
- [ ] MSK Overview — broker CPU < 40%, no lag spikes
- [ ] Aurora Overview — writer CPU < 30%, replica lag < 200ms
- [ ] EKS Overview — all nodes Ready, no Pending/CrashLoop pods
- [ ] ALB Overview — 5xx rate < 0.1%, target response time < 100ms

### 3. Grafana Dashboard Review
- [ ] Pipeline Dashboard — latency P99 < 50ms, error rate < 0.05%
- [ ] Consumer Lag — all groups < 1000 (no trending)
- [ ] DLQ Depth — < 100 unprocessed messages
- [ ] Kafka Connect — all connectors RUNNING, tasks healthy

### 4. Kubernetes Health
- [ ] `kubectl get nodes -o wide` — all Ready
- [ ] `kubectl get pods --all-namespaces` — all Running/Completed
- [ ] `kubectl get hpa --all-namespaces` — all reporting metrics
- [ ] `kubectl get pdb --all-namespaces` — all healthy

### 5. Data Pipeline Verification
- [ ] S3 archive freshness — all topics have recent data (< 1 hour)
- [ ] Kafka topic offsets — not falling behind
- [ ] Schema Registry — reachable at schema-registry:8081

### 6. Capacity Check
- [ ] MSK broker CPU < 40%
- [ ] EKS node CPU < 60%, memory < 70%
- [ ] Aurora CPU < 40%, storage < 70%
- [ ] VPC IP utilisation < 60%

### 7. Backup Verification
- [ ] RDS automated snapshot exists (last 24 hours)
- [ ] S3 data lake has recent data
- [ ] Terraform state versioned

### 8. Handover Notes
- [ ] Document any ongoing issues or observations
- [ ] Note any deployments or config changes expected next shift
```

---

## 2. Weekly Operations Checklist

```markdown
## Weekly Ops Checklist — [Week of Date]

- [ ] Review CloudWatch alarm trends (flapping, stale)
- [ ] Check EKS node health — verify all nodes in correct AZs
- [ ] Verify all pods Running — check for OOMKilled or CrashLoop history
- [ ] Review MSK broker health — partition leader distribution
- [ ] Check Aurora replica lag trend
- [ ] Verify S3 lifecycle execution — transition counts for week
- [ ] Review incident post-mortems from past week
- [ ] Check certificate expiry dates
- [ ] Update runbooks based on recent incidents
- [ ] Review capacity trends — are any metrics trending toward thresholds?
```

---

## 3. Monitoring Dashboards Reference

### 3.1 CloudWatch Dashboards (AWS Console)

| Dashboard | Location | Purpose | Expected Baseline |
|-----------|----------|---------|-------------------|
| `agora-{env}-eks` | CloudWatch → Dashboards → agora-{env}-eks | Node count, pod capacity, API server latency, node CPU/memory | All nodes Ready, API latency < 50ms |
| `agora-{env}-msk` | CloudWatch → Dashboards → agora-{env}-msk | Broker CPU, BytesIn/Out, consumer lag, request rate | CPU < 40%, lag < 500 |
| `agora-{env}-aurora` | CloudWatch → Dashboards → agora-{env}-aurora | Connections, CPU, read replica lag, failover events, storage | CPU < 30%, lag < 200ms |
| `agora-{env}-alb` | CloudWatch → Dashboards → agora-{env}-alb | Request count, target response time, error rate (5xx, 4xx) | 5xx < 0.1%, response < 100ms |
| `agora-{env}-vpc` | CloudWatch → Dashboards → agora-{env}-vpc | Top talkers, rejected connections (flow logs summary) | No unexpected REJECT traffic |

### 3.2 Grafana Dashboards (In-Cluster)

| Dashboard | Access | Purpose | Expected Baseline |
|-----------|--------|---------|-------------------|
| **Agora Pipeline** | Grafana → Dashboards → Agora Pipeline | Consumer lag, processing latency, error rate, throughput, DLQ depth | Latency P99 < 50ms, error < 0.05%, DLQ < 100 |
| **System Health** | Grafana → Dashboards → System Health | Pod status, node health, cluster capacity, HPA metrics | All green, no Pending/CrashLoop |
| **Kubernetes / Compute** | Grafana → Dashboards → Kubernetes | Node CPU/memory/network, pod resource usage | Node CPU < 60%, memory < 70% |
| **Prometheus Alerts** | Grafana → Alerting | Active alert status, alert history | No pending critical alerts |

### 3.3 Dashboard Access

```bash
# Grafana (port-forward for initial access)
kubectl port-forward svc/grafana 3000:3000 -n monitoring
# Open http://localhost:3000

# CloudWatch
# AWS Console → CloudWatch → Dashboards → agora-{env}-{service}
```

---

## 4. Key Metrics & Alert Thresholds

| Metric | Description | Warning | Critical | Evaluation Window | SLO Impact |
|--------|-------------|---------|----------|-------------------|------------|
| **Consumer Lag** | Max offset lag across all consumer groups | > 500 | > 1000 | 5 minutes | Processing delay |
| **Processing Latency P99** | Per-service P99 processing time (traffic-optimizer) | > 80ms | > 100ms | 5 minutes | Primary SLO (P99 < 100ms) |
| **Processing Error Rate** | Errors / total processed messages | > 0.05% | > 0.1% | 5 minutes | Data quality |
| **DLQ Depth** | Unprocessed messages in dlq.all | > 500 | > 1000 | 5 minutes | Data loss risk |
| **Throughput per Broker** | BytesInPerSec / broker capacity | > 60% | > 80% | 5 minutes | Capacity saturation |
| **Broker CPU** | Average CPU across all brokers | > 40% | > 60% | 15 minutes | Performance degradation |
| **EKS Node CPU** | Average CPU across all nodes | > 60% | > 80% | 5 minutes | Pod scheduling |
| **EKS Node Memory** | Average memory across all nodes | > 70% | > 85% | 5 minutes | OOM risk |
| **Aurora CPU** | Writer instance CPU | > 50% | > 70% | 5 minutes | Write throughput |
| **Aurora Read Replica Lag** | Max replica lag across all readers | > 500ms | > 1s | 5 minutes | Read consistency |
| **Aurora Connections** | Active connections / max_connections | > 70% | > 85% | 5 minutes | Connection errors |
| **Schema Registry Latency** | P99 request latency | > 200ms | > 500ms | 5 minutes | Schema registration |
| **Pod Crash Rate** | Container restarts per second | > 0.05 | > 0.1 | 5 minutes | Service availability |
| **ALB 5xx Rate** | 5xx errors / total requests | > 0.5% | > 1% | 5 minutes | API availability |
| **S3 Archive Freshness** | Time since last object written to data lake | > 30 min | > 60 min | Continuous | Data durability |

### Prometheus Alert Rules (Pipeline)

From `agora-data-pipeline/monitoring/prometheus-rules-pipeline.yaml`:

| Alert | Expression | Severity |
|-------|-----------|----------|
| `ConsumerLagHigh` | `kafka_consumer_lag > 1000` for 5m | critical |
| `TrafficOptimizerLatencyBreach` | P99 latency > 100ms for 5m | critical |
| `EnergyOptimizerLatencyBreach` | P99 latency > 1s for 5m | warning |
| `DeadLetterQueueAccumulating` | dlq.all unprocessed > 1000 for 5m | critical |
| `ProcessingErrorRateHigh` | error rate > 0.1% for 5m | critical |
| `KafkaConnectTaskFailed` | any connector task in FAILED state | critical |
| `SchemaRegistryHighLatency` | P99 > 500ms for 5m | warning |
| `HighThroughputWarning` | produce throughput > 80% of capacity | warning |
| `DataBrokerHighLag` | data-broker lag > 5000 for 2m | critical |
| `AnomalyDetectorHighScoreRate` | critical anomalies > 10/min | warning |

### Prometheus Alert Rules (Kubernetes)

From `agora-kubernetes-components/monitoring/prometheus-rules.yaml`:

| Alert | Expression | Severity |
|-------|-----------|----------|
| `TrafficOptimizerLatencyHigh` | P99 > 100ms for 5m | warning |
| `EnergyManagementErrorRateHigh` | error rate > 0.1% for 5m | critical |
| `PodCrashLooping` | restart rate > 0.1/s for 5m | critical |
| `HighMemoryUsage` | memory > 90% for 5m | warning |

---

## 5. Incident Severity Levels

| Level | Definition | Response Time | Examples |
|-------|-----------|---------------|----------|
| **SEV-1** | City operations affected — critical service unavailable | 5 min (ack), 15 min (fix) | Traffic system down, Kafka cluster unavailable, Aurora writer down |
| **SEV-2** | Degraded performance — SLO breach, partial outage | 15 min (ack), 60 min (fix) | High latency, elevated error rate, single broker down, high consumer lag |
| **SEV-3** | Minor issue — no immediate user impact | 1 hour (ack), next day (fix) | Non-critical pod crash, warning alerts, schema registry high latency |
| **SEV-4** | Informational — no service impact | 1 day | Certificate expiry, cost anomaly, backup verification warning |

### Severity Quick-Reference by Symptom

| Symptom | Likely Severity | Runbook |
|---------|----------------|---------|
| No traffic signals changing | SEV-1 | [High Consumer Lag](#7-high-consumer-lag) |
| All MSK brokers unreachable | SEV-1 | [Kafka Broker Failure](#9-kafka-broker-failure) |
| Database write failures | SEV-1 | [Aurora Database Failover](#13-aurora-database-failover) |
| Processing > 100ms P99 | SEV-2 | [Stream Processor Crash](#8-stream-processor-crash) |
| DLQ accumulating > 1000 | SEV-2 | [Data Broker Failure](#12-data-broker-failure) |
| Schema registry unreachable | SEV-3 | [Schema Registry Outage](#10-schema-registry-outage) |
| S3 objects appear corrupt | SEV-2 | [S3 Data Corruption](#11-s3-data-corruption) |
| Single broker CPU > 60% | SEV-3 | [Kafka Broker Failure](#9-kafka-broker-failure) |

---

## 6. Incident Response Procedures

### 6.1 Incident Response Process

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
    ├── Known issue → Apply runbook below
    └── Unknown issue → Investigate, document findings
    │
    ▼
RESOLUTION (service restored)
    │
    ▼
POST-INCIDENT (within 48 hours)
    ├── Blameless post-mortem (use template §16)
    ├── Root cause identified
    ├── Action items created
    └── Runbook updated (if applicable)
```

### 6.2 Incident Roles

| Role | Responsibility |
|------|---------------|
| **Incident Commander** | Coordinates response, decides severity, communicates status |
| **Scribe** | Documents timeline, actions, decisions in the incident doc |
| **Subject Matter Expert** | Investigates root cause, implements fix |
| **Customer Liaison** | Communicates with affected teams/inventors |
| **Engineering Manager** | Approves emergency changes, engages AWS support if needed |

---

## 7. High Consumer Lag

**Severity**: SEV-1 (if > 1000 and growing) / SEV-2 (if stable > 500)

### Symptoms

- CloudWatch/MSK alarm: `ConsumerLagHigh` — MaxOffsetLag > 1000 for 5 minutes
- Grafana: Consumer lag graph trending up for one or more consumer groups
- Services processing slower than incoming data rate
- S3 archive falling behind real-time

### Impact

- Processing outputs delayed (traffic commands, anomaly alerts, inventor data)
- Data in Kafka retained but not processed — 7-day retention buffer applies
- If lag exceeds retention, messages are lost

### Triage

```bash
# 1. Identify affected consumer groups
kafka-consumer-groups.sh --bootstrap-server b-1:9098,b-2:9098,b-3:9098 \
  --all-groups --describe

# 2. Check if consumers are assigned to partitions
# (if consumers < partitions, some partitions have no consumer)
kafka-consumer-groups.sh --bootstrap-server b-1:9098,b-2:9098,b-3:9098 \
  --group <group-name> --describe

# 3. Check HPA status
kubectl describe hpa <service>-hpa -n city-services
```

### Procedure

#### Step 1: Auto-Scaling Check (0–2 minutes)

```bash
# Verify HPA is working
kubectl get hpa <service>-hpa -n city-services
kubectl describe hpa <service>-hpa -n city-services
```

- If HPA reports metrics but hasn't scaled: check `kubectl get pods` for pending pods (resource constraints)
- If HPA shows `<unknown>` for metrics: check Prometheus/ServiceMonitor is scraping
- If HPA is scaling: wait 2-3 minutes for pods to join consumer group

#### Step 2: Manual Scale-Up (2–5 minutes)

If HPA is not acting fast enough:

```bash
# Scale up manually — match or exceed partition count
kubectl scale deployment <service> -n city-services --replicas=<max>
# For traffic-optimizer: max 10 (partition limit: 12)
# For data-broker: max 20 (partition limit: 12)
```

For `vehicle.telemetry` (12 partitions), scaling beyond 12 consumers is ineffective — extra consumers are idle.

#### Step 3: Investigate Root Cause (5–15 minutes)

```bash
# Check pod resource usage
kubectl top pod -n city-services -l app=<service>

# Check for CPU throttling
kubectl exec <pod> -n city-services -- cat /sys/fs/cgroup/cpu/cpu.stat

# Check processor logs for errors
kubectl logs -n city-services -l app=<service> --tail=200 | grep -i "error\|exception"

# Check if lag is across all partitions or just one (skew)
kafka-consumer-groups.sh --bootstrap-server b-1:9098,b-2:9098,b-3:9098 \
  --group <group-name> --describe
# If single partition has high lag: check partition key distribution
```

#### Step 4: Offset Reset (Last Resort — Data Loss Risk)

If the service has been down for a long time and catching up from the earliest offset would take too long:

```bash
# CAUTION: This skips all unprocessed messages
# Use only if data integrity is not critical for the backlog period

# Reset to latest (skip backlog)
kafka-consumer-groups.sh --bootstrap-server b-1:9098,b-2:9098,b-3:9098 \
  --group <group-name> \
  --topic <topic> \
  --reset-offsets --to-latest --execute

# Or reset to a specific timestamp
kafka-consumer-groups.sh --bootstrap-server b-1:9098,b-2:9098,b-3:9098 \
  --group <group-name> \
  --topic <topic> \
  --reset-offsets --to-datetime 2026-05-16T14:00:00.000 --execute
```

#### Step 5: Post-Mitigation

- Verify lag dropping: `kafka-consumer-groups.sh --describe --group <group>`
- Leave HPA scaled-up until lag is below 100
- Document the incident including root cause
- If partition expansion is needed, follow [Partition Expansion] guide

### Prevention

- Monitor lag trends in Grafana — proactive scaling before thresholds
- Ensure HPA has lag-based metric in addition to CPU/memory
- Review partition count vs max consumers — expand partitions if needed

---

## 8. Stream Processor Crash

**Severity**: SEV-1 (traffic-optimizer) / SEV-2 (others)

### Symptoms

- Prometheus alert: `PodCrashLooping` — restart rate > 0.1/s for 5 minutes
- Grafana: pods showing CrashLoopBackOff or ImagePullBackOff
- Consumer lag starts growing as no consumers are processing

### Impact

- Traffic optimizer crash: traffic signals not updated, potential city disruption
- Data broker crash: inventor data flow stops, raw data accumulates in MSK
- Anomaly detector crash: incidents not detected, alerts delayed

### Procedure

#### Step 1: K8s Auto-Restart (0–30 seconds)

Kubernetes automatically restarts the pod via the ReplicaSet/Deployment controller. If the pod exits cleanly:

```bash
# Check if pod is restarting
kubectl get pods -n city-services -l app=<service> -w

# Wait for new pod to reach Running state
# If it crash-loops, proceed to Step 2
```

#### Step 2: Diagnose Crash (1–5 minutes)

```bash
# Check current pod logs
kubectl logs <crash-pod> -n city-services --tail=100

# Check previous pod logs (before crash)
kubectl logs <crash-pod> -n city-services --previous --tail=100

# Check pod events
kubectl describe pod <crash-pod> -n city-services | grep -A20 Events
```

#### Step 3: Consumer Group Rebalance (1–2 minutes)

When a stream processor pod crashes:
- The consumer group detects the lost consumer
- A rebalance is triggered (may cause brief processing pause for other members)
- Remaining consumers re-assign partitions from the lost consumer
- If the pod restarts, it rejoins the group (another rebalance)

```bash
# Monitor rebalance
kafka-consumer-groups.sh --bootstrap-server b-1:9098,b-2:9098,b-3:9098 \
  --group <group-name> --describe
# Look for: state = STABLE (normal) vs REBALANCING
```

#### Step 4: Data Integrity Check (5–10 minutes)

Verify no data loss during the crash:

```bash
# Check DLQ for messages from the crashed processor
kubectl logs -n city-services -l app=dlq-processor --tail=50

# Check if offsets were committed before crash
# (manual commits are safer — verify enable.auto.commit=false)

# Check S3 archive received data during the crash window
aws s3 ls s3://agora-prod-data-lake/raw/ --recursive --summarize | tail -3
```

#### Step 5: Common Fixes by Crash Type

| Error | Likely Cause | Fix |
|-------|-------------|-----|
| `OOMKilled` | Memory limit too low | Increase memory limit in deployment, restart |
| `NullPointerException` | Unexpected null in processing | Add null checks, fix data, restart |
| `SerializationException` | Schema mismatch | Check AVRO schema compatibility |
| `ImagePullBackOff` | Image tag missing or ECR auth issue | Fix image tag, check ECR auth |
| `CreateContainerConfigError` | Missing ConfigMap/Secret | Verify K8s resources exist |
| `Readiness probe failed` | Service not starting in time | Increase failureThreshold or fix startup |

### Prevention

- Set `enable.auto.commit=false` — use manual offset commits
- Configure `max.poll.interval.ms` to match processing time
- Use podDisruptionBudget to ensure minimum replicas during voluntary disruptions
- Implement graceful shutdown (SIGTERM handler commits offsets)

---

## 9. Kafka Broker Failure

**Severity**: SEV-1 (multiple brokers) / SEV-3 (single broker)

### Architecture Note

MSK Express runs 3 brokers across 3 Availability Zones. Losing 1 broker is tolerated. Losing 2+ brokers causes cluster unavailability.

### Symptoms

- CloudWatch alarm: `KafkaBrokerHealth` (single) or `MSKClusterOffline` (multiple)
- Producer errors: `LeaderNotAvailable`, `NotEnoughReplicas`
- Consumer errors: connection refused to affected broker

### Procedure

#### Single Broker Failure (Auto-Recovery)

MSK Express auto-recovers within 2 minutes (90% faster than Standard).

```bash
# 1. Confirm it's a single broker
aws kafka list-nodes --cluster-arn $CLUSTER_ARN

# 2. Monitor auto-recovery
aws kafka describe-cluster --cluster-arn $CLUSTER_ARN \
  --query 'ClusterInfo.State'

# 3. Verify producers/consumers reconnect automatically
# Producers with acks=all will block until ISR restored
# Consumers will auto-discover new broker via metadata

# 4. Check MSK CloudWatch dashboard
# Verify BytesInPerSec and BytesOutPerSec returning to normal
```

**Expected recovery time**: < 2 minutes. No manual intervention needed.

#### Multiple Broker Failure (Cluster Unavailable)

If 2+ brokers fail and the cluster becomes unavailable:

```bash
# 1. Confirm cluster state
aws kafka describe-cluster --cluster-arn $CLUSTER_ARN \
  --query 'ClusterInfo.State'

# 2. If State != ACTIVE, trigger Terraform re-create
cd terraform/environments/production
terraform apply -target=module.msk

# 3. Re-create topics (Terraform handles this if defined)
kafka-topics.sh --create --topic vehicle.telemetry \
  --partitions 12 --replication-factor 3 \
  --bootstrap-server $NEW_BOOTSTRAP \
  --command-config admin-client.properties

# 4. Re-start Kafka Connect connectors
curl -X POST http://kafka-connect:8083/connectors/s3-sink-vehicle-telemetry/restart

# 5. Verify data flow from producers
# Devices reconnect automatically (bootstrap addresses in ConfigMap)

# 6. Verify S3 archive is intact
aws s3 ls s3://agora-prod-data-lake/raw/vehicle.telemetry/ --recursive | tail -5
```

**Data loss**: Messages produced between last S3 flush and cluster failure are lost (max 1 hour). Devices with local buffers can replay.

### Post-Recovery

```bash
# Verify all topics have correct partition count and ISR
kafka-topics.sh --describe --topic vehicle.telemetry \
  --bootstrap-server b-1:9098,b-2:9098,b-3:9098

# Verify preferred leader election (rebalance leaders)
kafka-leader-election.sh --bootstrap-server b-1:9098,b-2:9098,b-3:9098 \
  --election-type PREFERRED --all-topic-partitions
```

---

## 10. Schema Registry Outage

**Severity**: SEV-3

### Symptoms

- Prometheus alert: `SchemaRegistryHighLatency` (P99 > 500ms)
- Producer error: `RetryableConnectException: Connection refused`
- Consumer error: `Schema not found`
- Dashboards: schema-registry pod CrashLoop or Pending

### Impact

- **Producers**: Can still produce using cached schema IDs (read-only mode)
- **New schema registration**: Blocked entirely
- **New consumers/services**: Cannot register — may fail to start
- **Existing consumers**: Continue with cached schemas

### Procedure

#### Step 1: Verify Outage

```bash
# Check pod status
kubectl get pod -n city-services -l app=schema-registry

# Check schema registry endpoint
curl -s -o /dev/null -w "%{http_code}" http://schema-registry:8081
# Should return 200. If connection refused, proceed.

# Check Schema Registry logs
kubectl logs -n city-services -l app=schema-registry --tail=100
```

#### Step 2: Enable Read-Only Fallback Mode

Stream processors and Kafka Connect use local schema caches. During an outage:

- **Existing operations**: Continue normally with cached schemas
- **New schema registration**: Blocked — developers must wait until Schema Registry is restored
- **Schema evolution**: Blocked — no new schema versions can be registered

No manual action needed for read-only mode — it's built into the Kafka clients.

#### Step 3: Restore Schema Registry

```bash
# Restart the pod
kubectl rollout restart deployment/schema-registry -n city-services

# If the restart doesn't fix it, check backend storage
kubectl exec -n city-services -l app=schema-registry -- \
  curl http://localhost:8081/subjects

# Check for backend Kafka topic _schemas
kafka-topics.sh --describe --topic _schemas \
  --bootstrap-server b-1:9098,b-2:9098,b-3:9098
```

#### Step 4: Verify Restoration

```bash
# Wait for pod to be ready
kubectl wait --for=condition=ready pod -l app=schema-registry -n city-services --timeout=60s

# Verify endpoint
curl -s http://schema-registry:8081/subjects | jq .

# Verify known schemas are accessible
curl -s http://schema-registry:8081/subjects/vehicle.telemetry-value/versions/latest
```

### Prevention

- Deploy Schema Registry with multiple replicas (min 2)
- Configure client-side schema caching (in-memory cache with TTL)
- Use `schema.registry.url` failover list if multiple instances

---

## 11. S3 Data Corruption

**Severity**: SEV-2

### Symptoms

- Athena/Spark queries fail on archived data
- Deserialization errors in analytics pipelines
- Missing or truncated objects in data lake
- S3 Access Logs show unexpected DELETE or overwrite operations

### Impact

- Analytics and reporting produce incorrect results
- Data replay from S3 would propagate corrupt data
- Long-term data retention compromised

### Procedure

#### Step 1: Assess Scope

```bash
# 1. Identify corrupt objects
# Check Athena error logs for failing partitions
aws s3 ls s3://agora-prod-data-lake/raw/vehicle.telemetry/ --recursive | tail -20

# 2. Verify object integrity
aws s3api head-object \
  --bucket agora-prod-data-lake \
  --key raw/vehicle.telemetry/year=2026/month=05/day=16/hour=14/topic+0+000001.avro

# 3. Check object version (if versioning enabled)
aws s3api list-object-versions \
  --bucket agora-prod-data-lake \
  --prefix raw/vehicle.telemetry/year=2026/month=05/
```

#### Step 2: Determine Recovery Strategy

**Option A: Replay from MSK (if within retention window)**

| Topic | Retention Window |
|-------|-----------------|
| vehicle.telemetry | 7 days |
| sensor.environmental | 7 days |
| signal.events | 7 days |
| incidents | 30 days |

```bash
# Deploy a temporary S3 Source connector to re-ingest
# This replays from S3 to a new topic
curl -X POST http://kafka-connect:8083/connectors -H "Content-Type: application/json" -d '{
  "name": "s3-source-replay-vehicle-telemetry",
  "config": {
    "connector.class": "io.confluent.connect.s3.S3SourceConnector",
    "s3.bucket.name": "agora-prod-data-lake",
    "s3.region": "ap-northeast-1",
    "topics.dir": "raw/vehicle.telemetry",
    "format.class": "io.confluent.connect.s3.format.avro.AvroFormat"
  }
}'
```

**Option B: Restore from Glacier**

If objects have transitioned to Glacier:

```bash
# Check storage class
aws s3api list-objects-v2 \
  --bucket agora-prod-data-lake \
  --prefix raw/vehicle.telemetry/ \
  --query 'Contents[?StorageClass==`GLACIER`]'

# Restore (takes 1-12 hours for Standard tier)
aws s3api restore-object \
  --bucket agora-prod-data-lake \
  --key raw/vehicle.telemetry/year=2026/month=05/day=16/topic+0+0001234.avro \
  --restore-request '{"Days":7,"GlacierJobParameters":{"Tier":"Standard"}}'
```

**Option C: Restore from S3 Versioning**

```bash
# Remove delete markers
aws s3api delete-objects \
  --bucket agora-prod-data-lake \
  --delete "$(aws s3api list-object-versions \
    --bucket agora-prod-data-lake \
    --prefix raw/vehicle.telemetry/ \
    --query '{Objects: DeleteMarkers[?IsLatest==`true`].[{Key:Key,VersionId:VersionId}]}' \
    --output json)"
```

#### Step 3: Verify Data Integrity

```bash
# For AVRO files, verify with avro-tools
java -jar avro-tools-1.11.1.jar tojson test.avro | head

# Verify schema matches expected
java -jar avro-tools-1.11.1.jar getschema test.avro

# Run a test query on Athena to validate
```

#### Step 4: Post-Recovery

- If corruption was due to lifecycle policy misconfiguration, update Terraform
- If corruption was due to S3 sink connector bug, fix connector configuration
- Document root cause and update monitoring

### Prevention

- S3 Versioning enabled on all buckets (Terraform-managed)
- S3 Object Lock (WORM) on backups bucket
- Bucket policies prevent accidental public access or deletion
- Kafka Connect flush configuration balanced (10K msgs or 1 hour max)

---

## 12. Data Broker Failure

**Severity**: SEV-1 (data broker down) / SEV-2 (functionally degraded)

### Architecture Context

The Data Broker is the multi-tenant gateway that:
1. Reads from raw topics (vehicle.telemetry, sensor.environmental, signal.events)
2. Strips PII and anonymizes data
3. Writes to output topics (data.anonymized.vehicle, data.inventor.traffic)
4. Enforces per-inventor access control rules

### Symptoms

- Prometheus alert: `DataBrokerHighLag` — lag > 5000 for 2 minutes
- Inventor data feeds stop receiving updates
- S3 processed/ directory stops growing
- Error rate spikes on data-broker service

### Impact

- **Internal city services**: Unaffected — they read from raw topics directly
- **Inventors**: Complete outage — no anonymized data available
- **Data lake processed/**: Stale — affects inventor S3 access
- **Raw data in MSK**: Continues to accumulate with 7-day retention buffer — **no data loss**

### Procedure

#### Step 1: Verify Data Broker Status

```bash
# Check pods
kubectl get pods -n city-services -l app=data-broker

# Check logs
kubectl logs -n city-services -l app=data-broker --tail=100

# Check HPA
kubectl describe hpa data-broker-hpa -n city-services
```

#### Step 2: Confirm Raw Data is Safe

```bash
# Verify raw topics are still receiving data
kafka-consumer-groups.sh --bootstrap-server b-1:9098,b-2:9098,b-3:9098 \
  --group data-broker-group --describe

# Check MSK throughput — should be normal
aws cloudwatch get-metric-statistics \
  --namespace AWS/Kafka \
  --metric-name BytesInPerSec \
  --dimensions Name=Cluster Name,Value=agora-production \
  --start-time $(date -u -d '-10 minutes' +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 300 --statistics Sum
```

**Key point**: Raw data is retained in MSK for 7 days. As long as the broker cluster is healthy, no data is lost.

#### Step 3: Restart Data Broker

```bash
# Restart deployment
kubectl rollout restart deployment/data-broker -n city-services

# Monitor restart
kubectl rollout status deployment/data-broker -n city-services

# Verify it re-joins consumer group
kafka-consumer-groups.sh --bootstrap-server b-1:9098,b-2:9098,b-3:9098 \
  --group data-broker-group --describe
```

#### Step 4: Monitor Lag Drain

```bash
# Watch consumer lag drop
watch -n 5 "kafka-consumer-groups.sh --bootstrap-server b-1:9098,b-2:9098,b-3:9098 \
  --group data-broker-group --describe | awk '{sum+=\$5} END {print \"Total lag: \" sum}'"
```

#### Step 5: Verify Anonymized Output

```bash
# Check output topics are receiving data
kfractl consume data.anonymized.vehicle \
  --bootstrap-server b-1:9098,b-2:9098,b-3:9098 \
  --max-messages 10

# Verify no PII in output
kfractl consume data.anonymized.vehicle \
  --bootstrap-server b-1:9098,b-2:9098,b-3:9098 \
  --max-messages 5 -o json | grep -i "vehicle_id\|driver_id\|gps_exact"
# Should return no matches
```

### Prevention

- Data broker deploys with 5 minimum replicas (max 20)
- HPA scales on CPU, memory, AND consumer lag
- PDB ensures minimum 3 pods during voluntary disruptions
- Raw data retention in MSK (7 days) provides a buffer for recovery
- Anonymization rules are configuration-driven, not hardcoded

---

## 13. Aurora Database Failover

**Severity**: SEV-1

### Architecture

Aurora PostgreSQL with 1 writer + 2 reader replicas across 3 AZs. Automatic failover < 30 seconds.

### Symptoms

- CloudWatch alarm: `AuroraWriterDown`
- Application logs: connection refused to writer endpoint
- CloudWatch: DB connections drop to 0 briefly
- Prometheus: `pg_stat_activity` drops

### Procedure

#### Step 1: Confirm Failover

```bash
# Check cluster status
aws rds describe-db-clusters \
  --db-cluster-identifier agora-production \
  --query 'DBClusters[0].[Status,DBClusterMembers]'

# Identify new writer
aws rds describe-db-clusters \
  --db-cluster-identifier agora-production \
  --query 'DBClusters[0].DBClusterMembers[?IsClusterWriter==`true`].DBInstanceIdentifier'
```

#### Step 2: Wait for DNS Propagation

```bash
# Writer endpoint DNS update — typically < 30 seconds
# Applications with exponential backoff will reconnect automatically

# Verify writer endpoint resolves
nslookup agora-production.cluster-xxxx.ap-northeast-1.rds.amazonaws.com
```

#### Step 3: Verify Application Reconnection

```bash
# Check application logs for reconnection
kubectl logs -n city-services -l app=traffic-optimizer --tail=50 | grep -i "db\|postgres\|connection"

# Check connection count on new writer
SELECT count(*) FROM pg_stat_activity;
```

#### Step 4: Manual Failover (for testing or to force new writer)

```bash
aws rds failover-db-cluster \
  --db-cluster-identifier agora-production \
  --target-db-instance-identifier agora-production-reader-1
```

### Prevention

- Use Aurora cluster endpoint (not individual instance endpoints)
- Implement exponential backoff with jitter in connection code
- Connection pooler (PgBouncer/RDS Proxy) handles failover transparently
- Monitor replica lag — lag > 1s indicates potential failover delay

---

## 14. EKS Node Failure

**Severity**: SEV-2

### Symptoms

- CloudWatch alarm: `NodeGroupUnhealthy`
- `kubectl get nodes` shows NotReady status
- Pods stuck in Pending state
- Karpenter logs show provisioning activity

### Procedure

#### Step 1: Verify Node Status

```bash
kubectl get nodes -o wide
kubectl describe node <failed-node>
```

#### Step 2: Let Karpenter Handle It (0–2 minutes)

Karpenter automatically:
- Detects unschedulable pods
- Launches replacement nodes
- Cordon and drains the failed node

```bash
# Check Karpenter activity
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter --tail=50
```

#### Step 3: If Karpenter Isn't Working

```bash
# Check Karpenter provisioner
kubectl get provisioners
kubectl describe provisioner agora-provisioner

# Check EC2 limits
aws ec2 describe-account-attributes | grep -A5 "max-instances"

# Manual node drain (if node is partially responsive)
kubectl drain <node> --ignore-daemonsets --delete-emptydir-data

# Delete the node (Karpenter will recreate)
kubectl delete node <node>
```

#### Step 4: Verify Pod Rescheduling

```bash
kubectl get pods --all-namespaces -o wide | grep -v "Running\|Completed"
# Should show only daemonset pods or none
```

---

## 15. Escalation Contacts

### 15.1 On-Call Rotations

| Role | Primary Contact | Secondary Contact | Escalation Path |
|------|----------------|-------------------|-----------------|
| **L1: On-Call Engineer** | PagerDuty rotation | Slack #agora-oncall | — |
| **L2: Senior Engineer** | Slack @sre-lead | Phone | L1 → L2 (30 min) |
| **L3: Engineering Manager** | Slack @eng-mgr | Phone | L2 → L3 (1 hour) |
| **L4: CTO / VP Eng** | Slack @cto | Phone | L3 → L4 (city-wide) |

### 15.2 Security Contacts

| Role | Contact | Availability |
|------|---------|-------------|
| Security Team | security@agora.woven-city.jp | Business hours |
| Security On-Call | PagerDuty: SEC-ROTATION | 24/7 |
| CISO | ciso@woven-by-toyota.com | Business hours |
| Data Protection Officer | dpo@woven-by-toyota.com | Business hours |

### 15.3 AWS Support

| Plan | Response Time | Channel |
|------|---------------|---------|
| Enterprise Support | 15 min (critical) | AWS Support Center / TAM |
| TAM (Technical Account Manager) | Business hours | Email / Monthly review |

### 15.4 Communication Channels

| Channel | Purpose | Severity |
|---------|---------|----------|
| **PagerDuty** | Critical incident alerts (phone push + SMS) | SEV-1, SEV-2 |
| **Slack #agora-alerts** | All alerts (critical + warning + info) | All |
| **Slack #agora-incidents** | Incident coordination and status updates | SEV-1, SEV-2 |
| **Slack #agora-deployments** | Deployment notifications | N/A |
| **Email** | Scheduled reports, non-urgent | SEV-4 |

### 15.5 Escalation Procedure

```
SEV-1 Incident Detected
    │
    ▼
On-Call Engineer (L1) acknowledges within 5 minutes
    │
    ├── Resolved → Document, close incident
    │
    └── Not resolved within 30 minutes
            │
            ▼
        Escalate to Senior Engineer (L2)
            │
            ├── Open bridge call (Zoom / Google Meet)
            │
            └── Not resolved within 60 minutes
                    │
                    ▼
                Escalate to Engineering Manager (L3)
                    │
                    ├── Decision: rollback, engage AWS support
                    │
                    └── City-wide impact → CTO / VP Eng (L4)
```

---

## 16. Post-Incident Post-Mortem Template

```markdown
# Post-Mortem: [Incident Title]

**Date**: YYYY-MM-DD
**Incident ID**: INC-XXXX
**Severity**: SEV-[1-4]
**Duration**: [X] minutes ([start] JST → [end] JST)
**Detection**: [Automated alert / Manual report / Customer report]
**Report Author**: [Name]

---

## Summary

[2-3 sentence executive summary of what happened, impact, and resolution]

## Timeline

| Time (JST) | Event |
|------------|-------|
| HH:MM | [First symptom detected] |
| HH:MM | [Alert fired / Incident acknowledged] |
| HH:MM | [Triage completed, severity assigned] |
| HH:MM | [Mitigation action taken] |
| HH:MM | [Service restored] |
| HH:MM | [Monitoring confirmed stable] |

## Impact

- **Affected services**: [list]
- **User impact**: [what end-users/inventors experienced]
- **Data loss**: [Yes/No — if yes, quantify]
- **SLO breach**: [Yes/No — which SLO, by how much]

## Root Cause

### Primary Cause
[Detailed explanation of what went wrong]

### Contributing Factors
- [Factor 1]
- [Factor 2]

## Detection & Response

### What Went Well
- [Good detection, good communication, good tooling, etc.]
- [ ]

### What Could Be Improved
- [Slow detection, unclear runbook, etc.]
- [ ]

## Action Items

| # | Action | Owner | Type | Severity | Status |
|---|--------|-------|------|----------|--------|
| 1 | [Specific, measurable action] | @person | process/tech | P0/P1/P2 | Open/In Progress/Done |
| 2 | [ ] | @person | | | |
| 3 | [ ] | @person | | | |

## Metrics (Optional)

- **Time to detect**: X min
- **Time to acknowledge**: X min
- **Time to mitigate**: X min
- **Time to resolve**: X min
- **Error budget consumed**: X min (of Y budget = Z%)

## Lessons Learned

1. [Key takeaway 1]
2. [Key takeaway 2]

## Appendix

- [Links to relevant dashboards, logs, commits]
- [Link to related PRs or docs changes]

---

*Blameless post-mortem — focus on systemic improvements, not individual blame.*
```

---

## 17. Communications Template

### Status Update Template

```
Status: INVESTIGATING | MITIGATING | RESOLVED | MONITORING
Severity: SEV-[1-4]
Incident ID: INC-XXXX
Affected Services: [list]
Impact: [what's affected, scope]
Action: [what we're doing]
ETA: [estimated resolution time]
Next Update: [time]
```

### Incident Slack Post Template

```
:rotating_light: *INCIDENT DECLARED* :rotating_light:

*Severity*: SEV-[1-4]
*Service*: [service name]
*Summary*: [brief description]
*Impact*: [affected users/inventors]

*Runbook*: [link to runbook section]
*Commander*: @person
*Scribe*: @person
*SME*: @person

*Timeline*:
- HH:MM — Detected/Reported
- HH:MM — Acknowledged
- HH:MM — Mitigation started

*Slack Channel*: #agora-incidents
*Bridge*: [Zoom/Google Meet link]
```

---

## Appendix: Runbook Index

| Runbook | Section | Response Time | Severity |
|---------|---------|---------------|----------|
| High Consumer Lag | [§7](#7-high-consumer-lag) | 10 min | SEV-1/2 |
| Stream Processor Crash | [§8](#8-stream-processor-crash) | 15 min | SEV-1/2 |
| Kafka Broker Failure | [§9](#9-kafka-broker-failure) | 5 min (multi) | SEV-1/3 |
| Schema Registry Outage | [§10](#10-schema-registry-outage) | 2 hours | SEV-3 |
| S3 Data Corruption | [§11](#11-s3-data-corruption) | 15 min | SEV-2 |
| Data Broker Failure | [§12](#12-data-broker-failure) | 10 min | SEV-1 |
| Aurora DB Failover | [§13](#13-aurora-database-failover) | 5 min | SEV-1 |
| EKS Node Failure | [§14](#14-eks-node-failure) | 15 min | SEV-2 |
| EKS Cluster Recovery | [`docs/DISASTER-RECOVERY.md`](DISASTER-RECOVERY.md#5-eks-cluster-recovery) | 30 min | SEV-1 |
| MSK Cluster Recovery | [`docs/DISASTER-RECOVERY.md`](DISASTER-RECOVERY.md#6-msk-cluster-recovery) | 30 min | SEV-1 |
| DDoS / Security Incident | [`docs/SECURITY.md`](SECURITY.md#11-incident-response-security) | 5 min | SEV-1 |
| Full Region DR | [`docs/DISASTER-RECOVERY.md`](DISASTER-RECOVERY.md#10-cross-region-dr-future) | 4 hours | SEV-1 |
