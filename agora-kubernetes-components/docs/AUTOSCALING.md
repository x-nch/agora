# Autoscaling

## Overview

Horizontal Pod Autoscalers (HPAs) adjust replica counts based on real-time CPU and memory utilization. Each service has tuned thresholds, scaling policies, and stabilization windows to match its workload pattern.

## HPA Configuration

### traffic-optimizer

| Setting | Value |
|---------|-------|
| Min replicas | 2 |
| Max replicas | 10 |
| CPU target | 70% |
| Memory target | 80% |
| Scale-up stabilization | 60s |
| Scale-up policy | +2 pods per 60s or +100% per 60s (whichever is more) |
| Scale-down stabilization | 300s |
| Scale-down policy | -1 pod per 120s |

### energy-management

| Setting | Value |
|---------|-------|
| Min replicas | 2 |
| Max replicas | 8 |
| CPU target | 75% |
| Memory target | 80% |
| Scale-up stabilization | 60s |
| Scale-up policy | +1 pod per 60s |
| Scale-down stabilization | 300s |
| Scale-down policy | -1 pod per 120s |

### data-broker

| Setting | Value |
|---------|-------|
| Min replicas | 3 |
| Max replicas | 15 |
| CPU target | 65% |
| Memory target | 75% |
| Scale-up stabilization | 60s |
| Scale-up policy | +2 pods per 60s or +100% per 60s (whichever is more) |
| Scale-down stabilization | 300s |
| Scale-down policy | -1 pod per 120s |

### api-gateway

| Setting | Value |
|---------|-------|
| Min replicas | 3 |
| Max replicas | 10 |
| CPU target | 70% |
| Memory target | 80% |
| Scale-up stabilization | 60s |
| Scale-up policy | +2 pods per 60s or +100% per 60s (whichever is more) |
| Scale-down stabilization | 300s |
| Scale-down policy | -1 pod per 120s |

## Design Decisions

### Stabilization Windows
- **Scale-down (300s)**: Long window prevents thrashing from transient metric dips. A 5-minute cool-down ensures the HPA doesn't rapidly scale down after a traffic spike passes.
- **Scale-up (60s)**: Short window allows quick reaction to increased load.

### Scaling Policies
- **Aggressive scale-up**: Both pods-based and percent-based policies are used, with `selectPolicy: Max`. This means if you have 10 pods and all are at 90% CPU, the HPA can add 10 more pods (100% of current) in a single step.
- **Conservative scale-down**: Only one pod at a time every 2 minutes. This prevents over-reaction during fluctuating traffic.

### Metric Selection
- **CPU utilization**: Primary metric for all services. Most microservices' throughput correlates with CPU usage.
- **Memory utilization**: Secondary metric to catch memory leak scenarios. If memory grows without corresponding CPU increase, the HPA still scales.

## Pod Anti-Affinity

In production, traffic-optimizer uses **required** pod anti-affinity (hard constraint), ensuring pods are scheduled on different availability zone nodes. All other environments use **preferred** anti-affinity (soft constraint).

## Viewing HPA Status

```bash
# Check all HPAs
kubectl get hpa -n city-services

# Detailed view
kubectl describe hpa traffic-optimizer -n city-services

# Watch metrics
kubectl get hpa -n city-services -w
```
