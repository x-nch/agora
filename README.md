# Agora Platform

**Smart city operating system for Woven City — Toyota's prototype city at the base of Mount Fuji.**

Ingests 60K+ events/sec from 10,000+ IoT devices across 5 districts, processing them through a real-time data pipeline for traffic optimization, energy management, anomaly detection, and multi-tenant data brokering.

## Repositories

| Directory | Phase | Description |
|---|---|---|
| `agora-infrastructure/` | Phase 1 | Terraform IaC — VPC, EKS, MSK Express, Aurora, S3, IAM, KMS |
| `agora-kubernetes-components/` | Phase 2 | K8s manifests — services, multi-tenancy, RBAC, network policies, monitoring |
| `agora-data-pipeline/` | Phase 3 | Kafka pipeline — topics, Schema Registry, Connect, 4 stream processors, DLQ |

## Recent Additions

| Addition | Description | Key Docs |
|----------|-------------|----------|
| **Istio Service Mesh** | STRICT mTLS enforcement, L7 deny-by-default authz, sidecar egress restriction, JWT validation, per-namespace telemetry | [Deployment](agora-kubernetes-components/docs/DEPLOYMENT.md#istio-service-mesh-deployment), [Architecture](agora-kubernetes-components/docs/ARCHITECTURE.md#service-mesh-layer-istio) |
| **Terraform State Lock Hardening** | DynamoDB PITR + TTL + streams, stale lock CloudWatch alarm, S3 lifecycle cleanup for state versions | [Infrastructure](agora-infrastructure/README.md#state-lock--bootstrap) |
| **DR Automation** | State backup CronJob with S3 Object Lock (GOVERNANCE, 7d), DR ConfigMap with RTO/RPO targets, DR SNS topic, dedicated DR alerts + dashboards | [Disaster Recovery](docs/DISASTER-RECOVERY.md), [Observability](agora-observability/README.md#dr-alert-rules) |

## Quick Links

- [Documentation Hub](docs/README.md) — Full docs with architecture, deployment, security, operations
- [API Reference](docs/api/README.md) — REST API docs + OpenAPI spec
- [Architecture Diagrams](docs/diagrams/) — Mermaid diagrams (platform, data flow, infra, security)
- [Glossary](docs/GLOSSARY.md) — Platform terminology
- [Deployment Guide](docs/DEPLOYMENT.md) — End-to-end deployment procedures
- [Disaster Recovery](docs/DISASTER-RECOVERY.md) — Backup, failover, and cross-region DR plans

## Architecture

```
IoT Devices (10K+) → MSK Express (3 brokers) → Stream Processors → S3 Data Lake
                          ↓                          ↓
                   Schema Registry            Aurora PostgreSQL
                          ↓                          ↓
                   Kafka Connect              API Gateway (ALB)
```

## Key Decisions

| Decision | Rationale |
|---|---|
| MSK Express > Provisioned | 3x throughput, 20x faster scaling, 90% faster recovery |
| IAM Auth (IRSA) > mTLS | No certificate rotation, pod-level auth via K8s SA |
| Aurora > RDS | ~30s failover vs ~120s, auto-scaling to 128TB |
| Kustomize > raw YAML | Environment overlays for dev/staging/prod |
| 12 partitions for telemetry | Max parallelism, room to double |
| Data broker anonymization | PII stripped before multi-tenant distribution |

## Environments

| Environment | MSK | Aurora | EKS Nodes | Est. Cost |
|---|---|---|---|---|
| dev | Serverless | Serverless v2 | t3.large (1-5) | ~$250/mo |
| staging | Express 3x m7g.large | r5.large + 1 reader | m7g.xlarge (3-12) | ~$3,400/mo |
| production | Express 3x m7g.xlarge | r6g.xlarge + 2 readers | m7g.xlarge/2xl (5-30) | ~$16,200/mo |

## Prerequisites

- AWS CLI, Terraform >= 1.0, kubectl >= 1.28
- Python 3.11, Docker, Java 11
- `ap-northeast-1` AWS region

See [Getting Started](docs/GETTING_STARTED.md) for full setup instructions.
