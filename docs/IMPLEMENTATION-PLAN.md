# Implementation Plan — Agora Platform

> **Phase-by-phase build plan for the Woven City Agora real-time event processing platform infrastructure**
> **Timeline**: 7 days (Phase 1: 2-3 days, Phase 2: 2 days, Phase 3: 2 days)
> **Last Updated**: May 2026

---

## Table of Contents

1. [Phase Overview](#1-phase-overview)
2. [Phase 1: Terraform IaC (Days 1-3)](#2-phase-1-terraform-iac-days-1-3)
3. [Phase 2: Kubernetes Components (Days 4-5)](#3-phase-2-kubernetes-components-days-4-5)
4. [Phase 3: Data Pipeline (Days 6-7)](#4-phase-3-data-pipeline-days-6-7)
5. [Phase 4: CI/CD & Automation (Future)](#5-phase-4-cicd--automation-future)
6. [Phase 5: Cross-Region DR (Future)](#6-phase-5-cross-region-dr-future)
7. [Dependency Map](#7-dependency-map)
8. [Risk Register](#8-risk-register)
9. [Testing Strategy](#9-testing-strategy)

---

## 1. Phase Overview

```
Phase 1: Terraform IaC ───────────────────────────────┐
  Days 1-3: 7 modules, 3 environments, bootstrap       │
                                                       │
Phase 2: Kubernetes ───────────────────────────────────┤
  Days 4-5: Multi-tenancy, 4 services, monitoring      │  All Phases
                                                       │  are complete
Phase 3: Data Pipeline ────────────────────────────────┤
  Days 6-7: Topics, processors, Connect, DLQ, IAM      │
                                                       │
Phase 4: CI/CD (Future)                                │  READY
  GitHub Actions, Atlantis, ArgoCD                     │
                                                       │
Phase 5: Cross-Region DR (Future)                      │
  Aurora Global, MSK Mirror, ArgoCD Multi-Cluster      │
└──────────────────────────────────────────────────────┘
```

---

## 2. Phase 1: Terraform IaC (Days 1-3)

### Goal

Build production-ready, modular Terraform infrastructure framework for Agora's AWS foundation.

### Deliverables

| Day | Module | Key Components |
|-----|--------|---------------|
| 1 | Bootstrap + VPC + IAM | S3 backend, DynamoDB lock, VPC with 3 AZs, IAM base roles |
| 2 | EKS + MSK | EKS cluster with Karpenter, MSK Express + Serverless |
| 3 | RDS + S3 + Monitoring | Aurora PostgreSQL, 4 S3 buckets, CloudWatch + AMP |

### Module Details

#### Day 1 — Foundation

**Bootstrap module:**
- S3 bucket for Terraform state (`agora-terraform-state`)
- DynamoDB table for state locking (`terraform-lock`)
- KMS CMK for state bucket encryption

**VPC module:**
- VPC with configurable CIDR (10.x.0.0/16)
- 3 AZs: public / private / database subnets
- Internet Gateway + NAT Gateways (1 in dev, 2 in staging, 3 in prod)
- Route tables + associations
- VPC endpoints: S3 (Gateway), ECR API/DKR, Secrets Manager, CloudWatch, AMP

**IAM module:**
- EKS cluster role (AmazonEKSClusterPolicy)
- EKS node role (AmazonEKSWorkerNodePolicy, AmazonEKS_CNI_Policy, AmazonEC2ContainerRegistryReadOnly)
- Karpenter node role
- IRSA OIDC provider
- Base service roles with least-privilege policies

#### Day 2 — Compute + Streaming

**EKS module:**
- EKS cluster (Kubernetes 1.28)
- Karpenter provisioner (m7g.xlarge, 5-30 nodes in prod)
- Node security group (control plane + node access)
- Cluster addons: vpc-cni, kube-proxy, coredns, ebs-csi-driver
- Logging: audit, api, authenticator, controllerManager, scheduler
- OIDC provider for IRSA

**MSK module:**
- Conditional resource creation: Express vs Serverless
- Express: 3 brokers, m7g.large/xlarge, Kafka 3.6, auto-scaling storage
- Serverless: pay-per-use, no cluster management
- IAM Access Control (port 9098)
- Encryption: TLS in-transit + KMS at-rest
- Enhanced monitoring: PER_TOPIC_PER_PARTITION
- CloudWatch log delivery (broker logs, consumer lag)
- Custom config: `auto.create.topics.enable = false`

#### Day 3 — Storage + Monitoring

**RDS (Aurora PostgreSQL) module:**
- DB cluster + instance(s): Aurora Serverless v2 (dev), provisioned (staging/prod)
- Reader replicas: 0/1/2 for dev/staging/prod
- DB subnet group (dedicated database subnets)
- Security group (EKS node SG only)
- Parameter group: connection pooling, statement timeout
- Secrets Manager integration (auto-rotate credentials)
- Performance Insights (7 days retention)
- Backup: automated daily + WAL continuous archiving
- Deletion protection (staging/prod)

**S3 module:**
- 4 buckets: data-lake, app-logs, access-logs, backups
- KMS encryption (SSE-KMS)
- Versioning enabled
- Block public access (account + bucket)
- Lifecycle policies (data lake: 30d → IA → Glacier 90d → delete 7yr)
- Bucket policies: enforce TLS 1.3, deny HTTP, require KMS

**Monitoring module:**
- CloudWatch dashboards (EKS, MSK, Aurora, ALB, VPC)
- SNS topics: critical (PagerDuty), warning (Slack), info (log)
- Composite alarms: SLO-based (latency > 100ms AND error rate > 0.1%)
- AMP workspace for Prometheus metrics
- Log group encryption (KMS)

### Environment Configuration

```hcl
# dev/terraform.tfvars
msk_broker_type       = "serverless"
rds_instance_class    = "db.serverless"
rds_min_capacity      = 0.5
rds_max_capacity      = 2
node_instance_types   = ["t3.large"]
desired_node_count    = 2
min_node_count        = 1
max_node_count        = 5
availability_zones    = ["ap-northeast-1a", "ap-northeast-1c"]

# staging/terraform.tfvars
msk_broker_type       = "express"
msk_broker_count      = 3
msk_instance_type     = "express.m7g.large"
rds_instance_class    = "db.r5.large"
rds_reader_count      = 1
node_instance_types   = ["m7g.xlarge"]
desired_node_count    = 4
min_node_count        = 3
max_node_count        = 12
availability_zones    = ["ap-northeast-1a", "ap-northeast-1c", "ap-northeast-1d"]

# production/terraform.tfvars
msk_broker_type       = "express"
msk_broker_count      = 3
msk_instance_type     = "express.m7g.xlarge"
rds_instance_class    = "db.r6g.xlarge"
rds_reader_count      = 2
node_instance_types   = ["m7g.xlarge", "m7g.2xlarge"]
desired_node_count    = 8
min_node_count        = 5
max_node_count        = 30
availability_zones    = ["ap-northeast-1a", "ap-northeast-1c", "ap-northeast-1d"]
```

### Validation

```bash
# Local validation (no AWS credentials needed)
terraform init -backend=false
terraform validate
terraform fmt -recursive

# Plan (read-only, no changes)
terraform plan -out=tfplan
terraform show tfplan

# Cost estimation
infracost breakdown --path .
```

---

## 3. Phase 2: Kubernetes Components (Days 4-5)

### Goal

Build production-ready Kubernetes manifests for multi-tenant, multi-service Agora platform.

### Deliverables

| Day | Component | Resources |
|-----|-----------|-----------|
| 4 | Foundation + Security | Namespaces, RBAC, NetworkPolicies, ResourceQuotas, PSP |
| 4 | Core services | traffic-optimizer, energy-management, data-broker, api-gateway |
| 5 | Observability + Scaling | Prometheus, Grafana, HPA, PDB, Kustomize, scripts |

### Day 4 — Foundation + Services

**Namespaces:**
```yaml
- city-services:    # Internal city operations, privileged
- inventors:        # External partners, restricted
- monitoring:       # Observability stack, can scrape all namespaces
```

**RBAC:**
```yaml
city-services-role:
  - apps: [deployments, statefulsets] → get/list/watch
  - core: [pods, services] → get/list/watch
  - core: [configmaps, secrets] → get/list
  - core: [pods/exec, pods/log] → get/create

inventors-role:
  - [all] → get/list/watch only (read-only)
  - Cannot: create, update, delete, exec, write
```

**Network Policies:**
```yaml
default-deny-all:        # Applied first — implicit deny
  - Ingress: deny all
  - Egress: deny all

city-services-allow:
  - Ingress: monitoring (port 8080), intra-namespace
  - Egress: DNS (kube-system UDP 53), MSK (VPC CIDR TCP 9098), intra-namespace

inventors-allow:
  - Ingress: api-gateway.city-services only (port 8080)
  - Egress: DNS only
```

**Resource Quotas:**
```yaml
city-services:   {cpu: 20/30, memory: 40Gi/60Gi, pods: 100, storage: 500Gi}
inventors:       {cpu: 5/10, memory: 10Gi/20Gi, pods: 20, storage: 100Gi}
```

**Core Services:**

Each service includes:
- `configmap.yaml` — Kafka bootstrap (port 9098), topic names, tuning parameters
- `secret.yaml` — Application-level API keys (NO Kafka credentials — IAM handles auth)
- `deployment.yaml` — Replicas, health probes, resource limits, security context, podAntiAffinity
- `service.yaml` — ClusterIP, port definitions
- `hpa.yaml` — CPU (70%), memory (80%), consumer lag (500)
- `pdb.yaml` — minAvailable (2 of 3 for critical services)
- `servicemonitor.yaml` — Prometheus scrape config

| Service | Replicas | CPU | Memory | Key Config |
|---------|----------|-----|--------|------------|
| traffic-optimizer | 3 | 500m → 1 | 512Mi → 1Gi | Kafka: vehicle.telemetry → signal.commands |
| energy-management | 2 | 500m → 1 | 512Mi → 1Gi | Kafka: sensor.environmental |
| data-broker | 5 | 2 → 4 | 2Gi → 4Gi | Kafka: all raw topics → anonymized |
| api-gateway | 5 | 500m → 1 | 512Mi → 1Gi | External ingress, rate limiting |

### Day 5 — Observability + Automation

**Prometheus:**
- ServiceAccount + ClusterRole + binding (full cluster metrics access)
- ConfigMap: scrape config (kubernetes_sd_configs for all namespaces)
- Alert rules: latency SLO, error rate, pod health, memory usage
- Deployment: 2 replicas, 90-day retention
- Service: ClusterIP port 9090

**Grafana:**
- ConfigMap: Prometheus datasource (auto-provisioned)
- Dashboards: Traffic Optimizer, Energy Management, System Health
- Deployment: 2 replicas, admin password from Secret
- Service: ClusterIP port 3000

**Kustomize Overlays:**
```yaml
base/:
  - All namespaces, RBAC, network policies, quotas
  - All services, HPAs, PDBs

overlays/development/:
  - Replicas: traffic-optimizer=2, energy=1, data-broker=2
  - Resource requests: lower (50%)
  - Ingress: disabled (port-forward only)

overlays/staging/:
  - Replicas: traffic-optimizer=3, energy=2, data-broker=3
  - Resource requests: 75% of prod
  - Ingress: enabled (internal ALB)

overlays/production/:
  - Replicas: traffic-optimizer=5, energy=3, data-broker=5
  - Resource requests: 100%
  - Ingress: enabled (external ALB, WAF)
  - podAntiAffinity: requiredDuringScheduling (strict)
```

**Validation:**
```bash
# Syntax check
kubectl apply -f kubernetes/ --dry-run=client

# Kustomize build
kustomize build kustomization/overlays/production > /tmp/prod-manifests.yaml
kubectl apply -f /tmp/prod-manifests.yaml --dry-run=client

# RBAC validation
kubectl auth can-i list pods --as=system:serviceaccount:inventors:default -n city-services
# Expected: no
```

---

## 4. Phase 3: Data Pipeline (Days 6-7)

### Goal

Build end-to-end data pipeline: device telemetry → MSK → stream processing → S3 archival + output topics.

### Deliverables

| Day | Component | Resources |
|-----|-----------|-----------|
| 6 | Kafka + Schema + Connect | Topic definitions, AVRO schemas, Schema Registry, Kafka Connect (S3 sink) |
| 6 | IAM auth | IRSA roles for 6 services, service accounts |
| 7 | Stream processors | 4 processors: traffic, anomaly, energy, data-broker |
| 7 | DLQ + Monitoring + Scripts | DLQ processor, Prometheus rules, Grafana dashboards, test scripts |

### Day 6 — Foundation + Streaming Infrastructure

**Topic Definitions:**

| Topic | Partitions | Config | Schema |
|-------|-----------|--------|--------|
| vehicle.telemetry | 12 | delete+compact, 7d, snappy | AVRO: GPS, speed, accel, vehicle_type |
| sensor.environmental | 6 | delete, 7d, snappy | AVRO: temp, humidity, PM2.5, CO2 |
| signal.events | 6 | delete, 7d, snappy | AVRO: intersection_id, queue, state |
| incidents | 1 | delete, 30d | AVRO: vehicle_id, score, type, action |

Output topics:
| Topic | Partitions | Config | Schema |
|-------|-----------|--------|--------|
| signal.commands | 6 | delete, 2d | AVRO: intersection_id, command, duration |
| data.anonymized.vehicle | 12 | delete, 30d | AVRO: grid_location, avg_speed, count |
| data.inventor.traffic | 3 | delete, 7d | AVRO: anonymous traffic per sector |
| alerts.notifications | 1 | delete+compact, 90d | AVRO: severity, source, message |
| dlq.all | 1 | delete, 30d | AVRO: original_msg, error, source |

**Schema Registry:**
- StatefulSet (2 replicas) on EKS
- Confluent Schema Registry image
- Compatibility: BACKWARD (default), FORWARD_TRANSITIVE (incidents), NONE (dlq)
- Service: ClusterIP port 8081
- PDB: minAvailable 1
- HPA: CPU 70%, request latency > 500ms

**Kafka Connect S3 Sink:**
- Deployment: 3 workers (distributed mode)
- 4 connectors: vehicle.telemetry, sensor.environmental, signal.events, incidents
- Format: AVRO (self-describing)
- Flush: 10K messages or 1 hour
- S3 prefix: `raw/{topic}/year=YYYY/month=MM/day=dd/hour=HH/`
- Partitioner: DefaultPartitioner (topic+partition+offset)

**IAM Auth (IRSA):**

| Service | IAM Role | Kafka Permissions |
|---------|----------|-------------------|
| traffic-optimizer | TrafficOptimizerMSKRole | Read: vehicle.telemetry, signal.events; Write: signal.commands, incidents |
| anomaly-detector | AnomalyDetectorMSKRole | Read: vehicle.telemetry; Write: incidents, alerts |
| energy-optimizer | EnergyOptimizerMSKRole | Read: sensor.environmental; Write: alerts |
| data-broker | DataBrokerMSKRole | Read: all raw; Write: data.anonymized.vehicle, data.inventor.traffic |
| kafka-connect | KafkaConnectMSKRole | Read: all raw; Write: S3 (via endpoint) |
| schema-registry | SchemaRegistryMSKRole | Read: _schemas; Write: _schemas |

### Day 7 — Processing + Quality + Testing

**Stream Processors:**

| Processor | Language | Resource | Replicas (min→max) | Key Logic |
|-----------|----------|----------|---------------------|-----------|
| traffic-optimizer | Python | 1 CPU, 2GB | 3→10 | 5s sliding window per intersection, queue thresholds |
| anomaly-detector | Python | 2 CPU, 4GB | 2→8 | ML model inference (pre-trained), feature extraction |
| energy-optimizer | Python | 500m CPU, 1GB | 2→6 | Weather + consumption cross-reference, peak shifting |
| data-broker | Python | 2 CPU, 4GB | 5→20 | PII strip, GPS round, per-inventor ACL |

Each processor includes:
- `processor.py` — Main Kafka Streams / consumer logic
- `Dockerfile` — Multi-stage build for small image size
- `deployment.yaml` — K8s Deployment with IRSA service account
- `configmap.yaml` — Topic names, window sizes, thresholds
- `hpa.yaml` — CPU 70% + consumer lag 500 trigger
- `pdb.yaml` — minAvailable (2 for critical, 1 for others)
- `servicemonitor.yaml` — Prometheus metrics

**Data Broker Transformations:**

```
1. Anonymizer:
   - Strip: vehicle_id, driver_id, payment_info, home_location
   - Round: GPS to 100m grid (35.123 → 35.12)
   - Replace: exact speed → speed band (0-20, 20-40, 40-60, 60+)

2. Aggregator:
   - 10-second tumbling window per district
   - Output: avg_speed, vehicle_count, congestion_level

3. Access Control:
   - City planners: full aggregated data
   - Inventor traffic app: sector-level averages only
   - Reject: any request without valid IAM credentials
```

**Dead Letter Queue:**
- Topic: `dlq.all` (1 partition, 30 day retention)
- DLQ processor reads and classifies failures:
  - Schema violation → notify team
  - Deserialization error → log + alert (data corruption)
  - Transient error → retry 3x
  - Poison pill → log + alert

**Pipeline Monitoring:**
- Prometheus rules:
  - `ConsumerLagHigh`: lag > 1000 for 5 min (Critical)
  - `TrafficOptimizerLatencyBreach`: P99 > 100ms for 5 min (Critical)
  - `DeadLetterQueueAccumulating`: > 1000 unprocessed for 5 min (Warning)
- Grafana dashboard: Pipeline view with consumer lag, throughput, error rate, latency

**End-to-End Test Script:**
```bash
scripts/test-end-to-end.sh
# 1. Seed 1000 test vehicle events to vehicle.telemetry
# 2. Wait 10s for processing
# 3. Verify signal.commands has commands
# 4. Verify incidents has no false positives
# 5. Verify S3 data lake has archive
# 6. Verify data.anonymized.vehicle has PII stripped
# 7. Verify consumer lag < 100
# 8. Clean up test data
```

**Performance verification:**
| Scenario | Expected | Method |
|----------|----------|--------|
| 10K msg/sec to vehicle.telemetry | < 100ms P99 latency | kafka-producer-perf-test |
| Consumer group with 12 consumers | Balanced partition assignment | kafka-consumer-groups |
| Aurora read replicas | < 1s replication lag | CloudWatch metric |
| S3 archive throughput | > 10 MBps sustained | CloudWatch S3 metrics |

---

## 5. Phase 4: CI/CD & Automation (Future)

### CI/CD Pipeline

```
Developer commits code
  ↓
GitHub Actions / GitLab CI
  ↓
Terraform Validation
  - fmt, validate, tflint, tfsec, checkov
  - Plan output saved as artifact
  ↓
Approval Gate (production)
  ↓
Terraform Apply
  - Terraform Cloud / Atlantis
  - Auto-approve for dev/staging
  - Manual approval for production
  ↓
Post-Apply
  - Run end-to-end tests
  - Update configuration repository
  - Notify Slack
```

### GitOps (ArgoCD)

```
Git Repository (source of truth)
  ↓ (sync)
ArgoCD
  ↓
EKS Cluster
  ↓
Health checks + Sync status
  ↓
Rollback (if degraded)
```

---

## 6. Phase 5: Cross-Region DR (Future)

### Architecture

```
Primary (ap-northeast-1)          DR (ap-southeast-1)
┌────────────────────┐           ┌────────────────────┐
│ Aurora Writer + 2R │──Global──→│ Aurora Read Replica│
│ MSK Express 3×m7g  │──Mirror──→│ MSK DR Cluster     │
│ S3 Data Lake       │──CRR─────→│ S3 DR Bucket       │
│ EKS Prod Cluster   │──ArgoCD──→│ EKS DR Cluster     │
└────────────────────┘           └────────────────────┘
```

### Implementation Steps

1. Deploy Aurora Global Database (RPO ~1s)
2. Configure MSK Replicator (MirrorMaker 2.0)
3. Enable S3 Cross-Region Replication (CRR)
4. Deploy ArgoCD with multi-cluster configuration
5. Create DR promotion runbook
6. Test: bi-annual full DR drill

---

## 7. Dependency Map

```
Phase 1: Terraform IaC
├── VPC (foundation — everything depends on network)
├── IAM (foundation — roles needed by EKS, MSK, Aurora)
├── EKS (depends on: VPC, IAM)
├── MSK (depends on: VPC, IAM)
├── RDS (depends on: VPC, IAM)
├── S3 (independent)
└── Monitoring (depends on: VPC, IAM)

Phase 2: Kubernetes
├── Namespaces (independent)
├── RBAC (independent)
├── Network Policies (depends on: namespaces)
├── Resource Quotas (depends on: namespaces)
├── Core Services (depends on: namespaces, RBAC, Phase 1 MSK)
├── Prometheus + Grafana (depends on: namespaces)
├── HPA + PDB (depends on: core services)
└── Kustomize (depends on: all resources)

Phase 3: Data Pipeline
├── Kafka Topics (depends on: Phase 1 MSK)
├── Schema Registry (depends on: Phase 2 EKS+namespaces)
├── Kafka Connect (depends on: Phase 1 MSK+S3, Phase 2 EKS)
├── Stream Processors (depends on: Phase 1 MSK, Phase 2 EKS)
├── IAM Auth (depends on: Phase 1 IAM)
├── DLQ (depends on: Phase 1 MSK)
└── Monitoring (depends on: Phase 2 Prometheus)
```

**Critical path:** VPC → EKS+MSK+Aurora → Namespaces → Services → Stream Processors

---

## 8. Risk Register

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| MSK Express not available in ap-northeast-1 | Low | High | Fallback to MSK Provisioned with auto-scaling |
| Kafka partition count exceeds broker limit | Low | Medium | Monitor partition count; scale brokers preemptively |
| Aurora storage auto-scaling exceeds budget | Medium | Low | Set maximum storage limit; monitor billing alerts |
| Karpenter EC2 instance limit hit | Low | High | Request limit increase before prod launch |
| Schema compatibility breaks consumers | Medium | High | BACKWARD default; test schema changes in staging |
| Inventor consumes more than allocated quota | Medium | Medium | ResourceQuota enforcement; enhanced monitoring |
| AZ-specific capacity constraints | Low | Medium | Use 3 AZs; any single AZ failure is survivable |
| VPC CIDR exhaustion | Low | High | /16 CIDR (65536 IPs) sufficient for planned scale |

---

## 9. Testing Strategy

### Pre-Deployment Validation

```bash
# Phase 1
terraform init -backend=false && terraform validate
terraform plan -out=tfplan
infracost breakdown --path .

# Phase 2
kubectl apply -f kubernetes/ --dry-run=client
kustomize build kustomization/overlays/production | kubectl apply --dry-run=client -f -

# Phase 3
python -m pytest stream-processors/traffic-optimizer/tests/
python -m pytest stream-processors/data-broker/tests/
```

### Post-Deployment Verification

| Test | Command | Expected |
|------|---------|----------|
| EKS cluster health | `aws eks describe-cluster --name agora-prod` | Status: ACTIVE |
| MSK cluster health | `aws kafka describe-cluster --cluster-arn $ARN` | State: ACTIVE |
| Topic creation | `kafka-topics --list --bootstrap-server b-1:9098` | 8 topics |
| Schema registration | `curl schema-registry:8081/subjects` | 9 subjects |
| Kafka Connect | `curl kafka-connect:8083/connectors` | 4 connectors |
| Producer test | `kafka-producer-perf-test --topic vehicle.telemetry --num-records 10000` | Throughput, latency |
| Consumer test | `kafka-consumer-perf-test --topic vehicle.telemetry --messages 10000` | Throughput |
| End-to-end | `scripts/test-end-to-end.sh` | All assertions pass |
