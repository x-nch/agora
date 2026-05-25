# Data-Broker Stream Processor

Real-time Kafka Streams processor for vehicle telemetry, environmental sensor data, and signal events. Ingests 60K+ events/sec from MSK, applies PII anonymization, windowed aggregation per district, and access-control routing to downstream topics and S3 data lake.

## Processing Architecture

```
vehicle.telemetry ─┐
sensor.environmental ─┤  ┌──────────┐  ┌──────────┐  ┌──────────────┐
signal.events ──────┘  │Anonymizer│→│Aggregator│→│AccessControl│
                        └──────────┘  └──────────┘  └──────┬───────┘
                                                            │
                        ┌───────────────────────────────────┤
                        │                                   │
                        ▼                                   ▼
              data.anonymized.vehicle             data.inventor.traffic
              (city planners, researchers)        (inventor traffic app)
                                                   + S3 data lake
```

## Stages

| Stage | Purpose |
|---|---|
| **Anonymizer** | Strips PII (driver_id, license_plate, payment), rounds GPS to 100m grid, buckets speed, adds `anonymized_at` |
| **Aggregator** | 10-second tumbling windows per district, computes avg speed, vehicle counts by type, congestion level |
| **Access Controller** | Routes data by permission tier — city planners get full aggregates, inventor app gets sector averages, external researchers get anonymized non-real-time only |

## Kafka Topics

| Source | Sink |
|---|---|
| `vehicle.telemetry` | `data.anonymized.vehicle`, `data.inventor.traffic` |
| `sensor.environmental` | `data.inventor.traffic` |
| `signal.events` | `data.inventor.traffic` |

## Deployment

```bash
kubectl apply -f configmap.yaml
kubectl apply -f deployment.yaml
kubectl apply -f service.yaml
kubectl apply -f hpa.yaml
kubectl apply -f pdb.yaml
kubectl apply -f servicemonitor.yaml
```
