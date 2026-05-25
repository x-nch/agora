# Agora Kubernetes Components — Phase 2

**Production-grade, multi-tenant Kubernetes manifests for Woven City's core microservices.**

## Overview

Complete K8s configuration for the Agora platform: 4 core services (traffic-optimizer, energy-management, data-broker, api-gateway) with multi-tenancy isolation, RBAC, network policies, autoscaling, and high availability across 3 AZs.

## Architecture

```
city-services (namespace)      inventors (namespace)    monitoring (namespace)
├── traffic-optimizer          └── (inventor workloads) ├── Prometheus
├── energy-management                                  └── Grafana
├── data-broker
└── api-gateway (ALB ingress)

All pods run in city-services namespace (default). 
All Kafka bootstrap: port 9098, IAM auth via IRSA.
```

## Quick Start

```bash
# Deploy base layer (namespaces, RBAC, network policies, services)
kubectl apply -k kustomization/base

# Or deploy an environment overlay:
kubectl apply -k kustomization/overlays/development
kubectl apply -k kustomization/overlays/staging
kubectl apply -k kustomization/overlays/production

# Validate manifests
./scripts/validate.sh
```

## Project Structure

```
.
├── kustomization/
│   ├── kustomization.yaml       # Overlay entry point (choose env)
│   ├── base/                    # Shared base resources
│   │   ├── kustomization.yaml
│   │   ├── namespaces/          # city-services, inventors, monitoring
│   │   ├── rbac/                # Roles + role bindings per namespace
│   │   ├── network-policies/    # Default-deny + per-ns allow rules
│   │   ├── resource-quotas/     # CPU/memory limits per namespace
│   │   ├── priority-classes/    # agora-critical, agora-high
│   │   ├── services/            # 4 microservice deployments
│   │   │   ├── api-gateway/
│   │   │   ├── traffic-optimizer/
│   │   │   ├── energy-management/
│   │   │   └── data-broker/
│   │   ├── istio/               # Service mesh (mTLS, authz, sidecar, telemetry)
│   │   ├── dr/                  # Disaster recovery (ConfigMap, backup CronJob)
│   │   ├── ingress/             # ALB ingress + ingress class
│   │   └── monitoring/          # Prometheus + Grafana
│   └── overlays/
│       ├── development/         # Reduced replicas, relaxed resources
│       ├── staging/             # Moderate replicas, moderate resources
│       └── production/          # Full HA, strict anti-affinity
├── helm-charts/                 # Helm chart for agora-services
├── scripts/                     # deploy.sh, validate.sh, rollback.sh
└── docs/                        # Architecture, deployment, operations
```

## Core Services

| Service | Replicas | Description | Ingress Path |
|---|---|---|---|
| api-gateway | 3 | ALB ingress, route to services | `api.agora.example.com/` |
| traffic-optimizer | 2 | Real-time traffic flow optimization | `/api/v1/traffic` |
| energy-management | 2 | Smart grid energy distribution | `/api/v1/energy` |
| data-broker | 3 | Kafka ingestion + stream processing | `/api/v1/data` |

## Multi-Tenancy

| Mechanism | Implementation |
|---|---|
| Namespace isolation | `city-services`, `inventors`, `monitoring` |
| Network isolation | Default-deny + per-namespace allow rules |
| **Istio mTLS** | **STRICT mTLS enforced between all services** |
| **Istio Authorization** | **L7 deny-by-default + per-service allow rules** |
| **Istio Sidecar** | **Egress restricted to REGISTRY_ONLY per namespace** |
| RBAC | Least-privilege roles per namespace |
| Resource quotas | CPU/memory caps per namespace |
| Priority classes | `agora-critical` > `agora-high` > default |
| Pod anti-affinity | Prefer/require spread across AZs |
| PDBs | minAvailable: 2 (critical), 1 (standard) |

## DR Automation

| Component | Description |
|---|---|
| `dr/dr-configmap.yaml` | ConfigMap with RTO/RPO/SLO targets, backup schedule, and DR test cadence |
| `dr/backup-cronjob.yaml` | Daily CronJob backing up Terraform state to S3 with lock detection and CloudWatch metric emission |

## Docs

| Document | Description |
|---|---|
| [Architecture](docs/ARCHITECTURE.md) | Full architecture (includes Istio service mesh layer) |
| [Deployment](docs/DEPLOYMENT.md) | Step-by-step deploy (includes Istio + DR components) |
| [Multi-Tenancy](docs/MULTI-TENANCY.md) | Isolation strategy |
| [RBAC](docs/RBAC.md) | Role design |
| [Network Policies](docs/NETWORK-POLICIES.md) | Ingress/egress rules |
| [Autoscaling](docs/AUTOSCALING.md) | HPA tuning |
| [Monitoring](docs/MONITORING.md) | Prometheus/Grafana |
| [Disaster Recovery](docs/DISASTER-RECOVERY.md) | Backup + failover |
| [Troubleshooting](docs/TROUBLESHOOTING.md) | Common fixes |
