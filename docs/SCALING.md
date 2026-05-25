# Scaling Strategy — Agora Platform

> **Target**: 60,000+ real-time events/sec, 10,000+ connected devices, multi-tenant workload isolation
> **Architecture**: 3-AZ multi-layer (MSK Express, Aurora PostgreSQL, EKS, S3 data lake)
> **Last Updated**: May 2026

---

## Table of Contents

1. [Scaling Philosophy](#1-scaling-philosophy)
2. [MSK Express — Kafka Scaling](#2-msk-express--kafka-scaling)
3. [Aurora PostgreSQL — Database Scaling](#3-aurora-postgresql--database-scaling)
4. [EKS — Kubernetes Cluster Scaling](#4-eks--kubernetes-cluster-scaling)
5. [Stream Processor Scaling (HPA)](#5-stream-processor-scaling-hpa)
6. [Kafka Topic Partition Expansion](#6-kafka-topic-partition-expansion)
7. [S3 Data Lake — Infinite Storage](#7-s3-data-lake--infinite-storage)
8. [Environment Comparison](#8-environment-comparison)
9. [Cost-Aware Scaling](#9-cost-aware-scaling)
10. [Operational Runbooks](#10-operational-runbooks)

---

## 1. Scaling Philosophy

Agora uses a **three-axis scaling model**:

| Axis | Mechanism | Time to Scale | Trigger |
|------|-----------|---------------|---------|
| **Vertical** | Increase instance size | Minutes | Persistent capacity压力的, cost optimisation reviews |
| **Horizontal** | Add more instances/nodes | Seconds–Minutes | Real-time load metrics (CPU, memory, consumer lag) |
| **Elastic** | Serverless auto-scaling | Sub-second | Demand spikes, pay-per-use for dev |

**Design principles:**
- Scale **out** before scaling **up** (prefer horizontal over vertical)
- Each layer scales **independently** (no coupled scaling)
- **Headroom** in every layer: target 60–70% utilisation to absorb spikes
- Scale **down** aggressively in dev, conservatively in prod

---

## 2. MSK Express — Kafka Scaling

### 2.1 Broker-Level Scaling

MSK Express handles the two hardest scaling problems automatically:
- **Storage**: Auto-scaling elastic storage (no EBS provisioning, no throughput bottlenecks)
- **Broker recovery**: 90% faster than Provisioned Standard

#### When to Add Brokers

| Signal | Threshold | Action |
|--------|-----------|--------|
| Broker CPU | > 60% for 15 min | Add 1 Express broker |
| BytesInPerSec | > 80% of per-broker limit | Add 1 Express broker |
| Produce request latency p99 | > 50ms for 5 min | Add 1 Express broker |
| Consumer lag growing | Lag > 1000 and trending up | Add brokers OR increase partitions/consumers |

#### How to Add Brokers

```bash
# Terraform: update variable and apply
# terraform/terraform.tfvars → increase msk_broker_count
msk_broker_count = 3   # → 4

terraform plan -out=tfplan
terraform apply tfplan
```

MSK Express adds brokers in **minutes** (20x faster than Standard). No data rebalancing needed — Express handles partition redistribution automatically.

#### Maximum Brokers

| Environment | Default | Max | Rationale |
|-------------|---------|-----|-----------|
| dev | N/A (serverless) | N/A | Pay-per-use, no broker management |
| staging | 3 | 6 | Cost-controlled, sufficient for load testing |
| production | 3 | 10 | 60K events/sec → 3 m7g.xlarge handles with headroom; 10 is ceiling for 200K+ events/sec |

### 2.2 Partition Scaling

Each broker supports ~4000 partitions on Express. For current topology (3 brokers):

| Topic | Current Partitions | Max Partitions | Bottleneck |
|-------|-------------------|----------------|------------|
| vehicle.telemetry | 12 | 4000 | Consumer parallelism |
| sensor.environmental | 6 | 4000 | Consumer parallelism |
| signal.events | 6 | 4000 | Consumer parallelism |
| incidents | 1 | 4000 | Ordering guarantee |
| data.anonymized.vehicle | 12 | 4000 | Consumer parallelism |
| signal.commands | 6 | 4000 | Intersection coverage |
| data.inventor.traffic | 3 | 4000 | Per-inventor isolation |
| alerts.notifications | 1 | 4000 | Ordering guarantee |

**Partition count formula** (for high-throughput topics):

```
partitions = max(
    expected_throughput_mbps / 2,    # ~2 MBps per partition conservative
    desired_consumer_parallelism,     # match max consumer count
    number_of_partition_keys * 2      # 2x partition keys for distribution
)
```

For `vehicle.telemetry` (10K msg/sec, ~10 MBps):
- 10 MBps / 2 = 5 partitions minimum
- Desired parallelism: 12 consumers
- Partition keys: 3 (autonomous, regular, emergency)
- **Result: 12 partitions** — gives room to 2x without data redistribution

### 2.3 Dev Environment: MSK Serverless

Dev uses MSK Serverless — pay-per-use, no cluster management:

```
msk_broker_type = "serverless"

# Auto-scales from 0 to 200 MBps throughput
# No broker count, no instance type, no storage management
# Auto-creates topics with 3 replication factor
```

**Limitations:**
- Max 5 MBps per shard (partition)
- Max throughput per cluster: 200 MBps
- No custom config (e.g., `auto.create.topics.enable`)

**When to migrate from Serverless to Express:**
- Sustained throughput > 50 MBps
- Need custom topic configuration
- Require enhanced monitoring (PER_TOPIC_PER_PARTITION)

---

## 3. Aurora PostgreSQL — Database Scaling

### 3.1 Aurora Auto-Scaling

Aurora PostgreSQL handles storage scaling automatically:
- **Storage**: Auto-scales in 10 GB increments up to 128 TB
- **No downtime**: Scaling is transparent to applications

### 3.2 Compute Scaling

#### Option A: Aurora Serverless v2 (dev)

```hcl
rds_instance_class    = "db.serverless"
rds_min_capacity      = 0.5   # ACU (min)
rds_max_capacity      = 2     # ACU (max)
```

- Scales from 0.5 ACU to 2 ACU based on load
- Pay-per-ACU-second
- Connection pooling handles up to ~1000 concurrent connections
- ~30 second failover

#### Option B: Provisioned with Replicas (staging/prod)

```hcl
# staging
rds_instance_class    = "db.r5.large"
rds_reader_count      = 1
rds_multi_az          = true

# production
rds_instance_class    = "db.r6g.xlarge"
rds_reader_count      = 2
rds_multi_az          = true
```

#### Scaling Readers

| Signal | Threshold | Action |
|--------|-----------|--------|
| Read replica lag | > 1 second for 5 min | Add reader replica |
| Connection count | > 80% of max_connections | Add reader replica + adjust pooler |
| CPU (writer) | > 70% for 10 min | Scale up instance class |
| Disk utilisation | > 100 GB free and growing | Aurora auto-scales — no action needed |

#### How to Scale

```bash
# Terraform: update reader count and apply
rds_reader_count = 2  # → 3

# Or scale up instance class
rds_instance_class = "db.r6g.xlarge"  # → "db.r6g.2xlarge"

terraform plan -out=tfplan
terraform apply tfplan
```

Adding a reader is zero-downtime. Aurora creates a new instance and adds it to the reader endpoint DNS rotation.

### 3.3 Connection Pooling

Aurora PostgreSQL has a default `max_connections` of ~5000 for r6g.xlarge. Use PgBouncer (sidecar or RDS Proxy) to:
- Multiplex thousands of application connections into ~100 database connections
- Prevent connection storms during pod scaling events
- Reduce memory pressure on the database

---

## 4. EKS — Kubernetes Cluster Scaling

### 4.1 Node Group Scaling (Karpenter / Cluster Autoscaler)

EKS node groups use **Karpenter** (preferred) or **Cluster Autoscaler** to add/remove EC2 instances.

#### Node Pool Configuration

```hcl
# production
node_instance_types   = ["m7g.xlarge", "m7g.2xlarge"]
desired_node_count    = 8
min_node_count        = 5
max_node_count        = 30
```

#### Karpenter Provisioner (recommended)

```yaml
apiVersion: karpenter.sh/v1alpha5
kind: Provisioner
metadata:
  name: agora-provisioner
spec:
  requirements:
    - key: karpenter.sh/capacity-type
      operator: In
      values: ["on-demand"]
    - key: node.kubernetes.io/instance-type
      operator: In
      values: ["m7g.xlarge", "m7g.2xlarge", "m7g.4xlarge"]
  limits:
    resources:
      cpu: 1000
  ttlSecondsAfterEmpty: 300  # Scale down nodes after 5 min idle
```

#### Scaling Behaviour

| Signal | Threshold | Action |
|--------|-----------|--------|
| Unschedulable pods | Any | Karpenter launches new node immediately |
| Node CPU | > 70% for 5 min | Karpenter adds node (conservative) |
| Node memory | > 80% for 5 min | Karpenter adds node |
| Node utilisation | < 40% for 5 min | Karpenter consolidates/drains nodes |
| Spot interruption | 2 min notice | Karpenter cordons + replaces |

### 4.2 Pod-Level Scaling (HPA)

| Service | Min | Max | CPU Trigger | Memory Trigger | Custom Metric |
|---------|-----|-----|-------------|----------------|---------------|
| traffic-optimizer | 3 | 10 | > 70% | > 80% | Consumer lag > 500 |
| energy-management | 2 | 6 | > 70% | > 80% | Consumer lag > 500 |
| data-broker | 5 | 20 | > 70% | > 80% | Consumer lag > 1000 |
| api-gateway | 5 | 15 | > 70% | > 80% | Request count > 5000/min |
| anomaly-detector | 2 | 8 | > 70% | > 80% | Consumer lag > 500 |
| kafka-connect | 3 | 10 | > 70% | > 80% | Task failures > 0 |
| schema-registry | 2 | 6 | > 70% | > 80% | Request latency > 500ms |

#### HPA Configuration (data-broker example)

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: data-broker-hpa
  namespace: city-services
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: data-broker
  minReplicas: 5
  maxReplicas: 20
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70
    - type: Resource
      resource:
        name: memory
        target:
          type: Utilization
          averageUtilization: 80
    - type: Pods
      pods:
        metric:
          name: kafka_consumer_lag
        target:
          type: AverageValue
          averageValue: 500
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 300  # Wait 5 min before scale-down
      policies:
        - type: Percent
          value: 50
          periodSeconds: 60
    scaleUp:
      stabilizationWindowSeconds: 0     # Immediate scale-up
      policies:
        - type: Percent
          value: 100                    # Double at a time
          periodSeconds: 15
        - type: Pods
          value: 4                      # Add 4 pods per 15s
          periodSeconds: 15
      selectPolicy: Max
```

### 4.3 Pod Disruption Budgets (PDB)

| Service | minAvailable | Rationale |
|---------|-------------|-----------|
| traffic-optimizer | 2 of 3 | Mission-critical, never below 2 |
| energy-management | 1 of 2 | Less critical |
| data-broker | 3 of 5 | High throughput, needs minimum parallelism |
| api-gateway | 3 of 5 | External-facing, must stay available |
| anomaly-detector | 1 of 2 | Best-effort |
| kafka-connect | 2 of 3 | Connector task redistribution |

---

## 5. Stream Processor Scaling (HPA)

Stream processors add a **custom metric** to standard HPA: **consumer lag**.

### Consumer-Lag-Based Scaling

```
consumer lag > threshold → HPA adds pods → more consumers join group
→ partitions redistributed → lag decreases → HPA scales down
```

#### Threshold Configuration

| Processor | Lag Threshold | Scale-Up Speed | Max Pods |
|-----------|--------------|----------------|----------|
| traffic-optimizer | 500 | Immediate (double) | 10 |
| data-broker | 1000 | Immediate (×4 per 15s) | 20 |
| anomaly-detector | 500 | Fast (double) | 8 |
| energy-optimizer | 500 | Normal | 6 |

### Important: Partition-Consumer Relationship

```
consumers ≤ partitions   # If consumers > partitions, extra consumers are idle
```

For `vehicle.telemetry` (12 partitions):
- Min 3 consumers, max 12 consumers (beyond 12, extra pods sit idle)
- To scale beyond 12, increase partitions first (see Section 6)

---

## 6. Kafka Topic Partition Expansion

### When to Expand Partitions

| Signal | Threshold |
|--------|-----------|
| Per-partition throughput | > 4 MBps sustained |
| Consumer group has idle members | Consumers > partitions |
| Partition CPU skew | One partition uses > 30% more CPU than others |

### How to Expand

```bash
# Step 1: Increase partition count
kafka-topics.sh --bootstrap-server b-1:9098,b-2:9098,b-3:9098 \
  --command-config admin-client.config \
  --alter \
  --topic vehicle.telemetry \
  --partitions 24

# Step 2: Verify
kafka-topics.sh --describe --topic vehicle.telemetry \
  --bootstrap-server b-1:9098,b-2:9098,b-3:9098

# Step 3: (If using Kafka Connect) restart connector to redistribute tasks
curl -X POST http://kafka-connect:8083/connectors/s3-sink-vehicle-telemetry/restart
```

### Partition Expansion Guidelines

| Rule | Explanation |
|------|-------------|
| Only increase, never decrease | Kafka does not support partition count reduction |
| Double at a time | Keeps key distribution clean (e.g., 12→24, not 12→15) |
| Update StreamApps config | If using Kafka Streams, update `num.stream.threads` |
| Rebalance expected | Brief rebalance as partitions redistribute — normal |

---

## 7. S3 Data Lake — Infinite Storage

S3 scales transparently to exabytes. The data lake buckets are:

| Bucket | Purpose | Lifecycle |
|--------|---------|-----------|
| `agora-{env}-data-lake` | Kafka archives + processed data | 30d Standard → Glacier → 7yr delete |
| `agora-{env}-app-logs` | CloudTrail, VPC flow logs, ALB logs | 7d Standard → Glacier → 1yr delete |
| `agora-{env}-access-logs` | S3 server access logs (audit) | 90d Standard → Glacier → 7yr delete |
| `agora-{env}-backups` | Terraform state, RDS exports, DR artifacts | 30d Standard → Glacier → 3yr delete |

### S3 Scaling Considerations

| Aspect | Limit | Notes |
|--------|-------|-------|
| Bucket size | Unlimited | No practical limit |
| Requests/sec | 5,500 GET / 3,500 PUT per prefix | Partition with date+hour prefixes |
| Multi-part upload | 5 GB–5 TB | Kafka Connect uses 64 MB parts |
| Throughput | 100+ Gbps per prefix | Use random prefix for extreme throughput |

**Kafka Connect S3 sink** partitions data by hour:
```
s3://agora-prod-data-lake/vehicle.telemetry/year=2026/month=05/day=16/hour=14/
```

Each directory prefix stays well within S3 request limits because each hour produces at most ~3.6 GB of compressed data.

---

## 8. Environment Comparison

| Dimension | dev | staging | production |
|-----------|-----|---------|------------|
| **MSK** | Serverless (auto-scale) | Express 3×m7g.large | Express 3×m7g.xlarge+ |
| **EKS nodes** | 2×t3.large (1–5) | 4×m7g.xlarge (3–12) | 8×m7g.xlarge (5–30) |
| **Aurora** | Serverless v2 (0.5–2 ACU) | r5.large + 1 reader | r6g.xlarge + 2 readers |
| **S3** | Single bucket (all-in-one) | Separated buckets | Full lifecycle + CRR |
| **Stream processors** | 1 replica each | 2–3 replicas | 3–5 replicas |
| **Kafka Connect** | 1 worker | 2 workers | 3 workers |
| **Scaling aggressiveness** | Very aggressive (scale to 0) | Moderate | Conservative |
| **Cost control** | Minimise (pay-per-use) | Balanced | Performance first |

### Dev Scaling Profile

```hcl
# MSK Serverless — auto-scales, pay-per-request
msk_broker_type       = "serverless"
# Aurora Serverless v2 — 0.5 to 2 ACU
rds_min_capacity      = 0.5
rds_max_capacity      = 2
# EKS — minimal
desired_node_count    = 2
min_node_count        = 1
max_node_count        = 5
```

### Staging Scaling Profile

```hcl
# Express — matches prod topology at smaller instance size
msk_broker_type       = "express"
msk_broker_count      = 3
msk_instance_type     = "express.m7g.large"
# Aurora — 1 reader for load testing
rds_reader_count      = 1
# EKS — moderate
desired_node_count    = 4
min_node_count        = 3
max_node_count        = 12
```

### Production Scaling Profile

```hcl
# Express — headroom for 60K events/sec
msk_broker_type       = "express"
msk_broker_count      = 3
msk_instance_type     = "express.m7g.xlarge"
# Aurora — 2 readers for read scaling + HA
rds_instance_class    = "db.r6g.xlarge"
rds_reader_count      = 2
rds_multi_az          = true
rds_backup_retention  = 30
# EKS — aggressive headroom
desired_node_count    = 8
min_node_count        = 5
max_node_count        = 30
```

---

## 9. Cost-Aware Scaling

### Monthly Estimate (Production)

| Service | Configuration | Est. Monthly Cost |
|---------|--------------|-------------------|
| MSK Express | 3 × express.m7g.xlarge | ~$4,500 |
| EKS | 8 × m7g.xlarge on-demand | ~$8,000 |
| Aurora | r6g.xlarge + 2 readers | ~$2,500 |
| S3 | 50 TB data lake + lifecycle | ~$600 |
| NAT Gateway | 3 AZs | ~$100 |
| CloudWatch | Dashboards + metrics + logs | ~$500 |
| KMS | 1 CMK per env | ~$1 |
| **Total** | | **~$16,200/month** |

### Cost-Saving Strategies

| Strategy | Impact | Effort |
|----------|--------|--------|
| Spot instances for EKS (dev/staging) | 60–70% node cost reduction | Low (add spot to Karpenter provisioner) |
| Scale to 0 in dev overnight | 50% dev cost reduction | Medium (K8s cron job + HPA min=0) |
| Aurora Serverless v2 in dev | Pay-per-ACU, no idle cost | Low (already configured) |
| MSK Serverless in dev | $0 idle cost (no cluster) | Low (already configured) |
| Lifecycle policies on S3 | 90% storage cost reduction | Low (already configured) |
| CloudWatch metric filters | Reduce log ingest costs | Medium |

---

## 10. Operational Runbooks

### Runbook 1: Scale EKS Node Group

```bash
#!/bin/bash
# scale-cluster.sh
ENV=${1:-production}
NEW_MAX=${2:-30}

# Option A: Karpenter — update provisioner limits
kubectl edit provisioner agora-provisioner

# Option B: Terraform
cd terraform/environments/$ENV
sed -i '' "s/max_node_count = [0-9]*/max_node_count = $NEW_MAX/" terraform.tfvars
terraform plan -out=tfplan
terraform apply tfplan
```

### Runbook 2: Add MSK Broker

```bash
# 1. Increase broker count in terraform.tfvars
msk_broker_count = 4

# 2. Apply
terraform plan -out=tfplan
terraform apply tfplan

# 3. Verify new broker
aws kafka list-nodes --cluster-arn $(aws kafka list-clusters --query "ClusterInfoList[?ClusterName=='agora-production'].ClusterArn" --output text)

# 4. Update bootstrap addresses in ConfigMaps (Terraform outputs new endpoints automatically)
kubectl rollout restart deployment -n city-services
```

### Runbook 3: Add Aurora Reader

```bash
# 1. Update terraform.tfvars
rds_reader_count = 3

# 2. Apply
terraform plan -out=tfplan
terraform apply tfplan

# 3. Verify
aws rds describe-db-clusters --db-cluster-identifier agora-production \
  --query 'DBClusters[0].DBClusterMembers[?IsClusterWriter==`false`].DBInstanceIdentifier'
```

### Runbook 4: Scale Stream Processor Manually

```bash
# Emergency scale-up (before HPA reacts)
kubectl scale deployment traffic-optimizer -n city-services --replicas=10

# Check HPA status
kubectl get hpa traffic-optimizer-hpa -n city-services

# Describe HPA (see metric values)
kubectl describe hpa traffic-optimizer-hpa -n city-services
```

### Runbook 5: Expand Kafka Topic Partitions

```bash
# Step 1: Check current partition count and distribution
kafka-topics.sh --describe --topic vehicle.telemetry \
  --bootstrap-server b-1:9098,b-2:9098,b-3:9098

# Step 2: Double partitions (only increase, never decrease)
kafka-topics.sh --alter --topic vehicle.telemetry \
  --partitions 24 \
  --bootstrap-server b-1:9098,b-2:9098,b-3:9098 \
  --command-config admin-client.properties

# Step 3: Verify
kafka-topics.sh --describe --topic vehicle.telemetry \
  --bootstrap-server b-1:9098,b-2:9098,b-3:9098

# Step 4: Update Kafka Connect connector tasks
curl -X POST http://kafka-connect:8083/connectors/s3-sink-vehicle-telemetry/restart
```

---

## Appendix: Key Terraform Variables for Scaling

```hcl
# terraform/terraform.tfvars (root)
msk_broker_count      = 3            # Number of Express brokers
msk_instance_type     = "express.m7g.xlarge"  # Broker instance size
node_instance_types   = ["m7g.xlarge", "m7g.2xlarge"]  # EKS node types
desired_node_count    = 8            # EKS desired nodes
min_node_count        = 5            # EKS minimum nodes
max_node_count        = 30           # EKS maximum nodes
rds_instance_class    = "db.r6g.xlarge"   # Aurora writer instance
rds_reader_count      = 2            # Aurora reader replicas
rds_min_capacity      = 0.5          # Aurora Serverless v2 min (dev only)
rds_max_capacity      = 2            # Aurora Serverless v2 max (dev only)
```
