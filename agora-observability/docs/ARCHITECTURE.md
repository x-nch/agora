# Observability Stack Architecture

## Stack Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                       Prometheus Operator                       │
│  (Manages Prometheus, Alertmanager, ServiceMonitors,           │
│   PrometheusRules via Kubernetes CRDs)                         │
└──────┬──────────────────────┬──────────────────────┬────────────┘
       │                      │                      │
       ▼                      ▼                      ▼
┌──────────────┐    ┌──────────────────┐    ┌──────────────────────┐
│  Prometheus  │    │   Alertmanager   │    │     Grafana          │
│  (2 replicas │    │  (3 replicas)    │    │  (1 replica)         │
│   HA mode)   │    │  HA mesh)        │    │  Dashboards +        │
│  Retention:  │    │  Routes:         │    │  Datasources:        │
│  90d / 90GB  │    │  critical→PD     │    │  - Prometheus        │
│              │    │  warning→Slack   │    │  - Loki              │
│              │    │  info→null       │    │  - CloudWatch        │
└──────┬───────┘    └──────────────────┘    └──────────────────────┘
       │                                                ▲
       │ scrapes                                       │ queries
       ▼                                                │
┌───────────────────────────────────────────────────────┘
│
│  ┌────────────┐  ┌────────────────┐  ┌───────────────┐
│  │node-       │  │kube-state-     │  │kube-metrics-  │
│  │exporter    │  │metrics         │  │adapter        │
│  │(DaemonSet) │  │(Deployment)    │  │(Deployment)   │
│  └────────────┘  └────────────────┘  └───────────────┘
│
│  ┌────────────┐  ┌──────────────┐  ┌──────────────────┐
│  │kafka-      │  │Kafka-        │  │AWS CloudWatch    │
│  │exporter    │  │MirrorMaker   │  │exporter          │
│  │(IAM signing)│ │exporter      │  │                  │
│  └────────────┘  └──────────────┘  └──────────────────┘
│
│  ┌──────────────────────┐  ┌─────────────────────────┐
│  │  Loki (3 replicas)   │  │  Promtail (DaemonSet)   │
│  │  S3 storage backend  │  │  Log shipping agent     │
│  └──────────────────────┘  └─────────────────────────┘
│
│  ┌─────────────────────────────────────────────┐
│  │  AMP remote_write (mirror to AWS Managed    │
│  │  Prometheus for long-term storage)          │
│  └─────────────────────────────────────────────┘
```

## Components

| Component | Type | Replicas | Purpose |
|---|---|---|---|
| Prometheus Operator | Deployment | 1 | Manages monitoring CRDs |
| Prometheus | StatefulSet | 2 (HA) | Metrics storage & alerting evaluation |
| Alertmanager | StatefulSet | 3 (HA mesh) | Alert dedup, grouping, routing |
| Grafana | Deployment | 1 | Visualization & dashboards |
| Loki | StatefulSet | 3 | Log aggregation (S3 backend) |
| Promtail | DaemonSet | per-node | Log shipping to Loki |
| node-exporter | DaemonSet | per-node | Node-level metrics |
| kube-state-metrics | Deployment | 1 | Kubernetes object metrics |
| kafka-exporter | Deployment | 1 | Kafka consumer lag metrics |
| CloudWatch exporter | Deployment | 1 | AWS service metrics |

## Key Design Decisions

**Prometheus Operator**: We use the Operator pattern to manage Prometheus and Alertmanager declaratively via Kubernetes CRDs. This eliminates manual config file management and enables GitOps workflows. ServiceMonitor CRDs auto-discover scrape targets from service labels.

**Loki over Elasticsearch**: Loki is preferred for its lightweight design — it indexes labels, not raw logs, which dramatically reduces storage cost and operational complexity. The S3 storage backend provides durable, scalable log storage without managing Elasticsearch clusters.

**S3 Storage Backend**: Both Loki and Prometheus (via Thanos sidecar pattern) use S3 for long-term storage. This decouples compute from storage, allows independent scaling, and leverages S3's 99.99999999% durability.

**Alertmanager Routing**: Alerts are routed by severity label: critical → PagerDuty (immediate notification), warning → Slack (same-day triage), info → null (blackhole). This ensures on-call engineers are only paged for truly urgent issues while maintaining visibility for lower-severity alerts.

**IAM Signing Proxy for kafka-exporter**: Since MSK uses IAM authentication (port 9098), the kafka-exporter requires an AWS SigV4 signing proxy sidecar to authenticate with the MSK cluster.

**AMP Remote Write**: Production Prometheus is configured with a remote_write rule to mirror all metrics to Amazon Managed Prometheus. This provides a disaster recovery copy and enables long-term querying beyond Prometheus's local retention window.
