# IAM Auth Integration

IRSA (IAM Roles for Service Accounts) integration for MSK IAM Access Control.

## Architecture

```
Pod → K8s ServiceAccount (IRSA annotation) → IAM Role → MSK IAM Auth → Kafka
```

## Per-Service Permissions

| Service | IAM Role | Permissions |
|---|---|---|
| traffic-optimizer | TrafficOptimizerMSKRole | Read: vehicle.telemetry, signal.events. Write: signal.commands, incidents |
| anomaly-detector | AnomalyDetectorMSKRole | Read: vehicle.telemetry. Write: incidents, alerts.notifications |
| energy-optimizer | EnergyOptimizerMSKRole | Read: sensor.environmental. Write: alerts.notifications |
| data-broker | DataBrokerMSKRole | Read: all raw. Write: data.anonymized.vehicle, data.inventor.traffic |
| kafka-connect | KafkaConnectMSKRole | Read: all raw topics. Write: S3 (via VPC endpoint) |
| schema-registry | SchemaRegistryMSKRole | Read/Write: _schemas topic |
| dlq-processor | DLQProcessorMSKRole | Read: dlq.all. Write: alerts.notifications |

## Apply

```bash
kubectl apply -f service-accounts.yaml
```
