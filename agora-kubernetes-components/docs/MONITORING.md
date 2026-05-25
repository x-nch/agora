# Monitoring

## Overview

The monitoring stack consists of Prometheus for metrics collection and Grafana for visualization. All four core services expose Prometheus metrics via the `/actuator/prometheus` endpoint (Spring Boot Actuator).

## Components

### Prometheus

| Setting | Value |
|---------|-------|
| Image | prom/prometheus:v2.47.0 |
| Namespace | monitoring |
| Port | 9090 |
| Storage | emptyDir (30-day retention) |
| Resources | requests: 500m CPU / 2Gi memory |

Prometheus is configured to scrape:
- **ServiceMonitors**: Each service has a ServiceMonitor CRD in the monitoring namespace that defines scrape targets, intervals, and paths
- **kubelet/cadvisor**: Node-level metrics via kubelet endpoints
- **Custom endpoints**: Any additional scrape targets defined in Prometheus configuration

### Grafana

| Setting | Value |
|---------|-------|
| Image | grafana/grafana:10.2.0 |
| Namespace | monitoring |
| Port | 3000 |
| Plugins | grafana-piechart-panel |
| Resources | requests: 200m CPU / 512Mi memory |

Grafana provisions:
- **Datasources**: Prometheus datasource configured automatically
- **Dashboards**: Pre-configured dashboards for all services

## ServiceMonitors

Each service has a ServiceMonitor that tells Prometheus how to scrape:

| Service | Path | Interval | Timeout |
|---------|------|----------|---------|
| traffic-optimizer | /actuator/prometheus | 15s | 10s |
| energy-management | /actuator/prometheus | 15s | 10s |
| data-broker | /actuator/prometheus | 15s | 10s |
| api-gateway | /actuator/prometheus | 15s | 10s |

## Metrics Categories

### Application Metrics (from each service)
- JVM memory usage (heap, non-heap)
- GC pause times and frequency
- HTTP request rates, latencies (p50, p95, p99), error rates
- Thread pool utilization
- Custom business metrics (specific to each service)

### Infrastructure Metrics (from kube-state-metrics / cAdvisor)
- Pod CPU and memory usage
- Node resource utilization
- Deployment replica counts
- Container restarts

### Kafka Metrics (from data-broker)
- Consumer lag
- Message throughput
- Connection pool status

## Alerting

Alert rules should be configured via PrometheusRule CRDs (requires Prometheus Operator):
- High CPU/memory utilization (>85% for 5m)
- Pod crash loop (restart count > 3 in 10m)
- High error rate (>5% for 5m)
- Kafka consumer lag (>10000 messages for 5m)
- HPA at max replicas for extended period

## Accessing Dashboards

```bash
# Port-forward Prometheus
kubectl port-forward svc/prometheus -n monitoring 9090:9090

# Port-forward Grafana
kubectl port-forward svc/grafana -n monitoring 3000:3000
```

Then open http://localhost:9090 (Prometheus) or http://localhost:3000 (Grafana).
