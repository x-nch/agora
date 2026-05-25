# Alerting & Routing

## Routing Tree

```
Alert (severity label)
│
├─ critical ──▶ route: critical → PagerDuty
│                - Immediate push notification
│                - Escalation after 15min if unacknowledged
│                - 24/7 on-call rotation
│
├─ warning ───▶ route: warning → Slack #agora-alerts
│                - Same-business-day triage
│                - No escalation
│                - Bundled into daily digest
│
└─ info ──────▶ route: info → null (blackhole)
                  - No notification
                  - Visible in Alertmanager UI
                  - Used for future capacity planning
```

## Alert Inventory

| # | Alert Name | Source | Severity | Threshold | Receiver |
|---|---|---|---|---|---|
| 1 | KafkaConsumerLagHigh | kafka-exporter | critical | lag > 1000 | PagerDuty |
| 2 | KafkaBrokerDown | kafka-exporter | critical | broker count < ISR | PagerDuty |
| 3 | KafkaUnderReplicatedPartitions | kafka-exporter | critical | partitions > 0 | PagerDuty |
| 4 | KafkaOfflinePartitions | kafka-exporter | critical | partitions > 0 | PagerDuty |
| 5 | NodeHighCPUUsage | node-exporter | critical | CPU > 90% for 10m | PagerDuty |
| 6 | NodeHighMemoryUsage | node-exporter | critical | memory > 90% for 10m | PagerDuty |
| 7 | NodeDiskFull | node-exporter | critical | disk usage > 90% | PagerDuty |
| 8 | PodCrashLooping | kube-state-metrics | critical | crash loop > 5m | PagerDuty |
| 9 | PodPending | kube-state-metrics | critical | pending > 10m | PagerDuty |
| 10 | K8sDeploymentReplicasMismatch | kube-state-metrics | critical | unavailable > 0 for 10m | PagerDuty |
| 11 | K8sJobFailed | kube-state-metrics | critical | job failed | PagerDuty |
| 12 | EtcdLeaderChanges | etcd | critical | leader changes > 5/10m | PagerDuty |
| 13 | KafkaConsumerLagWarning | kafka-exporter | warning | lag > 500 | Slack |
| 14 | NodeDiskWarning | node-exporter | warning | disk usage > 80% | Slack |
| 15 | NodeLoadAverageHigh | node-exporter | warning | load > 5 for 15m | Slack |
| 16 | PodRestarts | kube-state-metrics | warning | restarts > 3 in 1h | Slack |
| 17 | K8sDeploymentGenerationMismatch | kube-state-metrics | warning | generation mismatch | Slack |
| 18 | LokiDroppedLogs | promtail | warning | drop rate > 1% | Slack |
| 19 | PrometheusTargetDown | prometheus-operator | warning | target down > 5% | Slack |
| 20 | NodeDiskInfo | node-exporter | info | disk usage > 70% | null |
| 21 | PrometheusNotificationQueue | prometheus-operator | info | queue > 50% | null |
| 22 | KafkaRequestRate | kafka-exporter | info | requests > baseline 2x | null |

## How to Silence an Alert

Temporarily silence via Alertmanager UI (port-forward: `kubectl port-forward -n monitoring svc/alertmanager-agora 9093`) or API:

```bash
curl -XPOST http://localhost:9093/api/v2/silences \
  -H 'Content-Type: application/json' \
  -d '{"matchers":[{"name":"alertname","value":"NodeDiskFull","isRegex":false}],"startsAt":"2025-01-01T00:00:00Z","endsAt":"2025-01-02T00:00:00Z","createdBy":"admin","comment":"Maintenance window"}'
```

## How to Add a New Route

1. Edit `kustomization/base/alertmanager/alertmanager-config.yaml`
2. Add a new route under `route.routes` with match criteria and receiver
3. Add the receiver under `receivers` with the appropriate integration config
4. Apply via `kubectl apply -k kustomization/overlays/<env>/`
