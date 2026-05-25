# Grafana Dashboards

## 1. Agora Platform Overview

**Datasource**: Prometheus

This dashboard provides a high-level health view of the entire Agora platform. Key panels include:

- **Uptime & Health**: Overall platform availability percentage and current status badges for each major component (Kafka, data pipeline, infrastructure).
- **CPU/Memory by Namespace**: Stacked bar chart showing resource usage across `city-services`, `monitoring`, and system namespaces.
- **Kafka Lag Overview**: Sparkline for each consumer group showing lag trends over the past 24 hours.
- **Alert Firing Summary**: Embedded panel showing currently firing Prometheus alerts by severity.

Use this as your first stop during incident response to determine blast radius and affected components.

---

## 2. Kafka Performance

**Datasources**: Prometheus (kafka-exporter metrics), Loki (consumer logs)

Detailed Kafka cluster telemetry:

- **Broker Status**: Per-broker health, active connections, and leader partition count.
- **Consumer Lag Per Partition**: Heatmap of consumer lag across all partitions for top-10 consumer groups.
- **Produce/Consume Rates**: Throughput charts (messages/sec, bytes/sec) for each topic.
- **Under-Replicated Partitions**: Time-series showing replication health.
- **Error Rate**: 4xx/5xx Kafka API error rate by broker.

For troubleshooting, check the Consumer Lag heatmap first to identify hotspots, then correlate with broker status panels to identify the failing broker.

---

## 3. Kubernetes Cluster Health

**Datasources**: Prometheus (kube-state-metrics, node-exporter), Loki (pod logs)

Cluster-wide Kubernetes observability:

- **Node Health**: Per-node CPU, memory, disk, and network utilization gauges.
- **Pod Status**: Rolling count of Running, Pending, CrashLoopBackOff, and OOMKilled pods across all namespaces.
- **Deployment Rollout Status**: Table showing each deployment's current vs. desired replicas, generation match, and rollout age.
- **Resource Quotas**: Namespace-level resource quota usage bars.
- **Top-N Pods by Resource**: Sorted list of the most CPU/memory-intensive pods.

Use the Pod Status and resource panels during scale-up events to confirm adequate capacity.

---

## 4. Log Analytics

**Datasource**: Loki

Centralized log exploration and analysis:

- **Log Volume by Namespace**: Time-series of log ingestion rates per namespace with anomaly detection bands.
- **Error Rate by Service**: Count of log lines matching `error`, `exception`, `panic`, or `OOM` patterns, grouped by `service` label.
- **Top Log Producers**: Bar chart showing the top-10 pods/applications generating logs in the selected time range.
- **Search & Explore**: Free-form LogQL query bar with saved query templates for common searches (e.g., `{namespace="city-services"} |= "error"`).

Start with Log Volume to identify unusual spikes, then drill into Error Rate to identify the affected service, and finally use Search & Explore for individual log line inspection.
