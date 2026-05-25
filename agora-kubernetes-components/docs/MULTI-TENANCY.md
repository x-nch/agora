# Multi-Tenancy

## Overview

Agora uses a namespace-based multi-tenancy model with three isolation layers: RBAC, network policies, and resource quotas. This ensures tenants cannot access each other's data or disrupt each other's workloads.

## Namespace Isolation

| Namespace | Purpose | Isolation Level | Pod Security |
|-----------|---------|----------------|--------------|
| city-services | Core Agora microservices | Full (managed team) | restricted |
| inventors | Tenant workloads | Self-service | baseline |
| monitoring | Observability stack | Admin-only | privileged |

## Isolation Mechanisms

### 1. RBAC (Role-Based Access Control)

Each namespace has its own Role and RoleBinding:

- **city-services-manager** (city-services namespace): Full CRUD on pods, deployments, services, HPA, network policies, ingresses, PDBs, ServiceMonitors, and batch jobs. Assigned to the `city-services-team` group.

- **inventors-manager** (inventors namespace): CRUD on pods, deployments, services, HPA, and network policies. Restricted: no ingress management, no ServiceMonitor/PrometheusRule access, no DaemonSet management. Assigned to the `inventors-team` group.

- **No cross-namespace access**: The inventors role cannot read or modify resources in city-services, and vice versa.

### 2. Network Policies

Three layers of network isolation:

1. **Default deny all**: Applied to every namespace as a baseline. No ingress or egress allowed by default.

2. **Per-namespace allow rules**: Each namespace has an internal allow rule (traffic within the namespace is permitted).

3. **Cross-namespace exceptions**: Only explicitly allowed:
   - inventors → api-gateway (port 8080) in city-services
   - city-services → prometheus (port 9090) in monitoring
   - monitoring → all namespaces (metrics scraping)

### 3. Resource Quotas

| Resource | city-services | inventors |
|----------|--------------|-----------|
| CPU requests | 8 cores | 4 cores |
| Memory requests | 16 Gi | 8 Gi |
| CPU limits | 16 cores | 8 cores |
| Memory limits | 32 Gi | 16 Gi |
| PersistentVolumeClaims | 10 | 5 |
| Deployments | 20 | 10 |
| Services | 20 | 10 |
| Secrets | 40 | 20 |
| ConfigMaps | 40 | 20 |

### 4. Pod Security Standards

- **city-services**: `restricted` — Pods must run as non-root, with read-only root filesystem, and cannot escalate privileges.
- **inventors**: `baseline` — Prevents known privilege escalations but allows some flexibility.
- **monitoring**: `privileged` — Required for Prometheus node-exporter and similar components.

## Data Isolation

- **city-services** has direct access to Amazon MSK (Kafka) via IRSA. The `data-broker-sa` service account is annotated with an IAM role that grants MSK access.
- **inventors** cannot access Kafka directly. All city data is accessed through the api-gateway, which enforces authentication and authorization.
- Network policies explicitly block inventors → Kafka traffic (port 9098 is not in any inventors egress rule).
