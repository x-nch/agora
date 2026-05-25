# Kustomize Configuration

## Overview

This directory contains the Kustomize configuration for deploying Agora services across multiple environments. Kustomize allows environment-specific customization without duplicating manifests.

## Structure

```
kustomization/
├── kustomization.yaml          # Base: all resources with development defaults
├── namespaces/                 # Namespace definitions
├── rbac/                       # Role-based access control
├── network-policies/           # Network traffic rules
├── resource-quotas/            # Per-namespace resource limits
├── services/                   # Core microservice manifests
│   ├── traffic-optimizer/
│   ├── energy-management/
│   ├── data-broker/
│   └── api-gateway/
├── monitoring/                 # Prometheus + Grafana
├── ingress/                    # ALB ingress configuration
└── overlays/                   # Environment-specific overrides
    ├── development/
    ├── staging/
    └── production/
```

## Environments

| Environment | Base Replicas | Dev Replicas | Staging Replicas | Production Replicas |
|------------|--------------|--------------|------------------|--------------------|
| traffic-optimizer | 2 | 1 | 3 | 5 |
| energy-management | 2 | 1 | 2 | 3 |
| data-broker | 3 | 3 | 3 | 5 |
| api-gateway | 3 | 3 | 3 | 5 |

### Development
- Reduced resource footprint (single replicas for stateless services)
- Annotations set `env: development`
- Suitable for local testing and CI

### Staging
- Production-like replica counts
- Annotations set `env: staging`
- Validates scaling behavior before production

### Production
- Full HA with multiple replicas per AZ
- Strict pod anti-affinity for traffic-optimizer (requiredDuringScheduling)
- Annotations set `env: production`
- Higher resource quotas

## Usage

```bash
# Apply development overlay
kubectl apply -k kustomization/overlays/development/

# Apply staging overlay
kubectl apply -k kustomization/overlays/staging/

# Apply production overlay
kubectl apply -k kustomization/overlays/production/
```

## Patch Strategy

- **Strategic merge patches**: Used for replica count changes (simpler, merges cleanly with base)
- **patchesJson6902**: Used for complex structural changes like pod anti-affinity replacement in production
- All patches target specific deployments by name to avoid unintended modifications
