# Architecture — Agora Platform

> **Complete technical architecture documentation for the Woven City Agora real-time event processing platform**
> **Last Updated**: May 2026

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Network Architecture (VPC)](#2-network-architecture-vpc)
3. [Compute Architecture (EKS)](#3-compute-architecture-eks)
4. [Event Streaming (MSK Kafka)](#4-event-streaming-msk-kafka)
5. [Database Architecture (Aurora PostgreSQL)](#5-database-architecture-aurora-postgresql)
6. [Storage Architecture (S3)](#6-storage-architecture-s3)
7. [Data Pipeline Architecture](#7-data-pipeline-architecture)
8. [Multi-Tenancy Architecture](#8-multi-tenancy-architecture)
9. [Observability Architecture](#9-observability-architecture)
10. [Security Architecture](#10-security-architecture)
11. [Disaster Recovery Architecture](#11-disaster-recovery-architecture)
12. [Istio Service Mesh](#12-istio-service-mesh)
13. [Architecture Decision Records](#13-architecture-decision-records)

---

## 1. Architecture Overview

### 1.1 Six-Layer Stack

```
┌──────────────────────────────────────────────────────────┐
│  6. INVENTOR ECOSYSTEM            External APIs, Sandbox  │
│     ┌──────────────────────────────────────────────────┐  │
│  5. APPLICATIONS                  Traffic, Energy, etc  │  │
│     └──────────────────────────────────────────────────┘  │
│  4. DATA BROKER & STREAM PROCESS  4 processors, DLQ       │
│     └──────────────────────────────────────────────────┘  │
│  3. EVENT STREAMING & STORAGE     MSK, S3, Aurora         │
│     └──────────────────────────────────────────────────┘  │
│  2. COMPUTE & ORCHESTRATION        EKS, Karpenter         │
│     └──────────────────────────────────────────────────┘  │
│  1. NETWORKING & SECURITY          VPC, IAM, KMS           │
└──────────────────────────────────────────────────────────┘
```

### 1.2 End-to-End Data Flow

```
[10,000+ IoT Devices]                         [External Inventors]
       │ mTLS                                       ▲
       ▼                                            │
┌─────────────────┐     ┌────────────────────┐      │
│  IoT Gateway    │────>│  API Gateway       │──────┘
│  (EKS)          │     │  (EKS, Ingress)    │
└─────────────────┘     └────────────────────┘
       │ Kafka produce (IAM auth, port 9098)
       ▼
┌──────────────────────────────────────────────┐
│              Amazon MSK Express              │
│  3 brokers × express.m7g.xlarge (prod)       │
│  8 topics, 3-way replication, 12 partitions  │
└──────────────────────────────────────────────┘
       │                    │                    │
       ▼                    ▼                    ▼
┌────────────┐    ┌──────────────┐    ┌──────────────────┐
│  Schema    │    │  Kafka       │    │  Stream          │
│  Registry  │    │  Connect S3  │    │  Processors      │
│  AVRO      │    │  → Data Lake │    │  (4 pods)        │
│  compat    │    │  Archive     │    │  Traffic, Anomaly,│
└────────────┘    └──────────────┘    │  Energy, Broker  │
                                      └──────────────────┘
                                              │
                                              ▼
                                    ┌──────────────────┐
                                    │  Output Topics   │
                                    │  + S3 Processed  │
                                    │  + Aurora        │
                                    └──────────────────┘
                                              │
                                              ▼
                                    ┌──────────────────┐
                                    │  Dead Letter     │
                                    │  Queue           │
                                    │  (dlq.all topic) │
                                    └──────────────────┘
```

### 1.3 AWS Service Map

| Layer | AWS Service | Purpose |
|-------|-------------|---------|
| Network | Amazon VPC | Isolated network with 3 AZs, public/private/database subnets |
| Compute | Amazon EKS | Kubernetes orchestration for 50+ microservices |
| Compute | AWS Karpenter | Node auto-scaling (EC2 instance management) |
| Streaming | Amazon MSK Express | Managed Kafka with auto-scaling storage, 3x throughput |
| Stream Proc | Amazon EKS (pods) | Stream processors running as K8s deployments |
| Database | Aurora PostgreSQL | Relational DB with <30s failover, auto-scaling storage |
| Cache | Amazon ElastiCache (Redis) | Rate limiting, aggregation cache |
| Time-series | Amazon Timestream | Sensor metric storage, analytical queries |
| Storage | Amazon S3 | Data lake, archive, logs, backups |
| Secrets | AWS Secrets Manager | Auto-rotating DB credentials |
| Monitoring | Amazon CloudWatch | Infrastructure dashboards, composite alarms |
| Monitoring | Amazon Managed Prometheus | Metrics aggregation (K8s + CloudWatch) |
| IAM | AWS IAM | Least-privilege roles, IRSA for K8s |
| Encryption | AWS KMS | Single CMK per environment |
| DNS | Amazon Route53 | Internal service discovery, external DNS |

---

## 2. Network Architecture (VPC)

### 2.1 VPC Design

```
VPC: 10.0.0.0/16 (production)
┌─────────────────────────────────────────────────────┐
│                  Availability Zones                   │
│  ┌─────────────────┐ ┌──────────────┐ ┌───────────┐ │
│  │    apne1-az1    │ │  apne1-az2  │ │ apne1-az3 │ │
│  │                 │ │              │ │           │ │
│  │ Public 10.0.1/24│ │ 10.0.2/24   │ │10.0.3/24  │ │
│  │ (IGW+NATGW)     │ │             │ │           │ │
│  ├─────────────────┤ ├──────────────┤ ├───────────┤ │
│  │ Private 10.0.11 │ │ 10.0.12     │ │10.0.13    │ │
│  │ (EKS nodes,     │ │             │ │           │ │
│  │  MSK, processors)│ │             │ │           │ │
│  ├─────────────────┤ ├──────────────┤ ├───────────┤ │
│  │ Database 10.0.21│ │ 10.0.22     │ │10.0.23    │ │
│  │ (Aurora subnet) │ │             │ │           │ │
│  └─────────────────┘ └──────────────┘ └───────────┘ │
└─────────────────────────────────────────────────────┘
```

**Subnet allocation:**

| Subnet Type | CIDR (prod) | Purpose |
|-------------|-------------|---------|
| Public | 10.2.1.0/24, .2.0/24, .3.0/24 | NAT Gateways, ALB, Internet Gateway |
| Private | 10.2.11.0/24, .12.0/24, .13.0/24 | EKS nodes, MSK, stream processors |
| Database | 10.2.21.0/24, .22.0/24, .23.0/24 | Aurora PostgreSQL (isolated) |

**Environment differences:**

| CIDR Range | Dev | Staging | Prod |
|------------|-----|---------|------|
| VPC | 10.0.0.0/16 | 10.1.0.0/16 | 10.2.0.0/16 |
| AZs | 2 | 3 | 3 |
| NAT GW | Single (cost) | 2 (HA) | 3 (full HA) |

### 2.2 Connectivity

```
Internet
    │
    ▼
┌──────────┐
│ IGW      │─── Internet Gateway (single)
└──────────┘
    │
    ▼
┌──────────┐      ┌──────────┐      ┌──────────┐
│ ALB      │      │ NAT GW-1 │      │ NAT GW-2 │
│ (public) │      │ (AZ-1)   │      │ (AZ-2)   │
└──────────┘      └──────────┘      └──────────┘
    │                  │                  │
    ▼                  ▼                  ▼
┌──────────────────────────────────────────┐
│         Private Subnets (per AZ)          │
│  EKS nodes → MSK → Aurora → S3 Endpoint  │
└──────────────────────────────────────────┘
```

### 2.3 VPC Endpoints

All AWS API calls stay within AWS network (no internet transit):

```
VPC Endpoints:
├── com.amazonaws.apne1.s3          # Gateway Endpoint (S3 access)
├── com.amazonaws.apne1.ecr.api     # Interface Endpoint (ECR API)
├── com.amazonaws.apne1.ecr.dkr    # Interface Endpoint (ECR Docker)
├── com.amazonaws.apne1.secretsmanager  # Secrets Manager
├── com.amazonaws.apne1.monitoring  # CloudWatch
├── com.amazonaws.apne1.logs       # CloudWatch Logs
└── com.amazonaws.apne1.aps-workspaces  # AMP workspace
```

---

## 3. Compute Architecture (EKS)

### 3.1 Cluster Configuration

| Parameter | Dev | Staging | Production |
|-----------|-----|---------|------------|
| K8s version | 1.28 | 1.28 | 1.28 |
| Node types | t3.large | m7g.xlarge | m7g.xlarge, m7g.2xlarge |
| Min/Des/Max | 1/2/5 | 3/4/12 | 5/8/30 |
| Autoscaler | Karpenter | Karpenter | Karpenter |
| Logging | audit, api | audit, api, controller | all |

### 3.2 Namespace Architecture

```
┌─────────────────────────────────────────────────┐
│                    EKS Cluster                    │
│                                                   │
│  ┌────────────────┐  ┌────────────┐  ┌────────┐  │
│  │ city-services  │  │ inventors  │  │monitor-│  │
│  │                │  │            │  │ ing    │  │
│  │ traffic-opt    │  │ inventor-A │  │Prometh-│  │
│  │ energy-mgmt    │  │ inventor-B │  │ eus    │  │
│  │ data-broker    │  │ inventor-C │  │Grafana │  │
│  │ api-gateway    │  │            │  │        │  │
│  │ kafka-connect  │  │            │  │        │  │
│  │ schema-registry│  │            │  │        │  │
│  └────────────────┘  └────────────┘  └────────┘  │
└─────────────────────────────────────────────────┘
```

### 3.3 Multi-Tenancy Enforcement

| Mechanism | city-services | inventors |
|-----------|--------------|-----------|
| **Network** | Allow intra-namespace, allow to MSK | Allow from API gateway only |
| **RBAC** | Read-write (services, pods, configmaps) | Read-only (deployments, pods) |
| **CPU quota** | 20 requests / 30 limits | 5 requests / 10 limits |
| **Memory quota** | 40Gi requests / 60Gi limits | 10Gi requests / 20Gi limits |
| **Pod limit** | 100 | 20 |
| **Storage quota** | 500Gi | 100Gi |

### 3.4 Service Scaling Configuration

| Service | Replicas | HPA Min→Max | CPU Trigger | Lag Trigger | PDB |
|---------|----------|-------------|-------------|-------------|-----|
| traffic-optimizer | 3 | 3→10 | 70% | 500 | minAvailable 2 |
| energy-management | 2 | 2→6 | 70% | 500 | minAvailable 1 |
| data-broker | 5 | 5→20 | 70% | 1000 | minAvailable 3 |
| api-gateway | 5 | 5→15 | 70% | N/A | minAvailable 3 |
| anomaly-detector | 2 | 2→8 | 70% | 500 | minAvailable 1 |
| kafka-connect | 3 | 3→10 | 70% | N/A | minAvailable 2 |
| schema-registry | 2 | 2→6 | 70% | N/A | minAvailable 1 |

---

## 4. Event Streaming (MSK Kafka)

### 4.1 Cluster Configuration

| Parameter | Dev | Staging | Production |
|-----------|-----|---------|------------|
| Broker type | Serverless | Express | Express |
| Broker count | N/A | 3 | 3 |
| Instance type | N/A | express.m7g.large | express.m7g.xlarge |
| Kafka version | 3.6 (auto) | 3.6 | 3.6 |
| Storage | Auto (up to 200 MBps) | Auto-scaling | Auto-scaling |
| Auth | IAM (port 9098) | IAM (port 9098) | IAM (port 9098) |
| Encryption | TLS + KMS | TLS + KMS | TLS + KMS |
| Monitoring | DEFAULT | PER_TOPIC_PER_PARTITION | PER_TOPIC_PER_PARTITION |
| Custom config | N/A (Serverless) | auto.create.topics=false | auto.create.topics=false |

### 4.2 Topic Architecture

| Topic | Partitions | Replication | Retention | Msg/sec | Partition Key | Consumers |
|-------|-----------|-------------|-----------|---------|---------------|-----------|
| `vehicle.telemetry` | 12 | 3 | 7d → S3 | 10K+ | vehicle_type | traffic-opt, anomaly, data-broker |
| `sensor.environmental` | 6 | 3 | 7d → S3 | 5K+ | district | energy-opt, data-broker |
| `signal.events` | 6 | 3 | 7d → S3 | 2K+ | intersection_id | traffic-opt, data-broker |
| `incidents` | 1 | 3 | 30d | 100 | N/A | anomaly, alerts |
| `signal.commands` | 6 | 3 | 2d | 1K+ | intersection_id | traffic-opt output |
| `data.anonymized.vehicle` | 12 | 3 | 30d | 10K+ | district | data-broker output |
| `data.inventor.traffic` | 3 | 3 | 7d | 500 | inventor_id | data-broker output |
| `alerts.notifications` | 1 | 3 | 90d | 50 | N/A | any |
| `dlq.all` | 1 | 3 | 30d | 10 | N/A | dlq-processor |

### 4.3 Partition Count Rationale

For `vehicle.telemetry` (10K msg/sec = ~10 MBps):
- 12 partitions × ~830 msg/sec per partition = well under limits
- Allows 12 parallel consumer pods
- Room to grow: double to 24 without rebalancing entire cluster
- Partition by `vehicle_type` (autonomous, regular, emergency) — 3 key values × 4 partitions each

For `sensor.environmental` (5K msg/sec):
- 6 partitions × ~830 msg/sec
- Partition by `district` (5 districts + 1 spare)

### 4.4 MSK IAM Auth (Port 9098)

```
Pod (traffic-optimizer)
  ↓ Kubernetes ServiceAccount with IRSA annotation
  ↓ IAM Role (TrafficOptimizerMSKRole)
  ↓ IAM policy: kafka-cluster:Connect, kafka-topic:Read/Write
  ↓ AWS SDK signs Kafka requests with IAM
  ↓ MSK Express on port 9098 validates IAM signature
  ↓ Pod produces/consumes — no secrets, no passwords
```

---

## 5. Database Architecture (Aurora PostgreSQL)

### 5.1 Cluster Configuration

| Parameter | Dev | Staging | Production |
|-----------|-----|---------|------------|
| Engine | Aurora PostgreSQL 15.4 | Aurora PostgreSQL 15.4 | Aurora PostgreSQL 15.4 |
| Instance class | db.serverless (0.5–2 ACU) | db.r5.large | db.r6g.xlarge |
| Reader count | 0 | 1 | 2 |
| Multi-AZ | false | true | true |
| Storage | Auto (10 GB–128 TB) | Auto | Auto |
| Backup retention | 7 days | 14 days | 30 days |
| Performance Insights | true (7 days) | true (7 days) | true (7 days) |
| Deletion protection | false | true | true |

### 5.2 Connection Architecture

```
[Application Pods]
       │
       ▼
┌────────────────┐
│  PgBouncer     │── Connection pooling (sidecar or RDS Proxy)
│  (sidecar)     │   Multiplex 1000s app connections → ~100 DB conns
└────────────────┘
       │
       ▼
┌──────────────────────────────────────────┐
│         Aurora Cluster (Writer)           │
│  writer-endpoint:  cluster-xxxx.rds...   │
└──────────────────────────────────────────┘
       │                    │
       ▼                    ▼
┌────────────┐    ┌────────────────┐
│ Reader 1   │    │  Reader 2       │
│ (AZ-1c)    │    │  (AZ-1d)       │
│ read-only  │    │  read-only     │
└────────────┘    └────────────────┘
       │                    │
       └────────────────────┘
               │
               ▼
     reader-endpoint: cluster-ro-xxxx.rds...
```

### 5.3 Failover Behaviour

```
Normal: Writer (AZ-1a) → Reader (AZ-1c) → Reader (AZ-1d)
             │
Failure: Writer (AZ-1a) DOWN
             │
30 seconds later:
  Reader (AZ-1c) promoted to Writer
  New reader launching in AZ-1a/1d
  Writer endpoint DNS updated
  Cluster fully operational within ~60 seconds
```

---

## 6. Storage Architecture (S3)

### 6.1 Bucket Design

| Bucket Name | Purpose | Lifecycle Policy |
|-------------|---------|-----------------|
| `agora-{env}-data-lake` | Kafka archives, processed device data, anonymized datasets | 30d Standard → Intelligent-Tiering → Glacier after 90d → delete after 7yr |
| `agora-{env}-app-logs` | CloudTrail, VPC flow logs, ALB logs, application logs | 7d Standard → Glacier after 30d → delete after 1yr |
| `agora-{env}-access-logs` | S3 server access logs (audit trail) | 90d Standard → Glacier after 1yr → delete after 7yr |
| `agora-{env}-backups` | Terraform state backups, RDS snapshot exports, DR artifacts | 30d Standard → Glacier after 90d → delete after 3yr |

### 6.2 S3 Archive Path Structure (Kafka Connect S3 Sink)

```
s3://agora-prod-data-lake/
├── raw/
│   ├── vehicle.telemetry/
│   │   └── year=2026/month=05/day=16/hour=14/
│   │       ├── vehicle.telemetry+0+0000001.avro
│   │       ├── vehicle.telemetry+1+0000001.avro
│   │       └── ...
│   ├── sensor.environmental/
│   ├── signal.events/
│   └── incidents/
├── processed/
│   ├── anonymized-vehicle/
│   └── inventor-traffic/
└── analytics/
    └── district-aggregates/
```

### 6.3 Security Controls

| Control | Implementation |
|---------|---------------|
| Encryption | SSE-KMS (single CMK per environment) |
| Versioning | Enabled on all buckets |
| Public access | Blocked (account-level + bucket-level) |
| TLS enforcement | Bucket policy: `aws:SecureTransport` = true |
| Access logging | All buckets log to `agora-{env}-access-logs` |
| Object lock | Enabled on backups bucket (WORM) |

---

## 7. Data Pipeline Architecture

### 7.1 Pipeline Components

```
[Input Topics]              [Processors]           [Output Topics]
                                                
vehicle.telemetry ──┬──→ traffic-optimizer ──→ signal.commands
                    │                         incidents
                    │
                    ├──→ anomaly-detector ───→ incidents
                    │                         alerts.notifications
                    │
                    └──→ data-broker ────────→ data.anonymized.vehicle
                                               data.inventor.traffic
                                               S3 processed/

sensor.environmental ─→ energy-optimizer ────→ alerts.notifications
                    │                         energy.commands
                    └──→ data-broker ────────→ data.anonymized.vehicle

signal.events ──────┬──→ traffic-optimizer ──→ signal.commands
                    └──→ data-broker ────────→ data.anonymized.vehicle
```

### 7.2 Stream Processor Details

| Processor | Input | Output | SLO | Resource | Key Logic |
|-----------|-------|--------|-----|----------|-----------|
| Traffic Optimizer | vehicle.telemetry, signal.events | signal.commands, incidents | <100ms P99 | 1 CPU, 2GB | 5s sliding window, queue thresholds, green phase extension |
| Anomaly Detector | vehicle.telemetry | incidents, alerts.notifications | <500ms | 2 CPU, 4GB | ML model (pre-trained), feature extraction, score > 0.8 triggers |
| Energy Optimizer | sensor.environmental | alerts.notifications, energy.commands | <1s | 500m CPU, 1GB | Weather + consumption + occupancy, shift peak → off-peak |
| Data Broker | vehicle.telemetry, sensor.environmental, signal.events | data.anonymized.vehicle, data.inventor.traffic | <200ms | 2 CPU, 4GB | PII stripping, GPS rounding, per-inventor access control |

### 7.3 Dead Letter Queue Flow

```
Failed message (deserialization, processing, schema violation)
  ↓
Processor catches exception
  ↓
Writes to dlq.all with metadata:
  - Original message (raw bytes)
  - Error type + stack trace + timestamp
  - Source topic + partition + offset
  - Processing stage
  ↓
DLQ Processor reads dlq.all
  ↓
Classifies:
  Schema violation → notify team
  Deserialization → log + alert
  Transient → retry 3x then discard
  Poison pill → log + alert (bad producer)
```

### 7.4 Schema Registry

| Topic | Compatibility | Rationale |
|-------|--------------|-----------|
| Default | BACKWARD | Consumers can read old+new data |
| incidents | FORWARD_TRANSITIVE | Schema evolves frequently (new anomaly types) |
| signal.commands | BACKWARD | Safety-critical, strict compatibility |
| dlq.all | NONE | Best-effort capture, no consumer guarantees |

---

## 8. Multi-Tenancy Architecture

### 8.1 Isolation Layers

| Layer | city-services | inventors |
|-------|--------------|-----------|
| **K8s Namespace** | Dedicated namespace | Dedicated namespace |
| **Network** | Can talk to MSK, other city-services | Can only talk via API gateway |
| **RBAC** | Can create/update services, read configmaps | Read-only pods, deployments |
| **Resource Quota** | 20 CPU, 40GB memory, 100 pods | 5 CPU, 10GB memory, 20 pods |
| **Data Access** | Full access to raw/processed topics | Anonymized data only via data broker |
| **API Rate Limit** | Internal (higher limits) | External (lower limits, API keys) |
| **Audit** | Standard audit | Enhanced audit (inventor activity) |

### 8.2 Data Broker Anonymization

```
Raw vehicle event:
  {vehicle_id: "V-12345", type: "sedan", lat: 35.123456, lng: 140.456789, speed: 45}

  ↓ Strip vehicle_id
  ↓ Round GPS to 100m grid (35.12, 140.46)
  ↓ Remove driver identity, payment info

Anonymized:
  {vehicle_type: "sedan", grid_lat: 35.12, grid_lng: 140.46, speed: 45}

Aggregated (10s tumbling window per district):
  {district: "mobility", avg_speed: 42, vehicle_count: 38, congestion: "medium"}
```

---

## 9. Observability Architecture

### 9.1 Phase Boundary

| Layer | Phase 1 (Terraform IaC) | Phase 2 (Kubernetes) |
|-------|------------------------|---------------------|
| Infrastructure | CloudWatch dashboards + alarms + SNS | N/A |
| Kubernetes | N/A | Prometheus + Grafana (in-cluster) |
| Pipeline | N/A | Prometheus rules (consumer lag, throughput) |
| Metrics | AWS-managed (MSK, Aurora, ALB) | Application metrics (custom histogram) |

### 9.2 CloudWatch Dashboards

| Dashboard | Widgets |
|-----------|---------|
| agora-{env}-eks | Node count, pod capacity, API server latency, node CPU/memory |
| agora-{env}-msk | Broker CPU, BytesIn/Out, consumer lag (per group), request rate |
| agora-{env}-aurora | Connections, CPU, read replica lag, failover events, storage |
| agora-{env}-alb | Request count, target response time, error rate (5xx, 4xx) |
| agora-{env}-vpc | Top talkers, rejected connections (flow logs summary) |

### 9.3 SNS Alert Tiers

| Topic | Severity | Destination | Example Alarms |
|-------|----------|-------------|----------------|
| agora-{env}-critical | P1 | PagerDuty + Slack | AZ failure, cluster down, Kafka broker dead |
| agora-{env}-warning | P2 | Slack | High CPU, approaching storage limits, elevated error rate |
| agora-{env}-info | P3 | Log | Daily rollup, cost anomalies, certificate expiry |

### 9.4 Prometheus Alert Rules (Phase 2)

| Rule | Condition | Severity |
|------|-----------|----------|
| TrafficOptimizerLatencyHigh | P99 > 100ms for 5min | Critical |
| EnergyManagementErrorRate | > 0.1% for 5min | Warning |
| PodCrashLooping | restart rate > 0.1/s | Critical |
| HighMemoryUsage | > 90% for 5min | Warning |
| ConsumerLagHigh | lag > 1000 for 5min | Critical |
| DeadLetterQueueAccumulating | unprocessed > 1000 | Warning |

---

## 10. Security Architecture

### 10.1 Encryption

| Layer | At Rest | In Transit |
|-------|---------|------------|
| MSK Kafka | KMS CMK | TLS 1.2+ |
| Aurora PostgreSQL | KMS CMK | SSL/TLS enforced (`rds.force_ssl=1`) |
| S3 | SSE-KMS | TLS 1.3 (bucket policy enforced) |
| EBS volumes | KMS CMK (default) | N/A |
| Secrets Manager | KMS CMK | TLS |

### 10.2 IAM Model

```
[IRSA Roles per Service]
  │
  ├── TrafficOptimizerMSKRole
  │   ├── kafka-cluster:Connect
  │   ├── kafka-cluster:DescribeGroup
  │   ├── kafka-topic:Read (vehicle.telemetry, signal.events)
  │   ├── kafka-topic:Write (signal.commands, incidents)
  │   └── [AssumeRolePolicy] → OIDC: traffic-optimizer-sa
  │
  ├── AnomalyDetectorMSKRole
  │   ├── kafka-cluster:Connect
  │   ├── kafka-topic:Read (vehicle.telemetry)
  │   ├── kafka-topic:Write (incidents, alerts)
  │   └── [AssumeRolePolicy] → OIDC: anomaly-detector-sa
  │
  ├── DataBrokerMSKRole
  │   ├── kafka-cluster:Connect
  │   ├── kafka-topic:Read (vehicle.telemetry, sensor.environmental, signal.events)
  │   ├── kafka-topic:Write (data.anonymized.vehicle, data.inventor.traffic)
  │   └── [AssumeRolePolicy] → OIDC: data-broker-sa
  │
  ├── KafkaConnectMSKRole
  │   ├── kafka-cluster:Connect
  │   ├── kafka-topic:Read (all raw topics)
  │   ├── s3:PutObject (data-lake bucket)
  │   └── [AssumeRolePolicy] → OIDC: kafka-connect-sa
  │
  └── SchemaRegistryMSKRole
      ├── kafka-cluster:Connect
      ├── kafka-topic:Read (_schemas)
      └── [AssumeRolePolicy] → OIDC: schema-registry-sa
```

### 10.3 Network Security

| Security Layer | Implementation |
|---------------|----------------|
| VPC isolation | Public/Private/Database subnets per AZ |
| Security groups | Per-service (EKS→MSK, EKS→Aurora, ALB→EKS) |
| Network policies | K8s-level: default-deny, allow-list only |
| VPC endpoints | S3, ECR, Secrets Manager, CloudWatch — no internet |
| Flow logs | VPC Flow Logs → S3 → Athena (audit) |
| DDoS protection | AWS Shield Standard (Advanced optional) |

---

## 11. Disaster Recovery Architecture

### 11.1 Terraform State Lock Infrastructure

The Terraform state backend uses a DynamoDB table for concurrent access control and an S3 bucket for durable state storage.

#### DynamoDB Lock Table Design

| Property | Value | Rationale |
|----------|-------|-----------|
| Table name | `terraform-lock` | Single table per account |
| Billing | PAY_PER_REQUEST | Lock operations are infrequent and low-volume |
| Hash key | `LockID` (String) | S3 key path (e.g., `agora-terraform-state/dev/terraform.tfstate`) |
| PITR | Enabled | Point-in-time recovery for lock audit trail |
| Streams | KEYS_ONLY | Enables monitoring for stale lock detection |
| TTL | Attribute `TimeToExist` | Auto-expires lock entries after configurable duration |
| SSE | Enabled | Encryption at rest |

#### S3 State Bucket Lifecycle

| Rule | Action | Purpose |
|------|--------|---------|
| Noncurrent version expiration | Delete after 90 days | Prevent state version accumulation |
| Abort incomplete multipart upload | After 7 days | Clean up failed uploads |
| Versioning | Enabled | Rollback to any previous state version |

#### Stale Lock Detection

A CloudWatch alarm monitors DynamoDB `ConditionalCheckFailedRequests`:

- Metric: `ConditionalCheckFailedRequests` (Sum, 5-minute periods)
- Threshold: > 50 over 3 evaluation periods
- Action: SNS DR topic notification
- Purpose: Detect lock contention indicating a possible stale lock

#### State Backup Automation

A CronJob runs nightly at 02:00 JST in the `city-services` namespace:

- Copies state files for dev, staging, and production to `agora-prod-backups/terraform-state-backups/`
- Checks for active DynamoDB locks and warns if found
- Emits `Agora/DR` custom CloudWatch metric `BackupAgeSeconds` (reset to 0 on success)
- Uses IRSA role `agora-dr-backup-role` for least-privilege S3 access

### 11.2 Multi-AZ Tolerance

| Layer | Single AZ Loss | Two AZ Loss |
|-------|---------------|-------------|
| MSK Express | Degraded (2/3 replicas); auto-recovery | Cluster unavailable; restore from S3 |
| Aurora | Failover to reader in surviving AZ (<30s) | Cluster unavailable; restore from snapshot |
| EKS | Pods reschedule (PDB allows 1 AZ loss) | etcd quorum may break; cluster recovery |
| S3 | No impact (region-redundant) | No impact |

### 11.2 Recovery Objectives

| Metric | Target | Critical Path |
|--------|--------|---------------|
| RPO | 5 minutes | Kafka retention + S3 archive |
| RTO | 15 minutes | Aurora failover + EKS pod recovery |
| Availability | 99.95% | ~4.38 hours/year total |

### 11.3 Backup Strategy

| Data | Method | Frequency | RPO |
|------|--------|-----------|-----|
| Kafka topics | S3 sink connector | Continuous (10K msgs or 1 hour) | < 1 hour |
| Aurora | Automated snapshots + WAL | Daily + continuous | < 5 min |
| Aurora (export) | Export to S3 | Daily | < 24 hours |
| S3 data lake | Versioning + lifecycle | Automatic | Instant (versioning) |
| Terraform state | S3 versioning | Auto (every apply) | Instant |

---

## 12. Istio Service Mesh

Istio provides a service mesh layer that enforces zero-trust networking across all pod-to-pod communication. It layers on top of existing Kubernetes NetworkPolicy for defense-in-depth.

### 12.1 Two-Namespace Model

Istio resources are scoped to the same two workload namespaces as the platform:

| Namespace | PeerAuthentication | AuthorizationPolicy | Sidecar |
|-----------|-------------------|-------------------|---------|
| `city-services` | STRICT mTLS | deny-all + per-service allow rules | REGISTRY_ONLY, egress to city-services/ monitoring/ istio-system |
| `inventors` | STRICT mTLS | No namespace-wide policy (default deny) | REGISTRY_ONLY, egress only to api-gateway and istio-system |
| `istio-system` | PERMISSIVE | N/A | N/A |

A mesh-wide default PeerAuthentication in `istio-system` is set to PERMISSIVE to allow ingress gateways and control plane components to accept non-mTLS traffic.

### 12.2 PeerAuthentication — STRICT mTLS

```yaml
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: default
  namespace: city-services
spec:
  mtls:
    mode: STRICT
```

Both `city-services` and `inventors` namespaces enforce STRICT mTLS. Every pod-to-pod connection uses mutual TLS with SPIFFE identities. Connections without a valid client certificate are rejected at the Envoy proxy level — before the application sees the request.

### 12.3 AuthorizationPolicy — Deny-by-Default with Per-Service Allow Rules

A global deny-all policy blocks all traffic in `city-services`:

```yaml
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: deny-all
  namespace: city-services
spec: {}
```

Per-service allow policies then selectively open traffic:

| Service | Allowed Sources | Allowed Operations |
|---------|----------------|-------------------|
| `traffic-optimizer` | city-services/default SA, monitoring/prometheus-sa | GET/POST `/api/*`, `/metrics` |
| `data-broker` | energy-management SA, traffic-optimizer SA, monitoring/prometheus-sa | GET/POST `/api/*`, `/metrics` |
| `api-gateway` | inventors namespace, city-services namespace | GET/POST `/v1/public/*` |

### 12.4 Sidecar — Restricting Inventor Mesh Visibility

The `inventor-restricted` Sidecar resource limits what inventor pods can discover and reach:

```yaml
apiVersion: networking.istio.io/v1beta1
kind: Sidecar
metadata:
  name: inventor-restricted
  namespace: inventors
spec:
  outboundTrafficPolicy:
    mode: REGISTRY_ONLY
  egress:
    - hosts:
        - "city-services/api-gateway.city-services.svc.cluster.local"
        - "istio-system/*"
```

Inventor pods can only egress to the API gateway and Istio control plane. They cannot discover or connect to MSK, Aurora, monitoring services, or other city-services pods directly. The `city-service-internal` Sidecar in `city-services` allows egress within the namespace plus monitoring and Istio system components.

### 12.5 RequestAuthentication — JWT at Mesh Edge

```yaml
apiVersion: security.istio.io/v1beta1
kind: RequestAuthentication
metadata:
  name: require-jwt
  namespace: city-services
spec:
  jwtRules:
    - issuer: "https://idp.agora.woven-city.internal"
      jwksUri: "https://idp.agora.woven-city.internal/.well-known/jwks.json"
```

Each namespace has its own JWT issuer:

| Namespace | Issuer | Audience |
|-----------|--------|----------|
| `city-services` | `https://idp.agora.woven-city.internal` | Internal service identities |
| `inventors` | `https://auth.agora.woven-city.global` | External inventor identities |

RequestAuthentication validates JWT tokens at the Envoy proxy before forwarding to the application. Invalid or missing tokens are rejected.

### 12.6 MeshConfig — REGISTRY_ONLY Outbound

The mesh ConfigMap enforces that all outbound traffic must go to services registered in the Istio service registry:

```yaml
outboundTrafficPolicy:
  mode: REGISTRY_ONLY
```

This prevents pods from making direct outbound connections to arbitrary IPs. All external traffic must route through defined Egress Gateways or Service Entries. Combined with the Sidecar egress rules, this provides three layers of egress control: MeshConfig (cluster-wide), Sidecar (per-namespace), and NetworkPolicy (Kubernetes-level).

### 12.7 Telemetry and Tracing

| Feature | Configuration |
|---------|---------------|
| Tracing | Zipkin provider, 100% random sampling |
| Access logging | JSON format to stdout |
| city-services logging | All requests (mode: ANY) |
| inventors logging | Only errors (response code >= 400) |

The mesh-level Telemetry resource enables Zipkin-compatible tracing with 100% sampling for all services. A separate Telemetry resource in `city-services` enables detailed access logging for all requests. The `inventors` namespace logs only errors to reduce noise.

### 12.8 Defense-in-Depth Layering

Istio adds a third layer of security on top of existing controls:

| Layer | Scope | Mechanism |
|-------|-------|-----------|
| VPC Security Groups | Network boundary | AWS-managed, per-AZ |
| Kubernetes NetworkPolicy | Namespace isolation | Default-deny, allow-list |
| Istio mTLS + Authz | Pod-to-pod identity | SPIFFE, JWT, STRICT mTLS |
| IAM (IRSA) | AWS API access | ServiceAccount-bound roles |
| RBAC | K8s API access | Role/ClusterRole bindings |

The Istio layer is identity-aware (SPIFFE), not just network-aware. Even if a NetworkPolicy is misconfigured to allow traffic, Istio will still reject it if the source identity is not authorized.

---

## 13. Architecture Decision Records

### ADR-1: MSK Express over Provisioned Standard

**Context**: Need high-throughput Kafka for 60K events/sec with minimal operational overhead.

**Decision**: Use MSK Express for staging/prod, MSK Serverless for dev.

**Rationale**: Express delivers 3x throughput per broker, 20x faster scaling, 90% faster recovery, and auto-scaling storage — eliminating the hardest Kafka ops problems.

### ADR-2: Aurora PostgreSQL over Standard RDS

**Context**: Database must survive AZ failures with minimal downtime and zero data loss.

**Decision**: Use Aurora PostgreSQL with Multi-AZ and reader replicas.

**Rationale**: Aurora failover is ~30 seconds vs ~120 seconds for standard RDS. Storage auto-scales to 128 TB. Read replicas offload read traffic.

### ADR-3: IAM Access Control over TLS/mTLS

**Context**: Kafka authentication should not require managing certificates or passwords.

**Decision**: Use MSK IAM Access Control on port 9098 with IRSA.

**Rationale**: Each pod inherits Kafka permissions from its Kubernetes ServiceAccount. No secrets to manage, rotate, or leak. Native AWS SDK integration.

### ADR-4: CloudWatch + Prometheus Split

**Context**: AWS infrastructure monitoring and application-level monitoring have different concerns.

**Decision**: Terraform manages CloudWatch (infra alarms, dashboards). Prometheus/Grafana deployed in K8s (Phase 2).

**Rationale**: Clean separation of concerns. CloudWatch handles AWS-managed services (MSK, Aurora, ALB). Prometheus handles application metrics where AWS can't reach.

### ADR-5: Single KMS CMK per Environment

**Context**: All services need encryption at rest. Multiple keys add complexity.

**Decision**: One KMS CMK per environment, used by all services in that environment.

**Rationale**: Simplified key management. Cross-service audit trail (CloudTrail logs all decrypt calls). Reduced AWS costs ($1/month per CMK).

### ADR-6: 3-AZ Minimum for Production

**Context**: MSK Express requires 3 AZs. Multi-AZ is Woven City's requirement for availability.

**Decision**: Deploy all production infrastructure across 3 AZs.

**Rationale**: MSK Express mandates 3 AZs. Aurora Multi-AZ needs at least 2. EKS control plane is multi-AZ by default. 3 AZs tolerance exceeds 99.95% requirement.
