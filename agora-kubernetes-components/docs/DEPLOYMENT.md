# Deployment Guide

## Prerequisites

| Tool | Version | Purpose |
|------|---------|---------|
| AWS CLI | >= 2.0 | EKS cluster management |
| kubectl | >= 1.28 | Kubernetes CLI |
| kustomize | >= 5.0 | Manifest customization |
| helm (optional) | >= 3.12 | Helm chart deployment |
| AWS EKS cluster | - | Target cluster |

Cluster requirements:
- EKS 1.28+
- AWS Load Balancer Controller installed
- Amazon MSK cluster accessible (port 9098)
- IRSA configured for data-broker service account
- Prometheus Operator (for ServiceMonitor CRDs)

## Deploying with Kustomize

### Quick Start

```bash
# Make scripts executable
chmod +x scripts/*.sh

# Deploy to development
./scripts/deploy.sh development

# Deploy to staging
./scripts/deploy.sh staging

# Deploy to production
./scripts/deploy.sh production
```

### Manual Deployment

```bash
# 1. Validate manifests
kubectl apply -k kustomization/ --dry-run=client

# 2. Apply base resources (namespaces, RBAC, policies)
kubectl apply -k kustomization/

# 3. Or apply an environment-specific overlay
kubectl apply -k kustomization/overlays/production/
```

### Deployment Order

Resources should be applied in the following order (Kustomize handles this automatically):

1. **Namespaces** — Create city-services, inventors, monitoring
2. **RBAC** — Roles and role bindings
3. **Network Policies** — Default deny, then allow rules
4. **Resource Quotas** — Per-namespace limits
5. **Services** — Core microservice deployments
6. **Istio** — Service mesh (PeerAuthentication, AuthorizationPolicy, Sidecar, RequestAuthentication, Telemetry, Mesh Config)
7. **DR Components** — DR ConfigMap and backup CronJob
8. **Monitoring** — Prometheus and Grafana
9. **Ingress** — ALB ingress class and ingress rules

See [ARCHITECTURE.md](ARCHITECTURE.md#service-mesh-layer-istio) for details on each Istio resource.

## Deploying with Helm

```bash
# Install
helm install agora-services ./helm-charts/agora-services \
  --namespace city-services --create-namespace

# Override values
helm install agora-services ./helm-charts/agora-services \
  --namespace city-services \
  --set trafficOptimizer.replicas=5

# Upgrade
helm upgrade agora-services ./helm-charts/agora-services \
  --namespace city-services
```

## Istio Service Mesh Deployment

### Prerequisites

Install Istio on the cluster before applying the mesh configs:

```bash
# 1. Install Istio CLI
curl -L https://istio.io/downloadIstio | sh -
export PATH=$PWD/istio-1.21/bin:$PATH

# 2. Install Istio on EKS with default profile
istioctl install --set profile=default -y

# 3. Label namespaces for automatic sidecar injection
kubectl label namespace city-services istio-injection=enabled --overwrite
kubectl label namespace inventors istio-injection=enabled --overwrite
kubectl label namespace monitoring istio-injection=enabled --overwrite

# 4. Verify injection labels
kubectl get ns --show-labels | grep istio-injection
```

### Applying Istio Configs

Istio resources deploy automatically via the base kustomization:

```bash
# Deploy everything (includes Istio)
kubectl apply -k kustomization/base

# Or deploy specific environment overlay
kubectl apply -k kustomization/overlays/production
```

### Verifying Sidecar Injection

```bash
# Pods should show 2/2 containers (app + istio-proxy)
kubectl get pods -n city-services
# NAME                               READY   STATUS    RESTARTS   AGE
# api-gateway-7d4f8b9c6f-abc12       2/2     Running   0          5m
# traffic-optimizer-5e6f7a8b9c-def34 2/2     Running   0          5m

# Check sidecar proxy status
istioctl proxy-status

# List Istio resources
kubectl get peerauthentication --all-namespaces
kubectl get authorizationpolicy --all-namespaces
kubectl get sidecar --all-namespaces
kubectl get requestauthentication --all-namespaces
kubectl get telemetry --all-namespaces
```

## DR Components Deployment

DR resources deploy automatically with the base kustomization. Verify them:

```bash
# Check DR ConfigMap
kubectl get configmap dr-config -n city-services -o yaml

# Check backup CronJob
kubectl get cronjob terraform-state-backup -n city-services
# Expected schedule: "0 2 * * *" (daily at 02:00 UTC)

# Check backup ServiceAccount
kubectl get sa dr-backup-sa -n city-services -o yaml

# Manually trigger a backup (ad-hoc test)
kubectl create job --from=cronjob/terraform-state-backup manual-backup-test -n city-services
kubectl logs job/manual-backup-test -n city-services
```

## Verifying Deployment

```bash
# Check namespaces
kubectl get ns

# Check pods (verify 2/2 for Istio-injected services)
kubectl get pods -n city-services -w

# Check services
kubectl get svc -n city-services

# Check HPA status
kubectl get hpa -n city-services

# Check ingress
kubectl get ingress -n city-services

# Check Istio mesh
istioctl proxy-status

# Check DR readiness
kubectl get cronjob terraform-state-backup -n city-services
kubectl get configmap dr-config -n city-services

# Verify monitoring
kubectl get pods -n monitoring
kubectl get servicemonitors -n monitoring
```
