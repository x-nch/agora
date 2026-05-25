# Agora Observability

Production-grade monitoring, logging, and alerting stack for the Agora platform on EKS.

## Stack

- **Prometheus Operator** — Declarative metrics collection via Kubernetes CRDs
- **Prometheus** (2-node HA) — Metrics storage, alert rule evaluation
- **Alertmanager** (3-node HA mesh) — Alert dedup, grouping, PagerDuty/Slack routing
- **Grafana** — Dashboards (4 pre-built) with Prometheus, Loki, CloudWatch datasources
- **Loki** (3-node) + **Promtail** — Log aggregation with S3 backend
- **Exporters** — node-exporter, kube-state-metrics, kafka-exporter, CloudWatch exporter

## Pre-requisites

- Phase 1: Terraform-infra deployed (EKS cluster, MSK, S3 buckets)
- Phase 2: Kustomize base resources applied to cluster
- `kubectl` context pointing to target cluster

## Deployment

```bash
# Development (default)
./scripts/deploy-observability.sh

# Staging or production
./scripts/deploy-observability.sh staging
./scripts/deploy-observability.sh production

# Verify stack health
./scripts/verify-stack.sh

# Fire test alerts
./scripts/test-alerts.sh
```

## DR Alert Rules

PrometheusRule [`alert-rules/dr-rules.yaml`](kustomization/base/alert-rules/dr-rules.yaml) defines 8 DR-specific alerts:

| Alert Name | Severity | Condition | RTO | Description |
|---|---|---|---|---|
| `SafetyCriticalComponentDegraded` | critical | `up{app="emergency-router"}=0` OR `up{app="emergency-dispatch"}=0` for 5s | 30s | Safety-critical component is down |
| `CityOperationalSLOTracking` | warning | City-services error rate > 0.1% (SLO < 99.9%) for 5m | 5m | Approaching error budget |
| `PotentialAZFailure` | critical | `< 2` nodes in any AZ for 2m | — | Possible AZ outage detected |
| `TerraformStaleLock` | warning | Lock age > 900s (15m) for 1m | — | Terraform lock held too long |
| `StateBackupStale` | warning | Backup age > 90,000s (25h) for 5m | — | State backup may have failed |
| `RTOBreachRisk` | critical | 5% error rate in city-services for 1m | — | Catastrophic error rate |
| `KafkaBrokerCountLow` | critical | `< 3` MSK brokers for 1m | — | Data durability at risk |
| `IstioMTLSFailureRate` | warning | mTLS failure rate > 1% for 5m | — | Certificate or auth misconfig |

## Grafana Dashboards

The stack includes 6 pre-built Grafana dashboards (2 new):

| Dashboard | UID | Description |
|---|---|---|
| Platform Overview | (`platform-overview`) | Aggregate view of all services, topics, and infrastructure |
| Service Metrics | (`service-metrics`) | Per-service request rate, latency, error rate |
| Kafka Monitoring | (`kafka-monitoring`) | Topic throughput, consumer lag, broker health |
| Pipeline Monitoring | (`pipeline-monitoring`) | Stream processor health, S3 sink status |
| **Istio Service Mesh** | (`istio-services`) | mTLS handshake success rate, requests by namespace, authz denies, TCP throughput |
| **DR Readiness** | (`dr-readiness`) | Terraform state backup age, AZ node distribution, consumer lag (RPO tracking), P99 latency vs RTO |

### Istio Service Mesh Dashboard (`istio-services`)

Panels:
- **mTLS Handshake Success Rate** — `sum(rate(istio_requests_total{...}))` ratio
- **Requests by Source Namespace** — Flow matrix between namespaces
- **Authorization Policy Denies** — 403 rate by destination service and source principal
- **TCP Throughput by Namespace** — Bytes sent between namespaces

### DR Readiness Dashboard (`dr-readiness`)

Panels:
- **Terraform State Backup Age** — `time() - dr_backup_timestamp_seconds`
- **AZ Node Distribution** — Node count per AZ (stat panel)
- **Consumer Lag (RPO Tracking)** — Lag for `agora-data-broker`, `traffic-optimizer-group`, `energy-optimizer-group`
- **P99 Latency vs RTO** — `histogram_quantile(0.99, ...)` for city-services

## Docs

| Document | Description |
|---|---|
| [Architecture](docs/ARCHITECTURE.md) | Stack diagram, component list, design rationale |
| [Alerting](docs/ALERTING.md) | Routing tree, alert inventory, silencing |
| [Runbooks](docs/RUNBOOKS.md) | Investigation and resolution steps per alert |
| [Dashboards](docs/DASHBOARDS.md) | Grafana dashboard descriptions and usage |
