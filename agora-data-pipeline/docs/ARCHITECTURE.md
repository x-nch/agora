# Architecture

## Overview

The Agora data pipeline ingests 60K+ events/sec from city IoT devices through Amazon MSK Express and processes them through Kafka Streams processors for traffic optimization, anomaly detection, energy management, and data brokering.

## Data Flow

```
IoT Gateways
    │
    ▼
┌──────────────────────────────────────────────────────────┐
│                   Amazon MSK Express                      │
│  3 × m7g.large brokers  │  IAM Auth  │  Auto-recovery    │
│                                                          │
│  vehicle.telemetry (12p)  signal.events (6p)             │
│  sensor.environmental (6p)  incidents (1p)               │
└──────────────────────────┬───────────────────────────────┘
                           │
          ┌────────────────┼────────────────┬────────────────┐
          ▼                ▼                ▼                ▼
   traffic-optimizer  anomaly-detector  energy-optimizer  data-broker
   (3-10 pods)        (2-8 pods)        (2-6 pods)        (5-20 pods)
          │                │                │                │
          ▼                ▼                ▼                ▼
   signal.commands    incidents         alerts          data.anonymized
   incidents          alerts.notif.     notifications    data.inventor
                                                    ────────────────
                                                           │
                                                           ▼
                                                     S3 Data Lake
                                              (Kafka Connect S3 Sink)
```

## Topics

| Topic | Partitions | Throughput | Key |
|---|---|---|---|
| vehicle.telemetry | 12 | 10K msg/s | vehicle_type |
| sensor.environmental | 6 | 5K msg/s | district |
| signal.events | 6 | 2K msg/s | intersection_id |
| incidents | 1 | 100 msg/s | N/A |
| signal.commands | 6 | 1K msg/s | intersection_id |
| data.anonymized.vehicle | 12 | 10K msg/s | district |
| data.inventor.traffic | 3 | 500 msg/s | inventor_id |
| alerts.notifications | 1 | 50 msg/s | N/A |
| dlq.all | 1 | 10 msg/s | N/A |

## Security

- Pod authentication via IRSA (IAM Roles for Service Accounts)
- MSK IAM Access Control (no mTLS secrets to manage)
- Per-service IAM policies with least privilege
- Data broker enforces multi-tenancy access control

## Resilience

- PodDisruptionBudgets on all critical services
- HPA based on CPU + consumer lag
- Dead letter queue catches processing failures
- MSK Express auto-recovery within 90% faster than provisioned
- Multiple replicas per processor (3-5 minimum)
