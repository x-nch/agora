# Monitoring

This directory contains Kubernetes manifests for the Agora monitoring stack.

## Components

### Prometheus
- **prometheus-serviceaccount.yaml** — ServiceAccount for Prometheus
- **prometheus-clusterrole.yaml** — ClusterRole with permissions for scraping metrics
- **prometheus-clusterrolebinding.yaml** — Binds the ClusterRole to the ServiceAccount
- **prometheus-configmap.yaml** — Prometheus configuration with scrape targets for city-services and Kubernetes API servers
- **prometheus-rules.yaml** — Alerting rules (TrafficOptimizerLatencyHigh, EnergyManagementErrorRateHigh, PodCrashLooping, HighMemoryUsage)
- **prometheus-deployment.yaml** — Deployment with 2 replicas, 90-day retention
- **prometheus-service.yaml** — ClusterIP service on port 9090

### Grafana
- **grafana-secret.yaml** — Admin password secret (change in production!)
- **grafana-configmap.yaml** — Pre-provisioned Prometheus datasource
- **grafana-deployment.yaml** — Deployment with 2 replicas, health probes
- **grafana-service.yaml** — ClusterIP service on port 3000

## Usage

```bash
kubectl apply -f monitoring/
```

Access Grafana via port-forward:
```bash
kubectl port-forward -n monitoring svc/grafana 3000:3000
```
