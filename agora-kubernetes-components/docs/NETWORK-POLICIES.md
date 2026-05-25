# Network Policies

## Overview

Network policies enforce micro-segmentation across the Agora platform. The strategy is **default-deny** with explicit allow rules: no traffic is permitted unless a policy explicitly allows it.

## Policy Hierarchy

```
default-deny-all (all namespaces)
    │
    ├── allow-city-services-internal
    │       ├── Internal traffic within city-services
    │       └── Egress to monitoring (prometheus:9090)
    │
    ├── allow-inventors-internal
    │       ├── Internal traffic within inventors
    │       └── Egress to api-gateway (city-services:8080)
    │
    ├── allow-monitoring-scraping
    │       ├── Ingress from any namespace on :9090 & :3000
    │       └── Egress to any namespace on :9090 (scraping)
    │
    └── allow-ingress-controller + allow-api-gateway-to-services
            ├── Ingress from ALB controller (kube-system) to api-gateway
            └── Egress from api-gateway to traffic-optimizer & energy-management
```

## Per-Namespace Rules

### city-services

| Policy | Direction | Allowed |
|--------|-----------|---------|
| default-deny-all | Both | Nothing by default |
| allow-city-services-internal | Ingress | From any pod in city-services |
| allow-city-services-internal | Egress | To city-services, and to prometheus:9090 |
| allow-ingress-controller | Ingress | From kube-system/ALB controller to api-gateway:8080,8443 |
| allow-api-gateway-to-services | Egress | To traffic-optimizer:8080, energy-management:8080 |
| api-gateway-specific | Both | Ingress from kube-system; egress to all services |
| allow-api-gateway-to-services | Egress | api-gateway → traffic-optimizer, energy-management |

### inventors

| Policy | Direction | Allowed |
|--------|-----------|---------|
| default-deny-all | Both | Nothing by default |
| allow-inventors-internal | Ingress | From any pod in inventors |
| allow-inventors-internal | Egress | To inventors, and to api-gateway:8080 |

### monitoring

| Policy | Direction | Allowed |
|--------|-----------|---------|
| default-deny-all | Both | Nothing by default |
| allow-monitoring-scraping | Ingress | From any namespace on :9090 (Prometheus UI) and :3000 (Grafana UI) |
| allow-monitoring-scraping | Egress | To any namespace on :9090 (pulling metrics) and :10250 (kubelet) |

## MSK (Kafka) Access

- **data-broker** connects to Amazon MSK on port 9098
- This egress is permitted by `allow-city-services-internal` which allows egress to external IPs (0.0.0.0/0 except private ranges) on ports 443 and 80
- Since MSK typically uses a private endpoint within the VPC, the egress to private IPs would need a specific rule. For MSK in the same VPC, add:
  ```yaml
  - to:
      - ipBlock:
          cidr: 10.0.0.0/8    # VPC CIDR (adjust as needed)
    ports:
      - port: 9098
        protocol: TCP
  ```
- **inventors cannot reach Kafka** because their egress rules do not include port 9098 and their external egress is limited to 80/443 only.

## Troubleshooting Network Policies

```bash
# Check if a pod can reach another pod
kubectl run test-pod --image=busybox -it --rm -- wget -O- http://target-service:8080

# View network policies in a namespace
kubectl get networkpolicies -n city-services -o wide

# Describe a specific policy
kubectl describe networkpolicy allow-city-services-internal -n city-services
```
