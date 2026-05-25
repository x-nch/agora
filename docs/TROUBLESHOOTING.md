# Troubleshooting Guide — Agora Platform

> **Common issues, diagnostic procedures, and recovery steps for the Agora real-time event processing platform**
> **Target**: 60K events/sec, 10K devices, multi-tenant city OS
> **Last Updated**: May 2026

---

## Table of Contents

1. [Troubleshooting Methodology](#1-troubleshooting-methodology)
2. [MSK / Kafka Issues](#2-msk--kafka-issues)
3. [Aurora PostgreSQL Issues](#3-aurora-postgresql-issues)
4. [EKS / Kubernetes Issues](#4-eks--kubernetes-issues)
5. [Stream Processor Issues](#5-stream-processor-issues)
6. [Kafka Connect Issues](#6-kafka-connect-issues)
7. [Schema Registry Issues](#7-schema-registry-issues)
8. [S3 Data Lake Issues](#8-s3-data-lake-issues)
9. [IAM / Auth Issues](#9-iam--auth-issues)
10. [Network Issues](#10-network-issues)
11. [Performance Issues](#11-performance-issues)
12. [Alerts Reference](#12-alerts-reference)
13. [Health Check Endpoints](#13-health-check-endpoints)

---

## 1. Troubleshooting Methodology

### 1.1 The Checklist

When any issue arises, follow this sequence:

```
1. IS IT A SEEN ISSUE?     → Check this guide, known issues list
2. IS IT STILL HAPPENING?  → Check monitoring dashboards (CloudWatch, Grafana)
3. WHAT CHANGED?           → Check recent deployments, Terraform changes
4. WHICH LAYER?            → MSK | Aurora | EKS | App | Network | IAM
5. WHAT'S THE IMPACT?      → Degraded | Partial outage | Full outage
6. IS THERE A RUNBOOK?     → Follow DR runbook if applicable
```

### 1.2 Diagnostic Commands Cheat Sheet

```bash
# Layer-by-layer health check
# EKS
kubectl get nodes -o wide                          # Node health
kubectl get pods --all-namespaces -o wide          # Pod status
kubectl describe pod <pod> -n <ns>                 # Pod details
kubectl logs <pod> -n <ns>                         # Container logs
kubectl get events --all-namespaces --sort-by=.lastTimestamp  # Cluster events

# MSK
aws kafka describe-cluster --cluster-arn $ARN      # Cluster state
aws kafka list-nodes --cluster-arn $ARN            # Broker health
aws cloudwatch get-metric-statistics ...            # MSK metrics

# Aurora
aws rds describe-db-clusters --db-cluster-identifier agora-prod
aws rds describe-db-instances --db-instance-identifier agora-prod-writer

# Network
kubectl run -it --rm debug --image=nicolaka/netshoot -- /bin/bash  # Debug pod
```

### 1.3 Monitoring Dashboard Reference

| Dashboard | URL | Purpose |
|-----------|-----|---------|
| CloudWatch: EKS Overview | AWS Console → CloudWatch → Dashboards → agora-{env}-eks | Node health, pod capacity, API latency |
| CloudWatch: MSK Overview | AWS Console → CloudWatch → Dashboards → agora-{env}-msk | Broker CPU, request rate, consumer lag |
| CloudWatch: Aurora Overview | AWS Console → CloudWatch → Dashboards → agora-{env}-aurora | Connections, CPU, read replica lag |
| Grafana: Pipeline | Grafana → Dashboards → Agora Pipeline | Consumer lag, processing latency, error rate |
| Grafana: System Health | Grafana → Dashboards → System Health | Pod status, node health, cluster capacity |

---

## 2. MSK / Kafka Issues

### 2.1 Producer Cannot Connect to Bootstrap Brokers

**Symptoms:**
- Producer logs: `Connection to node -1 (b-1/10.0.x.x:9098) failed`
- CloudWatch alarm: `ProduceRecordCount` = 0
- Grafana: `kafka_producer_request_rate` = 0

**Causes & Fixes:**

| Cause | Check | Fix |
|-------|-------|-----|
| Wrong bootstrap port | Config uses port 9092 (plaintext) not 9098 (IAM) | Update to `b-1:9098,b-2:9098,b-3:9098` |
| IAM auth not configured | Missing AWS credentials in pod | Verify IRSA annotation on ServiceAccount |
| Network policy blocking | Check NetworkPolicy in pod namespace | Add egress rule for port 9098 to VPC CIDR |
| Security group blocking | Check MSK SG inbound rules | Add producer SG to MSK SG inbound |
| Broker not in service | MSK broker in `CREATING` or `UPDATING` state | Wait for completion (Express recovers in minutes) |

**Diagnostic Steps:**

```bash
# 1. Test connectivity from a pod
kubectl run -it --rm kafka-test --image=bitnami/kafka:3.6 -- /bin/bash
kafkacat -b b-1:9098,b-2:9098,b-3:9098 -L

# 2. Check network policy
kubectl get networkpolicy -n city-services
kubectl describe networkpolicy city-services-allow -n city-services

# 3. Check MSK cluster state
aws kafka describe-cluster --cluster-arn $CLUSTER_ARN --query 'ClusterInfo.State'
```

### 2.2 Consumer Lag Growing

**Symptoms:**
- CloudWatch alarm: `ConsumerLagHigh` — MaxOffsetLag > 1000 for 5 min
- Grafana: Consumer lag metric trending up
- Services processing slower than incoming data rate

**Causes & Fixes:**

| Cause | Check | Fix |
|-------|-------|-----|
| Insufficient consumers | `kafka-consumer-groups --describe` shows active consumers < partitions | Scale up HPA or increase partitions |
| Slow processing | `kubectl logs` shows processing time > 100ms | Optimize processor code, increase resources |
| Stuck consumer | Consumer in `STALLED` or `DEAD` state | Restart deployment: `kubectl rollout restart deploy/name` |
| Rebalance in progress | Consumer group in `REBALANCING` state | Wait (usually < 30s); check for frequent rebalances |
| Throttled producer | MSK `Throttling` metric > 0 | Add brokers or partitions |

**Diagnostic Steps:**

```bash
# 1. Check consumer group status
kafka-consumer-groups.sh --bootstrap-server b-1:9098,b-2:9098,b-3:9098 \
  --group traffic-optimizer-group \
  --describe

# Output shows: GROUP, TOPIC, PARTITION, CURRENT-OFFSET, LOG-END-OFFSET, LAG, CONSUMER-ID, HOST, CLIENT-ID

# 2. Check if consumers > partitions (wasted capacity)
kafka-consumer-groups.sh --describe --group traffic-optimizer-group | wc -l
# Should be <= number of partitions (12 for vehicle.telemetry)

# 3. Check HPA status
kubectl describe hpa traffic-optimizer-hpa -n city-services
# Look for: current metrics vs target metrics

# 4. Reset consumer group if needed (CAUTION: skips messages)
kafka-consumer-groups.sh --bootstrap-server b-1:9098,b-2:9098,b-3:9098 \
  --group traffic-optimizer-group \
  --topic vehicle.telemetry \
  --reset-offsets --to-latest --execute
```

### 2.3 Broker CPU High

**Symptoms:**
- CloudWatch: `CpuUser` > 60% for 15 min
- Performance degradation: produce/consume latency increases

**Causes & Fixes:**

| Cause | Check | Fix |
|-------|-------|-----|
| Insufficient brokers | `BytesInPerSec` / `BytesOutPerSec` near per-broker limit | Add Express broker via Terraform |
| No compression | Check producer config `compression.type` != none or snappy | Enable `snappy` compression on producer |
| Hot partition | Check partition-level metrics for skew | Redistribute partition keys |
| Too many topics/partitions | `kafka-topics --describe` lists excessive partitions | Consolidate topics, increase broker count |

**Diagnostic Steps:**

```bash
# 1. Check broker-level CPU
aws cloudwatch get-metric-statistics \
  --namespace AWS/Kafka \
  --metric-name CpuUser \
  --dimensions Name=Cluster Name,Value=agora-production \
  --start-time $(date -u -d '-1 hour' +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 300 \
  --statistics Average

# 2. Check per-broker metrics (find hot broker)
aws kafka list-nodes --cluster-arn $CLUSTER_ARN

# 3. Check network I/O per broker
aws cloudwatch get-metric-statistics \
  --namespace AWS/Kafka \
  --metric-name BytesInPerSec \
  --dimensions Name=Cluster Name,Value=agora-production Name=Broker ID,Value=1 \
  --start-time ... --end-time ... --period 300 --statistics Sum
```

### 2.4 Topic Not Found or Auto-Creation Fails

**Symptoms:**
- Producer error: `LEADER_NOT_AVAILABLE`
- Consumer error: `UNKNOWN_TOPIC_OR_PARTITION_Exception`
- MSK has `auto.create.topics.enable=false`

**Fix:**

```bash
# Verify topic exists
kafka-topics.sh --list --bootstrap-server b-1:9098,b-2:9098,b-3:9098

# Create topic manually
kafka-topics.sh --create \
  --topic vehicle.telemetry \
  --partitions 12 \
  --replication-factor 3 \
  --bootstrap-server b-1:9098,b-2:9098,b-3:9098 \
  --command-config admin-client.properties

# Or re-apply topic definitions from Terraform provisioner
```

### 2.5 Messages Being Lost

**Symptoms:**
- Consumer lag drops suddenly (offsets committed without processing)
- Missing data in downstream systems

**Causes & Fixes:**

| Cause | Fix |
|-------|-----|
| `enable.auto.commit=true` | Set to `false`, use manual commits |
| `acks=1` or `acks=0` | Set `acks=all` (safety-critical) |
| Consumer group rebalance with auto-commit | Manual commits + `max.poll.interval.ms` tuning |
| Producer retry exhaustion | Verify `retries=MAX_INT`, `delivery.timeout.ms=30000` |

---

## 3. Aurora PostgreSQL Issues

### 3.1 Database Connection Failures

**Symptoms:**
- Application logs: `FATAL: no pg_hba.conf entry`
- Application logs: `could not connect to server: Connection refused`
- Dashboards: Connections dropping to 0

**Causes & Fixes:**

| Cause | Check | Fix |
|-------|-------|-----|
| Security group | Check RDS SG inbound rules allow EKS nodes | Ensure EKS node SG is in the RDS SG inbound rule |
| Wrong endpoint | Using instance DNS instead of cluster endpoint | Use writer endpoint for writes, reader endpoint for reads |
| Max connections | `SELECT count(*) FROM pg_stat_activity;` | Add PgBouncer/RDS Proxy sidecar |
| Failover in progress | DB in `resetting-master-credentials` or `renaming` | Wait 30s, retry with exponential backoff |
| SSL not enforced | Connection without SSL when `rds.force_ssl=1` | Add `?ssl=true&sslmode=require` to connection string |

### 3.2 Read Replica Lag

**Symptoms:**
- CloudWatch: `AuroraReplicaLagMaximum` > 1 second
- Stale reads (application reads not seeing recent writes)

**Diagnostic Steps:**

```bash
# Check replica lag
aws rds describe-db-instances \
  --db-instance-identifier agora-production-reader-1 \
  --query 'DBInstances[0].ReadReplicaSourceDBInstanceIdentifier'

# Check replica lag from PostgreSQL
SELECT
  pid,
  application_name,
  state,
  sync_state,
  pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn) AS lag_bytes
FROM pg_stat_replication;

# Add reader if lag persists
# Terraform: rds_reader_count = 2 → 3
```

**Common Causes:**
- Heavy write workload on writer (batch operations, large transactions)
- Reader instance class too small (upgrade to match writer)
- Long-running queries on reader blocking replication

### 3.3 Slow Queries

**Symptoms:**
- Application latency > 100ms for DB queries
- CloudWatch: `DatabaseConnections` high
- CPU on database > 70%

**Diagnostic Steps:**

```bash
# Find slow queries
SELECT
  query,
  calls,
  mean_time,
  total_time,
  rows,
  shared_blks_hit,
  shared_blks_read
FROM pg_stat_statements
ORDER BY mean_time DESC
LIMIT 20;

# Check for blocking queries
SELECT
  blocked_locks.pid AS blocked_pid,
  blocked_activity.usename AS blocked_user,
  blocking_locks.pid AS blocking_pid,
  blocking_activity.usename AS blocking_user,
  blocked_activity.query AS blocked_statement,
  blocking_activity.query AS blocking_statement
FROM pg_catalog.pg_locks blocked_locks
JOIN pg_catalog.pg_stat_activity blocked_activity ON blocked_activity.pid = blocked_locks.pid
JOIN pg_catalog.pg_locks blocking_locks ON blocking_locks.locktype = blocked_locks.locktype
  AND blocking_locks.DATABASE IS NOT DISTINCT FROM blocked_locks.DATABASE
  AND blocking_locks.relation IS NOT DISTINCT FROM blocked_locks.relation
  AND blocking_locks.page IS NOT DISTINCT FROM blocked_locks.page
  AND blocking_locks.tuple IS NOT DISTINCT FROM blocked_locks.tuple
  AND blocking_locks.virtualxid IS NOT DISTINCT FROM blocked_locks.virtualxid
  AND blocking_locks.transactionid IS NOT DISTINCT FROM blocked_locks.transactionid
  AND blocking_locks.classid IS NOT DISTINCT FROM blocked_locks.classid
  AND blocking_locks.objid IS NOT DISTINCT FROM blocked_locks.objid
  AND blocking_locks.objsubid IS NOT DISTINCT FROM blocked_locks.objsubid
  AND blocking_locks.pid != blocked_locks.pid
JOIN pg_catalog.pg_stat_activity blocking_activity ON blocking_activity.pid = blocking_locks.pid
WHERE NOT blocked_locks.GRANTED;
```

### 3.4 Storage Full or Auto-Scaling

Aurora auto-scales storage. If you hit storage limits:

```bash
# Check storage
aws rds describe-db-clusters \
  --db-cluster-identifier agora-production \
  --query 'DBClusters[0].AllocatedStorage'

# Aurora auto-scales — no action needed
# If auto-scaling is slow, manually modify
aws rds modify-db-cluster \
  --db-cluster-identifier agora-production \
  --allocated-storage 1000 \
  --apply-immediately
```

---

## 4. EKS / Kubernetes Issues

### 4.1 Pod CrashLoopBackOff

**Symptoms:**
- `kubectl get pods` shows `CrashLoopBackOff`
- CloudWatch alarm: `PodCrashLooping`

**Diagnostic Steps:**

```bash
# Step 1: Check pod logs
kubectl logs traffic-optimizer-7d8f9c8b6-abcde -n city-services

# Step 2: Check previous pod logs (if current crash)
kubectl logs traffic-optimizer-7d8f9c8b6-abcde -n city-services --previous

# Step 3: Describe pod for events
kubectl describe pod traffic-optimizer-7d8f9c8b6-abcde -n city-services

# Step 4: Check resource limits
kubectl describe pod traffic-optimizer-7d8f9c8b6-abcde -n city-services | grep -A5 Limits
```

**Common Causes:**

| Error Message | Cause | Fix |
|--------------|-------|-----|
| `Failed to create pod sandbox` | Node resource pressure | Check node resources, Karpenter may need to launch new node |
| `OOMKilled` | Memory limit too low | Increase memory limit in deployment.yaml |
| `ImagePullBackOff` | Wrong image tag or registry | Fix image name/tag; check registry credentials |
| `CreateContainerConfigError` | Missing ConfigMap or Secret | Verify ConfigMap/Secret exists: `kubectl get cm/name -n ns` |
| `CrashLoopBackOff` (no logs) | Application error during startup | Increase startupProbe failureThreshold |

### 4.2 Pod Pending (Unschedulable)

**Symptoms:**
- Pod stuck in `Pending` state
- `kubectl describe pod` shows `0/5 nodes available`

**Diagnostic Steps:**

```bash
kubectl describe pod <pod> -n city-services | grep -A10 Events
```

| Message | Cause | Fix |
|---------|-------|-----|
| `Insufficient cpu` | No node with available CPU | Karpenter should launch new node (check Karpenter logs) |
| `Insufficient memory` | No node with available memory | Same as above |
| `node(s) had taints` | Pod toleration mismatch | Check node taints vs pod tolerations |
| `failed to bind volumes` | PVC not bound to PV | Check PVC status: `kubectl get pvc` |
| `0/5 nodes are available` | All nodes full or unhealthy | Check Karpenter: `kubectl logs -n karpenter deploy/karpenter` |

### 4.3 Karpenter Not Scaling

**Symptoms:**
- Pods pending but no new nodes
- Cluster under-provisioned

**Diagnostic Steps:**

```bash
# Check Karpenter logs
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter --tail=100

# Check Karpenter provisioner
kubectl get provisioners
kubectl describe provisioner agora-provisioner

# Check node utilization
kubectl top nodes

# Check if Karpenter has limits
kubectl get provisioner agora-provisioner -o yaml | grep -A5 limits
```

**Common Issues:**
- EC2 instance limit reached (request AWS limit increase)
- Karpenter CPU/memory limits hit
- Subnet CIDR exhaustion (unlikely with /16 VPC)
- Karpenter itself is not running (check its deployment)

### 4.4 Pod-to-Pod Communication Failure

**Symptoms:**
- Service A cannot reach Service B
- `Connection refused` or `Connection timed out`

**Diagnostic Steps:**

```bash
# Step 1: Verify service endpoints
kubectl get endpoints traffic-optimizer -n city-services

# Step 2: Test from within a pod
kubectl exec -it <pod> -n city-services -- curl http://traffic-optimizer.city-services:8080/health/live

# Step 3: Check network policies
kubectl get networkpolicy -n city-services
kubectl describe networkpolicy city-services-allow -n city-services

# Step 4: Check DNS resolution
kubectl exec -it <pod> -n city-services -- nslookup traffic-optimizer.city-services

# Step 5: Launch network debug pod
kubectl run -it --rm debug --image=nicolaka/netshoot -- /bin/bash
# Inside: curl, nslookup, ping, traceroute, tcpdump
```

**Common Issues:**
- NetworkPolicy `default-deny-all` blocking traffic
- Wrong service name (check for namespace: `service.namespace`)
- Service selector labels don't match pod labels
- TargetPort doesn't match containerPort

---

## 5. Stream Processor Issues

### 5.1 Processing Latency > SLO

**Symptoms:**
- Prometheus alert: `TrafficOptimizerLatencyBreach` (P99 > 100ms)
- Grafana: processing latency histogram shows high tail latency

**Diagnostic Steps:**

```bash
# 1. Check pod resource usage
kubectl top pod traffic-optimizer-xxxx -n city-services

# 2. Check if pods are CPU throttled
kubectl exec traffic-optimizer-xxxx -n city-services -- cat /sys/fs/cgroup/cpu/cpu.stat

# 3. Check consumer lag (indicates processing falling behind)
kafka-consumer-groups.sh --bootstrap-server b-1:9098,b-2:9098,b-3:9098 \
  --group traffic-optimizer-group --describe

# 4. Check GC logs (Java-based processors)
kubectl logs traffic-optimizer-xxxx -n city-services | grep -i "gc\|pause"
```

**Common Causes & Fixes:**

| Cause | Fix |
|-------|-----|
| CPU throttling (limits too low) | Increase CPU request/limit in deployment |
| GC pauses (Java/Kafka Streams) | Tune JVM GC settings, increase heap |
| Expensive transformation | Profile and optimise processing function |
| Insufficient partitions | Increase partition count for more parallelism |
| Network latency to MSK | Check AZ affinity (co-locate pods with brokers) |

### 5.2 Processor Throwing Exceptions

**Symptoms:**
- Error log spikes
- DLQ accumulating
- Consumer group rebalancing

**Diagnostic Steps:**

```bash
# 1. Check processor logs for stack traces
kubectl logs traffic-optimizer-xxxx -n city-services --tail=200 | grep -i "error\|exception\|trace"

# 2. Check DLQ for failed messages
kubectl logs dlq-processor-xxxx -n city-services
kfractl consume dlq.all --bootstrap-server b-1:9098,b-2:9098,b-3:9098 --from-beginning --max-messages 10

# 3. Check schema registry compatibility
curl http://schema-registry:8081/subjects/vehicle.telemetry-value/versions
```

**Common Exceptions:**

| Exception | Cause | Fix |
|-----------|-------|-----|
| `SerializationException` | Schema mismatch | Check AVRO schema compatibility, update schema |
| `KafkaException: record too large` | Message > `max.message.bytes` | Increase topic-level `max.message.bytes` |
| `TimeoutException` | Broker unavailable or network issue | Check MSK health, network policies |
| `OutOfMemoryError` | Insufficient heap | Increase memory limits, tune GC |
| `NullPointerException` | Unexpected null field | Add null checks in processor code |

### 5.3 Data Anonymization Issues

**Symptoms:**
- Raw vehicle IDs appearing in output topics
- GPS coordinates not rounded to grid
- Inventor receiving data they shouldn't

**Diagnostic Steps:**

```bash
# 1. Subscribe to output topic to verify
kfractl consume data.anonymized.vehicle \
  --bootstrap-server b-1:9098,b-2:9098,b-3:9098 \
  --from-beginning --max-messages 10

# 2. Check access control config
kubectl exec data-broker-xxxx -n city-services -- cat /etc/config/access-control.yaml

# 3. Check data broker logs
kubectl logs data-broker-xxxx -n city-services | grep -i "anonymiz\|access\|denied"
```

**Fixes:**
- Update `transformations/anonymizer.py` to strip additional fields
- Add field to PII list in configuration
- Update `access_control.py` rules for inventor permissions

---

## 6. Kafka Connect Issues

### 6.1 Connector in FAILED State

**Symptoms:**
- CloudWatch alarm: `ConnectorFailed`
- S3 data lake not receiving new data

**Diagnostic Steps:**

```bash
# 1. Check connector status
curl http://kafka-connect:8083/connectors/s3-sink-vehicle-telemetry/status

# 2. Check connector config
curl http://kafka-connect:8083/connectors/s3-sink-vehicle-telemetry

# 3. Check Connect worker logs
kubectl logs kafka-connect-xxxx -n city-services | grep -i "error\|exception\|fail"

# 4. Restart connector
curl -X POST http://kafka-connect:8083/connectors/s3-sink-vehicle-telemetry/restart
```

**Common Causes & Fixes:**

| Cause | Check | Fix |
|-------|-------|-----|
| S3 bucket access denied | Check IAM role for Connect worker | Update IAM policy with correct bucket ARN |
| Schema registry unavailable | Connect logs show `SchemaRegistryTimeout` | Restart schema registry, check network |
| Invalid connector config | `curl /connectors/name/config` shows errors | Validate JSON config, fix typo |
| Out of disk (stateful) | Connect worker pod OOM or disk full | Increase disk size, add workers |
| Too few tasks | `tasks.max` < number of partitions | Increase `tasks.max` to match partition count |

### 6.2 Connector Tasks Not Distributing Evenly

**Symptoms:**
- Some Connect workers idle, others overloaded
- Uneven data flow to S3

**Fix:**

```bash
# Check task distribution
curl http://kafka-connect:8083/connectors/s3-sink-vehicle-telemetry/tasks

# Increase tasks.max
curl -X PUT http://kafka-connect:8083/connectors/s3-sink-vehicle-telemetry/config \
  -H "Content-Type: application/json" \
  -d '{"tasks.max": 12, ...}'

# Rebalance Connect workers
curl -X POST http://kafka-connect:8083/connectors/s3-sink-vehicle-telemetry/restart?includeTasks=true
```

---

## 7. Schema Registry Issues

### 7.1 Schema Compatibility Errors

**Symptoms:**
- Producer error: `Schema being registered is incompatible with an earlier schema`
- Consumer error: `Schema not found`

**Diagnostic Steps:**

```bash
# Check schema versions
curl http://schema-registry:8081/subjects/vehicle.telemetry-value/versions

# Check compatibility level
curl http://schema-registry:8081/config/vehicle.telemetry-value

# Test a new schema for compatibility
curl -X POST http://schema-registry:8081/compatibility/subjects/vehicle.telemetry-value/versions \
  -H "Content-Type: application/vnd.schemaregistry.v1+json" \
  -d '{"schema": "{\"type\":\"record\",\"name\":\"VehicleTelemetry\",\"fields\":[...]}"}'
```

**Compatibility Types:**

| Type | Meaning | Use for |
|------|---------|---------|
| BACKWARD | New schema can read old data | Default — safest for most topics |
| FORWARD | Old schema can read new data | Evolving schemas (incidents) |
| FULL | Both backward and forward | Safety-critical (signal.commands) |
| NONE | No compatibility checks | Dev/test only |

### 7.2 Schema Registry Unavailable

**Symptoms:**
- Error: `RetryableConnectException: Connection refused`
- Processors using cached schemas (read-only mode)

**Fix:**

```bash
# 1. Check schema registry pod
kubectl get pod schema-registry-0 -n city-services
kubectl logs schema-registry-0 -n city-services

# 2. Restart
kubectl rollout restart statefulset schema-registry -n city-services

# 3. During downtime, processors use local schema cache
# No data is lost; new schemas cannot be registered
```

---

## 8. S3 Data Lake Issues

### 8.1 Kafka Connect Not Writing to S3

**Symptoms:**
- S3 bucket: no new objects for > 1 hour
- Connect connector in RUNNING state but `TotalRecordCount` not increasing

**Diagnostic Steps:**

```bash
# 1. Check connector metrics (flush size, record count)
curl http://kafka-connect:8083/connectors/s3-sink-vehicle-telemetry/status

# 2. Check S3 bucket exists
aws s3 ls s3://agora-prod-data-lake/

# 3. Check S3 bucket policy allows Connect IAM role
aws s3api get-bucket-policy --bucket agora-prod-data-lake

# 4. Check for old data — may be hitting flush.size before rotate.interval
# Increase flush.size or reduce rotate.interval.ms
```

### 8.2 Data Lake Object Corruption

**Symptoms:**
- Athena/Spark queries fail on archived data
- Deserialization errors in analytics

**Fix:**

```bash
# 1. Identify corrupt objects from Athena error logs
# 2. Restore from S3 versioning
aws s3api list-object-versions \
  --bucket agora-prod-data-lake \
  --prefix raw/vehicle.telemetry/year=2026/month=05/

# 3. Manually verify object
aws s3 cp s3://agora-prod-data-lake/raw/vehicle.telemetry/... ./test.avro
# Verify with avro-tools
java -jar avro-tools-1.11.1.jar tojson test.avro | head

# 4. If corruption is systematic, replay from source or other connector
```

### 8.3 Lifecycle Policy Issues

**Symptoms:**
- Objects deleted prematurely
- Storage costs higher than expected

**Diagnostic Steps:**

```bash
# Check lifecycle policy
aws s3api get-bucket-lifecycle-configuration --bucket agora-prod-data-lake

# Check storage class distribution
aws s3api list-objects-v2 \
  --bucket agora-prod-data-lake \
  --query 'Contents[*].[Key,StorageClass]' \
  --output table

# Check for objects that should have transitioned but didn't
# (Object size < 128KB for Glacier transition)
```

---

## 9. IAM / Auth Issues

### 9.1 Pod Cannot Authenticate to MSK (IAM Auth)

**Symptoms:**
- Error: `AuthorizationException: User: arn:aws:iam::... is not authorized to perform: kafka-cluster:Connect`
- Error: `org.apache.kafka.common.errors.SaslAuthenticationException`

**Diagnostic Steps:**

```bash
# 1. Check ServiceAccount annotation
kubectl get sa traffic-optimizer -n city-services -o yaml | grep annotations -A5
# Expected: eks.amazonaws.com/role-arn: arn:aws:iam::ACCOUNT:role/TrafficOptimizerMSKRole

# 2. Check IAM role trust policy
aws iam get-role --role-name TrafficOptimizerMSKRole --query 'Role.AssumeRolePolicyDocument'

# 3. Check IAM policy allows kafka-cluster actions
aws iam get-role-policy --role-name TrafficOptimizerMSKRole --policy-name MSKAccess

# 4. Check OIDC provider exists
aws iam list-open-id-connect-providers | grep $(aws eks describe-cluster \
  --name agora-production --query "cluster.identity.oidc.issuer" --output text | cut -d/ -f4)
```

**Common Fixes:**

| Issue | Fix |
|-------|-----|
| Wrong IAM role ARN in annotation | Update ServiceAccount annotation |
| Role trust policy has wrong OIDC URL | Update trust policy to match cluster |
| Missing kafka-cluster:IAM access permission | Add `kafka-cluster:DescribeCluster` action |
| Wrong MSK port (9092 vs 9098) | Use port 9098 for IAM auth |
| AWS SDK not configured for IAM | Ensure AWS SDK v2+ with IAM auth configured |

### 9.2 Cross-Account Access Issues

**Symptoms:**
- Inventor cannot access S3 data lake
- External service cannot invoke API Gateway

**Diagnostic Steps:**

```bash
# Check bucket policy allows external/inventor access
aws s3api get-bucket-policy --bucket agora-prod-data-lake

# Check KMS key policy allows cross-account use
aws kms get-key-policy --key-id $KMS_KEY_ID --policy-name default
```

---

## 10. Network Issues

### 10.1 VPC Flow Logs Analysis

```sql
-- Athena query against VPC flow logs
-- Find rejected connections (security group blocks)
SELECT
  dstaddr,
  dstport,
  action,
  COUNT(*) AS attempts
FROM vpc_flow_logs
WHERE
  action = 'REJECT'
  AND log_status = 'OK'
  AND date = '2026/05/16'
GROUP BY dstaddr, dstport, action
ORDER BY attempts DESC
LIMIT 20;

-- Find top talkers
SELECT
  srcaddr,
  dstaddr,
  SUM(bytes) AS total_bytes
FROM vpc_flow_logs
WHERE date = '2026/05/16'
GROUP BY srcaddr, dstaddr
ORDER BY total_bytes DESC
LIMIT 20;
```

### 10.2 NAT Gateway Connectivity Issues

**Symptoms:**
- Pods in private subnets cannot reach internet (Docker Hub, etc.)
- Timeout errors for external API calls

**Diagnostic Steps:**

```bash
# Test internet connectivity from a pod
kubectl exec -it debug-pod -n city-services -- curl -I https://google.com

# Check NAT Gateway metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/NATGateway \
  --metric-name PacketsDropCount \
  --dimensions Name=NatGatewayId,Value=$NAT_GW_ID \
  --start-time ... --end-time ... --period 300 --statistics Sum

# Check route tables
aws ec2 describe-route-tables \
  --filters Name=vpc-id,Values=$VPC_ID \
  --query 'RouteTables[].Routes[?DestinationCidrBlock==`0.0.0.0/0`]'
```

### 10.3 ALB/Ingress Connectivity

**Symptoms:**
- Cannot reach API gateway from outside
- 503 Service Temporarily Unavailable

**Diagnostic Steps:**

```bash
# Check ingress status
kubectl get ingress api-gateway -n city-services
kubectl describe ingress api-gateway -n city-services

# Check ALB controller logs
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller

# Check target group health
aws elbv2 describe-target-health \
  --target-group-arn $TARGET_GROUP_ARN

# Check if service endpoints exist
kubectl get endpoints api-gateway -n city-services
```

---

## 11. Performance Issues

### 11.1 End-to-End Latency > 100ms (SLO Breach)

**Triage checklist:**

```
Check                    | Tool
─────────────────────────|─────────────────────
Device → Gateway latency | Gateway access logs
Gateway → MSK latency    | MSK CloudWatch metrics
MSK consumer lag         | kafka-consumer-groups
Processor processing time| Custom metrics (histogram)
Processor → output topic | MSK produce metrics
Downstream processing    | Service metrics
```

**Common Bottlenecks:**
1. **Producer batching**: `linger.ms` too high → reduce to 5-10ms
2. **Consumer slow**: CPU/memory limit → increase resources
3. **Network**: Cross-AZ traffic → co-locate pods in same AZ as brokers
4. **GC pause**: Java processor → tune GC, use G1GC
5. **Serialisation**: AVRO vs JSON → use AVRO (faster + smaller)

### 11.2 High Error Rate

**Symptoms:**
- Error rate > 0.1% for 5 min
- Prometheus alert: `ErrorRateHigh`

**Diagnostic Steps:**

```bash
# 1. Check error distribution by topic
# From Prometheus metrics:
rate(kafka_producer_error_total[5m]) by (topic)

# 2. Check error types
rate(processing_error_total[5m]) by (type)

# 3. Check DLQ content
# Errors should be in dlq.all topic — check what's failing
```

---

## 12. Alerts Reference

### 12.1 Critical Alerts (PagerDuty)

| Alert | Condition | Action |
|-------|-----------|--------|
| `MSKClusterOffline` | MSK cluster state != ACTIVE | Check MSK console; Terraform re-create if needed |
| `AuroraWriterDown` | Writer endpoint not reachable | Check failover; verify new writer |
| `ConsumerLagHigh` | MaxOffsetLag > 1000 for 5 min | Scale consumers, check for slow processing |
| `TrafficOptimizerLatencyBreach` | P99 > 100ms for 5 min | Investigate processing bottleneck |
| `ConnectorFailed` | Kafka Connect connector FAILED | Restart connector, check logs |
| `PodCrashLooping` | Pod restart rate > 0.1/s | Check pod logs, fix application error |
| `EksNodeGroupUnhealthy` | < min nodes available | Check Karpenter, EC2 limits |

### 12.2 Warning Alerts (Slack)

| Alert | Condition | Action |
|-------|-----------|--------|
| `BrokerCpuHigh` | CPU > 60% for 15 min | Plan broker scale-out |
| `AuroraReplicaLagWarning` | Lag > 1s for 5 min | Check heavy write workload |
| `SchemaRegistryErrors` | > 10 errors/min | Check schema compatibility |
| `DeadLetterQueueAccumulating` | DLQ > 1000 unprocessed | Investigate failed messages |
| `HighMemoryUsage` | Pod memory > 90% | Increase memory limits |
| `CertificateExpiryWarning` | SSL cert < 30 days | Renew certificate |

---

## 13. Health Check Endpoints

All services expose standard health endpoints:

| Endpoint | Purpose | Expected Response |
|----------|---------|-------------------|
| `/health/live` | Liveness probe — is process alive? | `200 OK` |
| `/health/ready` | Readiness probe — ready for traffic? | `200 OK` |
| `/health/startup` | Startup probe — initialized? | `200 OK` |
| `/metrics` | Prometheus metrics | Prometheus-format text |
| `/health/dependencies` | Downstream dependency status | JSON: `{"kafka":"up","db":"up","s3":"up"}` |

### Health Check Utility

```bash
#!/bin/bash
# scripts/health-check.sh
# Quick health check for all core services

ENV=${1:-production}
NAMESPACES=("city-services" "inventors" "monitoring")
SERVICES=("traffic-optimizer" "energy-management" "data-broker" "api-gateway" "prometheus" "grafana")

for ns in "${NAMESPACES[@]}"; do
  echo "=== $ns ==="
  for svc in "${SERVICES[@]}"; do
    status=$(kubectl get pod -n $ns -l app=$svc -o jsonpath='{.items[*].status.phase}' 2>/dev/null)
    echo "$svc: ${status:-Not found}"
  done
done

echo "=== MSK ==="
aws kafka list-clusters --query "ClusterInfoList[?ClusterName=='agora-$ENV'].State" --output text

echo "=== Aurora ==="
aws rds describe-db-clusters --db-cluster-identifier agora-$ENV \
  --query 'DBClusters[0].Status' --output text
```

---

## Appendix: Quick-Reference by Symptom

| Symptom | Likely Issue | First Action |
|---------|-------------|--------------|
| Pods stuck Pending | Node capacity / Karpenter | `kubectl describe pod` |
| Can't connect to Kafka | IAM auth / network policy | `kafkacat -b b-1:9098 -L` |
| Slow processing | CPU throttling / lag | `kubectl top pod` |
| DB connections failing | Aurora failover / SG | `kubectl exec debug -- psql ...` |
| Data missing in S3 | Connect connector failed | `curl /connectors/name/status` |
| Schema errors | Schema registry / compatibility | `curl /subjects/name/versions` |
| External API timeout | NAT Gateway / network | `kubectl exec debug -- curl ...` |
| Prometheus not scraping | ServiceMonitor config | `kubectl get servicemonitor` |
