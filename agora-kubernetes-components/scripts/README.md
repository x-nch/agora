# Management Scripts

## Overview

Shell scripts for deploying and managing the Agora Kubernetes platform. All scripts are designed to be run from the `scripts/` directory.

## Scripts

### deploy.sh

Deploys Agora manifests to a Kubernetes cluster using Kustomize overlays.

```bash
./deploy.sh [environment] [kubeconfig-path]
# environment: development (default), staging, or production
```

1. Validates manifests with `--dry-run=client`
2. Applies manifests with `kubectl apply -k`

### validate.sh

Validates all Kustomize overlays (base, development, staging, production) and checks RBAC permissions.

```bash
./validate.sh
```

Uses `kubectl apply --dry-run=client` to validate every manifest compiles correctly without applying.

### rollback.sh

Rolls back a deployment to a previous revision.

```bash
./rollback.sh <deployment-name> [namespace]
# namespace defaults to city-services
```

1. Shows revision history
2. Prompts for target revision (blank = previous)
3. Runs `kubectl rollout undo`

### scale-service.sh

Scales a deployment to the specified replica count.

```bash
./scale-service.sh <service-name> <replicas> [namespace]
# namespace defaults to city-services
```

1. Validates the deployment exists and replicas is a positive integer
2. Runs `kubectl scale deployment`
3. Waits for rollout to complete (120s timeout)
