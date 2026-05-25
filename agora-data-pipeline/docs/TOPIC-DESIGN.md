# Topic Design

## Partitioning Rationale

### vehicle.telemetry (12 partitions)
- 10K msg/sec ≈ 10 MBps
- Partition key: vehicle_type (autonomous, regular, emergency)
- 12 partitions × ~830 msg/sec/partition = well under limits
- Room to double to 24 with alter command

### sensor.environmental (6 partitions)
- 5K msg/sec
- Partition key: district (mobility, living, working, wellness, innovation)
- 6 partitions for 5 districts + 1 spare

### signal.events (6 partitions)
- 2K msg/sec
- Partition key: intersection_id
- 6 partitions = max parallel consumers

### incidents (1 partition)
- 100 msg/sec, ordering matters
- Single partition guarantees FIFO ordering

## Retention

| Topic | Retention | Rationale |
|---|---|---|
| vehicle.telemetry | 7 days → S3 | Raw data archived, compacted for latest state |
| sensor.environmental | 7 days → S3 | Historical trends via S3 |
| signal.events | 7 days → S3 | Archival needed for traffic analysis |
| incidents | 30 days | Longer retention for forensic analysis |
| signal.commands | 2 days | Transient commands, no archival needed |
| data.anonymized.vehicle | 30 days | City services need longer access |
| alerts.notifications | 90 days | Audit trail requirements |
| dlq.all | 30 days | Time to investigate failures |
