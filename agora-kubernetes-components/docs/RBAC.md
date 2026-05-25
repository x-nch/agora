# RBAC Configuration

## Overview

Agora uses Kubernetes RBAC to enforce least-privilege access. Each namespace has a dedicated Role and RoleBinding, scoped exactly to what the team needs.

## city-services Role

**Bound to**: `city-services-team` group (via RoleBinding `city-services-manager-binding`)

### Permissions

| Resource Group | Resources | Verbs |
|---------------|-----------|-------|
| Core | pods, services, endpoints, configmaps, secrets, persistentvolumeclaims | CRUD |
| Apps | deployments, statefulsets, daemonsets | CRUD |
| Autoscaling | horizontalpodautoscalers | CRUD |
| Networking | networkpolicies, ingresses | CRUD |
| Policy | poddisruptionbudgets | CRUD |
| Monitoring | servicemonitors, prometheusrules | CRUD |
| Batch | jobs, cronjobs | CRUD |

### Capabilities
- Full lifecycle management of all microservices
- Create and manage HPA rules for autoscaling
- Configure network policies and ingress rules
- Set up PodDisruptionBudgets for HA
- Deploy Prometheus ServiceMonitors and alert rules
- Run batch jobs and cron jobs

## inventors Role

**Bound to**: `inventors-team` group (via RoleBinding `inventors-manager-binding`)

### Permissions

| Resource Group | Resources | Verbs |
|---------------|-----------|-------|
| Core | pods, services, configmaps, secrets, persistentvolumeclaims | CRUD |
| Apps | deployments, statefulsets | CRUD |
| Autoscaling | horizontalpodautoscalers | CRUD |
| Networking | networkpolicies | CRUD |
| Policy | poddisruptionbudgets | CRUD |

### Limitations
- **No DaemonSet or CronJob access**: Cannot run daemon sets or scheduled jobs
- **No Ingress management**: Cannot expose services externally
- **No ServiceMonitor/PrometheusRule access**: Cannot configure scraping or alerting
- **No cross-namespace access**: Role is scoped to the inventors namespace only

## Key Design Decisions

1. **ClusterRoles not used**: All permissions are namespace-scoped via Role (not ClusterRole). No team has cluster-wide access.

2. **Group-based binding**: RoleBindings reference groups, not individual users. This allows identity provider integration (e.g., Azure AD, Okta) where the IdP manages group membership.

3. **No wildcard verbs**: Each verb is explicitly listed. No `*` verbs are used to prevent accidental privilege escalation.

4. **Separation of concerns**: The city-services team can manage ingress and monitoring because they own the platform. The inventors team cannot, because they are tenants.

## Verification

```bash
# Check if a user/service account can perform an action
kubectl auth can-i create deployments \
  --namespace city-services \
  --as system:serviceaccount:city-services:default

# Check RBAC for a specific user
kubectl auth can-i list pods \
  --namespace inventors \
  --as-group inventors-team
```
