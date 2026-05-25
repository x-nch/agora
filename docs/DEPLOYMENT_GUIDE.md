# Deployment Guide — Agora Platform

> **Step-by-step deployment instructions for the Woven City Agora infrastructure across dev/staging/production environments.**
> **Last Updated**: May 2026

---

## Overview

The Agora platform is deployed in 3 phases:

1. **Phase 1: Infrastructure (Terraform IaC)** — VPC, EKS, MSK, Aurora, S3, Monitoring
2. **Phase 2: Kubernetes (Kustomize)** — Namespaces, RBAC, network policies, services, Prometheus
3. **Phase 3: Data Pipeline** — Kafka topics, Schema Registry, Kafka Connect, stream processors, DLQ

For detailed instructions, refer to the full deployment documentation:

- [Full Deployment Guide](DEPLOYMENT.md) — Detailed step-by-step with all commands
- [Architecture](ARCHITECTURE.md) — Complete technical architecture
- [Scaling Strategy](SCALING.md) — Scaling procedures for all layers
- [Disaster Recovery](DISASTER-RECOVERY.md) — Recovery procedures and DR testing
- [Troubleshooting](TROUBLESHOOTING.md) — Common issues and fixes

---

## Deployment Sequence

```
Bootstrap S3 + DynamoDB (one-time)
        │
        ▼
Phase 1: Terraform IaC
├── 1. VPC + IAM (Foundation)
├── 2. EKS (Compute)
├── 3. MSK (Streaming)
├── 4. RDS Aurora (Database)
├── 5. S3 (Storage)
└── 6. Monitoring (Observability)
        │
        ▼
Phase 2: Kubernetes
├── 1. Namespaces
├── 2. RBAC
├── 3. Network Policies
├── 4. Resource Quotas
├── 5. Core Services
└── 6. Monitoring (Prometheus)
        │
        ▼
Phase 3: Data Pipeline
├── 1. Kafka Topics + AVRO
├── 2. Schema Registry
├── 3. Kafka Connect S3 Sink
├── 4. Stream Processors
├── 5. IAM Auth (IRSA)
├── 6. DLQ Processor
└── 7. Pipeline Monitoring
        │
        ▼
Verification & Testing
```

---

## Environment-Specific Guides

| Environment | Terraform Config | Est. Cost | Key Differences |
|-------------|-----------------|-----------|-----------------|
| **Dev** | `terraform/environments/dev` | ~$250/mo | MSK Serverless, Aurora Serverless v2, 1–5 EKS nodes |
| **Staging** | `terraform/environments/staging` | ~$3,400/mo | MSK Express 3×m7g.large, r5.large + 1 reader, 3–12 nodes |
| **Production** | `terraform/environments/production` | ~$16,200/mo | MSK Express 3×m7g.xlarge, r6g.xlarge + 2 readers, 5–30 nodes |

---

## Verification

After deployment, run:

```bash
make verify ENV=<environment>
```

This runs:
- Smoke test (cluster health, pods, services)
- End-to-end integration test (produce → consume → S3 archive)

---

## Rollback

See the [Deployment Guide](DEPLOYMENT.md#8-rollback-procedures) for detailed rollback procedures for Terraform, Kubernetes, and data pipeline components.

---

## CI/CD

The deployment is automated via GitHub Actions:

- Terraform validation on PR
- Terraform plan on PR to main (with commenting)
- Terraform apply on merge to main
- Kustomize build and kubectl apply on merge to main

See [DEPLOYMENT.md §10](DEPLOYMENT.md#10-cicd-integration) for CI/CD configuration.
