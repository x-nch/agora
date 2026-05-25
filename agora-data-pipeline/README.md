# Agora Data Pipeline — Phase 3

**Real-time Kafka pipeline handling 60K+ events/sec from 10K+ IoT devices across 5 districts.**

## Architecture

```
IoT Devices → MSK Express (3 brokers, IAM port 9098) → Stream Processors → S3 Data Lake
                  ↓                                                 ↓
            Schema Registry                               Kafka Connect
            (AVRO compat)                                 (4 S3 sink connectors)

Stream Processors:
  traffic-optimizer  → signal.commands, incidents      (SLO: <100ms)
  anomaly-detector   → incidents, alerts.notifications  (SLO: <500ms)
  energy-optimizer   → alerts.notifications             (SLO: <1s)
  data-broker        → data.anonymized.vehicle,         (anonymizer→aggregator→access_control)
                        data.inventor.traffic
```

## Quick Start

```bash
# Prerequisites: EKS cluster, MSK cluster, Schema Registry at :8081

# Create 9 Kafka topics
./kafka-topics/apply-topics.sh

# Deploy all pipeline components
./scripts/deploy-pipeline.sh

# Test end-to-end
./scripts/test-end-to-end.sh

# Seed 1000 test events
./scripts/seed-test-data.sh b-1:9098 1000
```

## Topics

| Topic | Partitions | Retention | Key | Rate |
|---|---|---|---|---|
| vehicle.telemetry | 12 | 7d (compacted) | vehicle_type | 10K/s |
| sensor.environmental | 6 | 7d | district | 5K/s |
| signal.events | 6 | 7d | intersection_id | 2K/s |
| incidents | 1 | 30d | — | 100/s |
| signal.commands | 6 | 2d | intersection_id | 1K/s |
| data.anonymized.vehicle | 12 | 30d | district | 10K/s |
| data.inventor.traffic | 3 | 7d | inventor_id | 500/s |
| alerts.notifications | 1 | 90d (compacted) | — | 50/s |
| dlq.all | 1 | 30d | — | 10/s |

## Project Structure

| Directory | Description |
|---|---|
| `kafka-topics/` | `definitions.yaml`, 7 AVRO schemas, `apply-topics.sh` |
| `schema-registry/` | Confluent Schema Registry K8s manifests (Deployment, Service, ConfigMap, PDB, HPA) |
| `kafka-connect/` | Distributed Kafka Connect cluster + 4 S3 sink connectors |
| `stream-processors/` | 4 Python processors (traffic-optimizer, anomaly-detector, energy-optimizer, data-broker) |
| `dead-letter-queue/` | DLQ processor — classifies failures (schema/deserialization/transient/poison pill) |
| `iam/` | MSK IAM policies + IRSA ServiceAccounts (7 roles) |
| `client-configs/` | Producer/consumer ConfigMaps tuned for 60K msg/sec |
| `monitoring/` | Prometheus alert rules + Grafana dashboard |
| `scripts/` | deploy, test, seed, reset-consumer-offset |
| `docs/` | ARCHITECTURE, TOPIC-DESIGN, SCHEMA-EVOLUTION, SCALING, TROUBLESHOOTING |

## Key Design Decisions

- **MSK Express**: 20x faster scaling, auto-recovery, no rebalance needed
- **IAM Auth via IRSA**: Pods inherit Kafka permissions from K8s ServiceAccounts — no secrets
- **12 partitions for vehicle.telemetry**: ~830 msg/sec per partition, room to double to 24
- **Data Broker 3-stage**: Anonymizer (PII strip, GPS → 100m grid) → Aggregator (10s windows) → Access Control (per-tenant routing)
- **DLQ**: Schema violations alert registry team, deserialization errors alert engineering, transient errors retry 3x, poison pills alert security

## DR Readiness

The pipeline integrates with the platform's DR framework during deployment and operation:

### Deployment-Time DR Checks

The [`deploy-pipeline.sh`](scripts/deploy-pipeline.sh) and [`test-end-to-end.sh`](scripts/test-end-to-end.sh) scripts perform the following DR checks:

| Check | What It Validates | DR Impact |
|-------|-------------------|-----------|
| Terraform state lock | Verifies no stale locks exist before deploying | Prevents concurrent state mutations |
| Backup accessibility | Confirms backup S3 bucket is reachable | Ensures DR artifacts can be written |
| Consumer lag within RPO | Checks lag doesn't exceed 1m threshold (city-operational RPO) | Validates data loss window is within target |
| Metrics emission | Verifies `BackupAgeSeconds` metric is written to CloudWatch | Ensures backup monitoring is functional |

### RPO Tracking

The pipeline emits consumer lag metrics that feed the DR Readiness dashboard:

```bash
# Check consumer lag against RPO targets
kafka-consumer-groups.sh --bootstrap-server b-1:9098,b-2:9098,b-3:9098 \
  --group agora-data-broker --describe

# Expected lag for city-operational RPO (1 minute max)
# At 10K msg/sec, max acceptable lag ≈ 600,000 messages
```

### Backup CronJob Integration

The data pipeline's S3 sink connectors (Kafka Connect) archive raw data to the data lake. The DR backup CronJob (`terraform-state-backup`) in `city-services` copies Terraform state files to the same backup infrastructure. Both use the `agora-prod-backups` S3 bucket.

## Gotchas

- **MSK IAM port is 9098** (not 9092) — all bootstrap configs use `b-1:9098,b-2:9098,b-3:9098`
- **AVRO schemas** are at `kafka-topics/` and referenced by processors via `../../kafka-topics/`
- **Topic configs** in shell scripts use `&` separator, not newlines
- **Processors run in containers** — each has its own `requirements.txt` and Dockerfile
- **Replication factor is always 3**
- **No test framework** — only the bash `test-end-to-end.sh` integration test
- **Consumer lag > RPO** triggers the `RTOBreachRisk` alert — monitor lag against city-operational RPO of 1 minute

See [`docs/`](docs/) for architecture, topic design, schema evolution, scaling, and troubleshooting.
