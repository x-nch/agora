# S3 Sink Connectors

Archives raw Kafka topics to S3 data lake in AVRO format with hourly partitioning.

| Connector | Source Topic | S3 Prefix | Flush | Tasks |
|---|---|---|---|---|
| s3-sink-vehicle-telemetry | vehicle.telemetry | raw/vehicle.telemetry/ | 10K msgs / 1hr | 12 |
| s3-sink-environmental | sensor.environmental | raw/sensor.environmental/ | 5K msgs / 1hr | 6 |
| s3-sink-signal-events | signal.events | raw/signal.events/ | 5K msgs / 1hr | 6 |
| s3-sink-incidents | incidents | raw/incidents/ | 500 msgs / 1hr | 1 |

## Deploy Connectors

```bash
# Apply each connector via Kafka Connect REST API
for f in connectors/*.json; do
  curl -X POST http://kafka-connect:8083/connectors \
    -H "Content-Type: application/json" \
    -d @"$f"
done
```

## Verify

```bash
curl http://kafka-connect:8083/connectors?expand=status | jq .
```

S3 path: `s3://agora-prod-data-lake/raw/<topic>/year=YYYY/month=MM/day=dd/hour=HH/<topic>+<partition>+<offset>.avro`
