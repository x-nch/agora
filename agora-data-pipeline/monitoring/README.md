# Pipeline Monitoring

Prometheus alerting rules and Grafana dashboard for the data pipeline.

## Key Metrics

| Metric | Source | Alert Threshold | Severity |
|---|---|---|---|
| Consumer lag | MSK CloudWatch / Kafka exporter | > 1000 for 5m | Critical |
| Processing latency P99 | Custom metric (histogram) | > 100ms (traffic), > 1s (energy) | Critical |
| Error rate | Custom metric | > 0.1% for 5m | Critical |
| DLQ depth | Kafka offset | > 1000 unprocessed | Critical |
| Kafka Connect task status | Connect REST API | FAILED state | Critical |
| Schema registry latency | Schema Registry metrics | > 500ms P99 | Warning |
| Produce throughput | MSK CloudWatch | > 80% capacity | Warning |

## Dashboards

Import `grafana-dashboard-pipeline.json` into Grafana for pipeline-specific monitoring.
