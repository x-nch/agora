# Traffic Optimizer

Reads from `vehicle.telemetry` and `signal.events`, writes optimized signal commands to `signal.commands` and incidents to `incidents`.

## Processing Logic

- 5-second sliding window per intersection
- Average speed + queue length analysis
- Extends green phase when queue > 50 and speed < 5 km/h
- Reduces green phase when queue < 5 vehicles
- Detects near-collisions via speed deltas > 30 km/h within 2s window

## SLO
< 100ms end-to-end latency
