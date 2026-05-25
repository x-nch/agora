# anomaly-detector

Kafka Streams processor that reads vehicle telemetry from `vehicle.telemetry`, scores each message for anomalous behavior, and writes results to `incidents` and `alerts.notifications`.

## Scoring

- ML model (`model/anomaly_model.pkl`) — IsolationForest — used when available.
- Heuristic fallback: speed > 120 (+0.3), acceleration > 8g (+0.4), battery < 5% (+0.2), emergency_brake (+0.5), collision_risk (+0.7).
- Threshold: 0.8 (configurable via `ANOMALY_THRESHOLD`).

## Classification

- `unusual_driving` — hard braking or collision risk
- `sensor_failure` — extreme acceleration
- `communication_loss` — low battery + comm loss
- `pattern_deviation` — all other anomalies

## Metrics

Prometheus metrics on port 8000: messages processed, anomalies detected, anomaly scores, processing duration, error counters.
