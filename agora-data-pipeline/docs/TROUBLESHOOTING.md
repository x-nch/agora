# Troubleshooting

## Common Issues

### High Consumer Lag
```
Check: kafka-consumer-groups --bootstrap-server <brokers> --group <group> --describe
Fix: HPA should auto-scale. If not, check pod resource constraints.
     Manual: kubectl -n city-services scale deployment/<processor> --replicas=<n>
```

### Processing Errors
```
Check: kubectl -n city-services logs <pod-name>
       Check DLQ: kafka-console-consumer --topic dlq.all --from-beginning --max-messages 10
Fix: DLQ processor auto-retries transient errors (up to 3x)
```

### Schema Registry Errors
```
Check: kubectl -n city-services logs deployment/schema-registry
       curl http://schema-registry:8081/subjects
Fix: Schema Registry runs with read-only local cache if primary is down
```

### Kafka Connect Task Failure
```
Check: curl http://kafka-connect:8083/connectors/<name>/status
Fix: RESTART: curl -X POST http://kafka-connect:8083/connectors/<name>/restart
```

### Corrupt Consumer Offsets
```bash
scripts/reset-consumer-offset.sh <group-id> --to-earliest
kubectl -n city-services rollout restart deployment/<processor>
```

### Data Corruption in S3
- Raw data retained in MSK for 7 days (vehicle telemetry)
- Replay from MSK or restore from S3 Glacier for older data

## Recovery Procedures

| Failure | Recovery |
|---|---|
| Dead stream processor | K8s auto-restarts pod, consumer group rebalances |
| Schema registry down | Processors use local schema cache (read-only mode) |
| MSK broker failure | Express auto-recovers; no manual intervention |
| Data broker down | Raw data accumulates in MSK (7d retention buffer) |
