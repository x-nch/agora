# Energy Optimizer Stream Processor

Kafka Streams processor that reads environmental sensor data and building
energy metrics, then emits HVAC pre-cooling commands, solar curtailment
optimizations, and critical-energy alerts to downstream topics.

## Topics

| Direction | Topic                          | Schema              |
|-----------|--------------------------------|---------------------|
| Consume   | `sensor.environmental`         | AVRO (Schema Reg)   |
| Consume   | `building_energy`              | AVRO (Schema Reg)   |
| Produce   | `energy.commands`              | AVRO (Schema Reg)   |
| Produce   | `alerts.notifications`         | AVRO (Schema Reg)   |

## Logic

- **Temperature-drop prediction** – linear regression over recent weather
  readings; triggers HVAC pre-cooling when drop rate exceeds -0.5 °C/h.
- **Solar load curtailment** – sheds 15 % of load (capped at 50 kW) when
  consumption > 1 kW.
- **Critical alert** – fires at > 5 kW instantaneous consumption.

## Auth

MSK IAM via SASL_SSL.  Schema Registry at `SCHEMA_REGISTRY_URL`.

## Deploy

```bash
kubectl apply -f configmap.yaml
kubectl apply -f deployment.yaml
kubectl apply -f hpa.yaml
kubectl apply -f pdb.yaml
kubectl apply -f servicemonitor.yaml
```
