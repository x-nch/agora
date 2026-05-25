# Helm Chart: agora-services

## Overview

The `agora-services` Helm chart packages the four core Agora microservices (traffic-optimizer, energy-management, data-broker, api-gateway) as a single deployable unit. This provides an alternative to Kustomize for teams that prefer Helm-based deployments.

## Values

| Parameter | Default | Description |
|-----------|---------|-------------|
| `global.namespace` | `city-services` | Target namespace |
| `trafficOptimizer.replicas` | `3` | Number of traffic-optimizer pods |
| `trafficOptimizer.image` | `agora/traffic-optimizer:v1.0.0` | Container image |
| `trafficOptimizer.resources.requests.cpu` | `500m` | CPU request |
| `trafficOptimizer.resources.requests.memory` | `512Mi` | Memory request |
| `trafficOptimizer.resources.limits.cpu` | `1000m` | CPU limit |
| `trafficOptimizer.resources.limits.memory` | `1Gi` | Memory limit |
| `energyManagement.replicas` | `2` | Number of energy-management pods |
| `energyManagement.image` | `agora/energy-management:v1.0.0` | Container image |
| `energyManagement.resources.requests.cpu` | `300m` | CPU request |
| `energyManagement.resources.requests.memory` | `384Mi` | Memory request |
| `energyManagement.resources.limits.cpu` | `700m` | CPU limit |
| `energyManagement.resources.limits.memory` | `768Mi` | Memory limit |
| `dataBroker.replicas` | `5` | Number of data-broker pods |
| `dataBroker.image` | `agora/data-broker:v1.0.0` | Container image |
| `dataBroker.resources.requests.cpu` | `2` | CPU request |
| `dataBroker.resources.requests.memory` | `2Gi` | Memory request |
| `dataBroker.resources.limits.cpu` | `4` | CPU limit |
| `dataBroker.resources.limits.memory` | `4Gi` | Memory limit |
| `apiGateway.replicas` | `5` | Number of api-gateway pods |
| `apiGateway.image` | `agora/api-gateway:v1.0.0` | Container image |
| `apiGateway.resources.requests.cpu` | `500m` | CPU request |
| `apiGateway.resources.requests.memory` | `512Mi` | Memory request |
| `apiGateway.resources.limits.cpu` | `1000m` | CPU limit |
| `apiGateway.resources.limits.memory` | `1Gi` | Memory limit |

## Usage

```bash
# Install default values
helm install agora-services ./agora-services --namespace city-services

# Override replicas for a specific environment
helm install agora-services ./agora-services \
  --namespace city-services \
  --set trafficOptimizer.replicas=5 \
  --set dataBroker.replicas=5

# Upgrade an existing release
helm upgrade agora-services ./agora-services \
  --namespace city-services \
  --set apiGateway.replicas=5
```

## Template Directory

The `templates/` directory is where Go template YAML files should be placed to render the Kubernetes manifests. Template files use Helm's built-in functions and values from `values.yaml` and `global` values.
