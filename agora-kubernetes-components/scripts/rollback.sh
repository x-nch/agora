#!/bin/bash
set -euo pipefail

DEPLOYMENT="${1:?Usage: $0 <deployment-name> <namespace>}"
NAMESPACE="${2:-city-services}"

echo "=== Rollback Script ==="
echo "Deployment: $DEPLOYMENT"
echo "Namespace:  $NAMESPACE"
echo ""

# Check that the deployment exists
if ! kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" > /dev/null 2>&1; then
  echo "Error: Deployment '$DEPLOYMENT' not found in namespace '$NAMESPACE'"
  exit 1
fi

# Show revision history
echo "--- Revision history ---"
kubectl rollout history deployment/"$DEPLOYMENT" -n "$NAMESPACE"

echo ""
read -rp "Roll back to which revision? (leave blank for previous): " REVISION

ROLLBACK_ARGS=()
if [ -n "$REVISION" ]; then
  ROLLBACK_ARGS+=(--to-revision="$REVISION")
fi

echo ""
echo "--- Rolling back ---"
kubectl rollout undo deployment/"$DEPLOYMENT" -n "$NAMESPACE" "${ROLLBACK_ARGS[@]}"

echo ""
echo "=== Rollback initiated ==="
echo "Monitor: kubectl rollout status deployment/$DEPLOYMENT -n $NAMESPACE"
