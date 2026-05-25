# Agora Platform Documentation

> **Central documentation hub for Woven City's Agora platform — the operating system for Toyota's smart city at the base of Mount Fuji.**
> **Last Updated**: May 2026

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Quick Start](#quick-start)
3. [Documentation Map](#documentation-map)
4. [Phase 1: Infrastructure (Terraform IaC)](#phase-1-infrastructure-terraform-iac)
5. [Phase 2: Kubernetes Components](#phase-2-kubernetes-components)
6. [Phase 3: Data Pipeline](#phase-3-data-pipeline)
7. [Operations & Security](#operations--security)
8. [API Reference](#api-reference)
9. [Diagrams](#diagrams)
10. [Glossary](#glossary)

---

## Architecture Overview

Agora is a six-layer, multi-tenant event processing platform that ingests 60,000+ real-time events/second from 10,000+ IoT devices across Woven City. Built on AWS in the `ap-northeast-1` region, it spans 3 Availability Zones and uses Amazon MSK Express for event streaming, EKS with Karpenter for compute, Aurora PostgreSQL for relational storage, and S3 for the data lake. The platform enforces multi-tenant isolation between internal city services (traffic optimization, energy management, anomaly detection) and an external inventor ecosystem, with IAM-based authentication (IRSA), mTLS for device ingress, and a data broker layer that strips PII before multi-tenant distribution. Recovery objectives are RPO 5 minutes and RTO 15 minutes, targeting 99.95% availability.

---

## Quick Start

### Prerequisites

| Tool | Version | Purpose |
|------|---------|---------|
| Terraform | >= 1.0 | Infrastructure provisioning |
| AWS CLI | >= 2.0 | AWS API interactions |
| kubectl | >= 1.28 | Kubernetes management |
| kustomize | >= 5.0 | K8s manifest overlays |
| Python | >= 3.11 | Stream processors |
| Docker | >= 24.0 | Container builds |
| Java | >= 11 | Kafka CLI tools |

### Deploy in 3 Phases

```bash
# === Phase 1: Infrastructure ===
cd terraform/bootstrap && terraform init && terraform apply    # One-time state backend
cd terraform/environments/dev && terraform init && terraform apply
aws eks update-kubeconfig --name agora-dev --region ap-northeast-1

# === Phase 2: Kubernetes ===
kubectl apply -k kustomization/overlays/dev

# === Phase 3: Data Pipeline ===
kafka-topics/apply-topics.sh
scripts/deploy-pipeline.sh
```

### Verify

```bash
make verify ENV=dev
```

---

## Documentation Map

| Document | Location | Description |
|----------|----------|-------------|
| **Architecture** | [`docs/ARCHITECTURE.md`](ARCHITECTURE.md) | Full technical architecture — 6-layer stack, network, compute, streaming, storage, DR |
| **Getting Started** | [`docs/GETTING_STARTED.md`](GETTING_STARTED.md) | Project setup, prerequisites, first deployment walkthrough |
| **Deployment Guide** | [`docs/DEPLOYMENT_GUIDE.md`](DEPLOYMENT_GUIDE.md) | Step-by-step deployment across dev/staging/production |
| **Security Architecture** | [`docs/SECURITY.md`](SECURITY.md) | Threat model, IAM, encryption, K8s security, audit, data protection |
| **Operations Runbook** | [`docs/OPERATIONS_RUNBOOK.md`](OPERATIONS_RUNBOOK.md) | Daily ops, incident response, escalation, post-mortem |
| **Operations Guide** | [`docs/OPERATIONS.md`](OPERATIONS.md) | Monitoring, capacity management, backup verification, maintenance, cost monitoring |
| **Scaling Strategy** | [`docs/SCALING.md`](SCALING.md) | Three-axis scaling — MSK, Aurora, EKS, HPA, partition expansion, cost-aware scaling |
| **Disaster Recovery** | [`docs/DISASTER-RECOVERY.md`](DISASTER-RECOVERY.md) | DR architecture, backup strategy, failover, recovery runbooks, DR testing |
| **Terraform State Lock** | [`docs/terraform-state-lock.md`](terraform-state-lock.md) | DynamoDB lock table design, stale lock detection, force-unlock procedure, hardening |
| **Istio Service Mesh** | [`docs/istio-service-mesh.md`](istio-service-mesh.md) | Zero-trust service mesh: mTLS, authorization, sidecar egress, JWT, telemetry |
| **Troubleshooting** | [`docs/TROUBLESHOOTING.md`](TROUBLESHOOTING.md) | Diagnostic procedures by layer — MSK, Aurora, EKS, processors, Connect, Schema Registry |
| **Glossary** | [`docs/GLOSSARY.md`](GLOSSARY.md) | Definitions for all platform terms and acronyms |
| **API Reference** | [`docs/api/README.md`](api/README.md) | API documentation index and OpenAPI spec reference |
| **OpenAPI Spec** | [`docs/api/agora-platform-openapi.yaml`](api/agora-platform-openapi.yaml) | Complete OpenAPI 3.0 specification |
| **Diagram Index** | [`docs/diagrams/README.md`](diagrams/README.md) | Architecture diagram index and descriptions |

---

## Phase 1: Infrastructure (Terraform IaC)

> Repository: `agora-infrastructure/`

### Terraform Module Structure

| Module | Description | Key Docs |
|--------|-------------|----------|
| `vpc/` | Network foundation — 3 AZs, public/private/database subnets, NAT Gateways, VPC Endpoints | [`ARCHITECTURE.md §2`](ARCHITECTURE.md#2-network-architecture-vpc) |
| `eks/` | EKS cluster — Karpenter, IRSA, OIDC, addons | [`ARCHITECTURE.md §3`](ARCHITECTURE.md#3-compute-architecture-eks) |
| `msk/` | MSK Express/Serverless — Kafka event streaming | [`ARCHITECTURE.md §4`](ARCHITECTURE.md#4-event-streaming-msk-kafka) |
| `rds/` | Aurora PostgreSQL — Multi-AZ, replicas, Secrets Manager | [`ARCHITECTURE.md §5`](ARCHITECTURE.md#5-database-architecture-aurora-postgresql) |
| `s3/` | Data lake — 4 buckets, lifecycle, versioning, SSE-KMS | [`ARCHITECTURE.md §6`](ARCHITECTURE.md#6-storage-architecture-s3) |
| `monitoring/` | CloudWatch dashboards, SNS, composite alarms, AMP | [`ARCHITECTURE.md §9`](ARCHITECTURE.md#9-observability-architecture) |
| `iam/` | IRSA roles, service-linked roles, KMS key, OIDC provider | [`ARCHITECTURE.md §10`](ARCHITECTURE.md#10-security-architecture) |

### Environments

| Environment | MSK | Aurora | EKS Nodes | Est. Cost |
|-------------|-----|--------|-----------|-----------|
| dev | Serverless | Serverless v2 (0.5–2 ACU) | t3.large (1–5) | ~$250/mo |
| staging | Express 3×m7g.large | r5.large + 1 reader | m7g.xlarge (3–12) | ~$3,400/mo |
| production | Express 3×m7g.xlarge | r6g.xlarge + 2 readers | m7g.xlarge/2xl (5–30) | ~$16,200/mo |

### Key Documents

| Document | Description |
|----------|-------------|
| [`docs/ARCHITECTURE.md`](ARCHITECTURE.md) | Complete architecture documentation |
| [`docs/DEPLOYMENT.md`](DEPLOYMENT.md) | Step-by-step deployment guide |
| [`docs/SCALING.md`](SCALING.md) | Scaling strategies for all layers |
| [`docs/DISASTER-RECOVERY.md`](DISASTER-RECOVERY.md) | DR procedures with runbooks |
| [`docs/TROUBLESHOOTING.md`](TROUBLESHOOTING.md) | Common issues and fixes |

---

## Phase 2: Kubernetes Components

> Repository: `agora-kubernetes-components/`

### Namespace Architecture

| Namespace | Purpose | Workloads |
|-----------|---------|-----------|
| `city-services` | Core microservices | traffic-optimizer, energy-management, data-broker, api-gateway, kafka-connect, schema-registry |
| `inventors` | Isolated tenant namespace | Inventor workloads (sandboxed) |
| `monitoring` | Observability | Prometheus, Grafana |

### Kustomize Structure

| Directory | Contents |
|-----------|----------|
| `kustomization/base/namespaces/` | Namespace definitions |
| `kustomization/base/rbac/` | RoleBindings, ClusterRoles |
| `kustomization/base/network-policies/` | Default-deny + allow rules per namespace |
| `kustomization/base/resource-quotas/` | Per-namespace resource limits |
| `kustomization/base/services/` | Service deployments (traffic-optimizer, energy-mgmt, etc.) |
| `kustomization/base/monitoring/` | Prometheus ServiceMonitor + Grafana |
| `kustomization/base/ingress/` | ALB Ingress Controller + ingress rules |
| `kustomization/base/priority-classes/` | Pod priority and preemption |
| `kustomization/overlays/` | Environment-specific overlays (dev/staging/production) |

### Key Documents

| Document | Description |
|----------|-------------|
| [`docs/ARCHITECTURE.md`](ARCHITECTURE.md) | Full platform architecture |
| [`docs/DEPLOYMENT.md`](DEPLOYMENT.md#5-phase-2-kubernetes-deployment) | K8s deployment guide |
| [`docs/TROUBLESHOOTING.md`](TROUBLESHOOTING.md#4-eks--kubernetes-issues) | K8s troubleshooting |

---

## Phase 3: Data Pipeline

> Repository: `agora-data-pipeline/`

### Pipeline Architecture

```
IoT Devices → MSK Express (Kafka) → Stream Processors → S3 Data Lake
                                    ├── Traffic Optimizer
                                    ├── Anomaly Detector
                                    ├── Energy Optimizer
                                    └── Data Broker (Anonymization)
```

### Topic Design

| Topic | Partitions | Retention | Consumers |
|-------|-----------|-----------|-----------|
| `vehicle.telemetry` | 12 | 7d → S3 | traffic-optimizer, anomaly-detector, data-broker |
| `sensor.environmental` | 6 | 7d → S3 | energy-optimizer, data-broker |
| `signal.events` | 6 | 7d → S3 | traffic-optimizer, data-broker |
| `incidents` | 1 | 30d | anomaly-detector, alerts |
| `signal.commands` | 6 | 2d | traffic-optimizer (output) |
| `data.anonymized.vehicle` | 12 | 30d | data-broker (output) |
| `data.inventor.traffic` | 3 | 7d | data-broker (output) |
| `alerts.notifications` | 1 | 90d | any |
| `dlq.all` | 1 | 30d | dlq-processor |

### Key Documents

| Document | Description |
|----------|-------------|
| [`docs/ARCHITECTURE.md`](agora-data-pipeline/docs/ARCHITECTURE.md) | Pipeline architecture |
| [`docs/TOPIC-DESIGN.md`](agora-data-pipeline/docs/TOPIC-DESIGN.md) | Topic partitioning rationale |
| [`docs/SCHEMA-EVOLUTION.md`](agora-data-pipeline/docs/SCHEMA-EVOLUTION.md) | AVRO schema compatibility |
| [`docs/SCALING.md`](agora-data-pipeline/docs/SCALING.md) | Pipeline scaling |
| [`docs/TROUBLESHOOTING.md`](agora-data-pipeline/docs/TROUBLESHOOTING.md) | Pipeline troubleshooting |

---

## Operations & Security

### Operations

| Document | Description |
|----------|-------------|
| [`docs/OPERATIONS_RUNBOOK.md`](OPERATIONS_RUNBOOK.md) | Daily ops, incident response, escalation, post-mortem |
| [`docs/OPERATIONS.md`](OPERATIONS.md) | Monitoring, capacity, backups, maintenance, change management, cost |
| [`docs/SCALING.md`](SCALING.md) | Three-axis scaling model (vertical, horizontal, elastic) |
| [`docs/DISASTER-RECOVERY.md`](DISASTER-RECOVERY.md) | DR architecture, failover, recovery runbooks, testing |
| [`docs/TROUBLESHOOTING.md`](TROUBLESHOOTING.md) | Diagnostic procedures by layer |

### Security

| Document | Description |
|----------|-------------|
| [`docs/SECURITY.md`](SECURITY.md) | Threat model, network security, IAM, encryption, K8s security, audit, compliance |

---

## API Reference

| Document | Description |
|----------|-------------|
| [`docs/api/README.md`](api/README.md) | API documentation index and versioning strategy |
| [`docs/api/agora-platform-openapi.yaml`](api/agora-platform-openapi.yaml) | Complete OpenAPI 3.0 specification for all platform APIs |

### Core API Endpoints

| Endpoint | Description | Method |
|----------|-------------|--------|
| `/api/v1/traffic/optimize` | Traffic signal optimization requests | POST |
| `/api/v1/energy/optimize` | Energy distribution optimization | POST |
| `/api/v1/data/telemetry` | Device telemetry ingestion | POST |
| `/api/v1/data/anonymized` | Anonymized data for inventors | GET |
| `/api/v1/incidents` | Incident reporting and query | GET, POST |
| `/health/live` | Liveness probe | GET |
| `/health/ready` | Readiness probe | GET |
| `/metrics` | Prometheus metrics endpoint | GET |

---

## Diagrams

All architecture diagrams are in the [diagrams/](../diagrams/) directory. See the [`docs/diagrams/README.md`](diagrams/README.md) for full descriptions.

| Diagram | File | Description |
|---------|------|-------------|
| High-Level Architecture | [`diagrams/high-level-architecture.svg`](../diagrams/high-level-architecture.svg) | 6-layer application stack |
| AWS Infrastructure | [`diagrams/aws-infrastructure.svg`](../diagrams/aws-infrastructure.svg) | VPC/3-AZ/AWS resource layout |
| End-to-End Data Flow | [`diagrams/dataflow.svg`](../diagrams/dataflow.svg) | Complete data flow from devices to S3 |
| Latency Timeline | [`diagrams/latency-timeline.svg`](../diagrams/latency-timeline.svg) | End-to-end latency Gantt chart |
| Istio Service Mesh | [`diagrams/istio-service-mesh.mmd`](../diagrams/istio-service-mesh.mmd) | Istio service mesh topology with Envoy sidecars, mTLS, and inventor egress |
| DR Architecture | [`diagrams/dr-architecture.mmd`](../diagrams/dr-architecture.mmd) | Multi-region DR: 3-AZ primary, cross-region standby, backup automation |
| Terraform State Lock | [`diagrams/terraform-state-lock.mmd`](../diagrams/terraform-state-lock.mmd) | DynamoDB lock flow: acquire, contention, stale detection, force-unlock |

---

## Glossary

See the complete [GLOSSARY.md](GLOSSARY.md) for definitions of all platform terms.

Key terms: **Agora**, **Woven City**, **MSK Express**, **MSK Serverless**, **IRSA**, **Karpenter**, **Kustomize**, **AVRO**, **Schema Registry**, **Kafka Connect**, **S3 Sink**, **DLQ**, **Stream Processor**, **Traffic Optimizer**, **Anomaly Detector**, **Energy Optimizer**, **Data Broker**, **Anonymization Engine**, **Multi-tenancy**, **PDB**, **HPA**, **P99 Latency**, **SLO**, **RPO**, **RTO**, **IAM Access Control**, **mTLS**, **VPC Endpoint**, **OIDC**, **Aurora**, **Timestream**, **ElastiCache**, **Prometheus**, **Grafana**, **ServiceMonitor**, **PodMonitor**, **canary deployment**, **rolling update**, **pod anti-affinity**, **priority class**.

---

## Build & Deploy Docs

```bash
# Build static documentation site
./docs/scripts/build-docs.sh

# Output: site/ directory with HTML documentation
# Requires: Python 3, mkdocs-material
```

---

## Contributing to Documentation

1. All docs are Markdown in the `docs/` directory
2. Source in git, build on CI, preview on PR, deploy on merge
3. Run `mkdocs serve` for local preview
4. Run `./docs/scripts/build-docs.sh` to validate builds
5. Add new pages to `mkdocs.yml` navigation

---

## License

Proprietary — Woven by Toyota / Agora Platform
