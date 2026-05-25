# Scaling

## Horizontal Scaling

| Component | Scale Signal | Action |
|---|---|---|
| Stream processors | Consumer lag > 500 for 2m | HPA adds pods |
| Data broker | CPU > 70% for 5m | HPA adds pods (max 20) |
| Kafka Connect | Task failures > 0 | Add worker pods via HPA |
| Schema Registry | Request latency > 500ms | Add pods via HPA |
| MSK cluster | Broker CPU > 60% | Add Express brokers |

## Topic Expansion

Add partitions to a topic:
```bash
kafka-topics --alter --topic vehicle.telemetry --partitions 24
```

Stream processors auto-detect new partitions. No cluster rebalance needed (Express auto-distributes).

## Vertical Scaling

Adjust pod resource requests/limits in deployment.yaml for memory-bound processors (anomaly-detector with ML inference).
