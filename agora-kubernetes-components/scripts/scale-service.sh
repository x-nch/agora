#!/bin/bash
set -euo pipefail

SERVICE="${1:?Usage: $0 <service-name> <replicas> [namespace]}"
REPLICAS="${2:?Usage: $0 <service-name> <replicas> [namespace]}"
NAMESPACE="${3:-city-services}"

echo "=== Scale Service ==="
echo "Service:   $SERVICE"
echo "Replicas:  $REPLICAS"
echo "Namespace: $NAMESPACE"
echo ""

if ! kubectl get deployment "$SERVICE" -n "$NAMESPACE" > /dev/null 2>&1; then
  echo "Error: Deployment '$SERVICE' not found in namespace '$NAMESPACE'"
  exit 1
fi

if ! [[ "$REPLICAS" =~ ^[0-9]+$ ]]; then
  echo "Error: Replicas must be a positive integer"
  exit 1
fi

kubectl scale deployment/"$SERVICE" --replicas="$REPLICAS" -n "$NAMESPACE"

echo "--- Waiting for rollout ---"
kubectl rollout status deployment/"$SERVICE" -n "$NAMESPACE" --timeout=120s

echo ""
echo "=== Service scaled successfully ==="
