#!/bin/bash
set -euo pipefail

ENVIRONMENT="${1:-development}"
KUBECONFIG="${2:-$KUBECONFIG}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

OVERLAY_DIR="$PROJECT_ROOT/kustomization/overlays/$ENVIRONMENT"

if [ ! -d "$OVERLAY_DIR" ]; then
  echo "Error: Environment '$ENVIRONMENT' not found at $OVERLAY_DIR"
  echo "Valid environments: development, staging, production"
  exit 1
fi

echo "=== Agora Deploy Script ==="
echo "Environment: $ENVIRONMENT"
echo "Overlay:     $OVERLAY_DIR"
echo ""

if [ -n "${KUBECONFIG:-}" ]; then
  echo "Using KUBECONFIG: $KUBECONFIG"
  export KUBECONFIG
fi

echo "--- Dry run validation ---"
kubectl apply -k "$OVERLAY_DIR" --dry-run=client -o yaml > /dev/null
echo "Validation passed."

echo ""
echo "--- Deploying manifests ---"
kubectl apply -k "$OVERLAY_DIR"

echo ""
echo "--- Post-deploy DR checks ---"
echo "Checking namespace istio-injection labels..."
for ns in city-services inventors monitoring; do
  LABEL=$(kubectl get ns "$ns" -o jsonpath="{.metadata.labels.istio-injection}" 2>/dev/null || echo "missing")
  echo "  $ns: istio-injection=$LABEL"
done

echo "Checking PDBs for critical services..."
for deploy in api-gateway data-broker traffic-optimizer energy-management; do
  PDB=$(kubectl -n city-services get pdb "$deploy" -o name 2>/dev/null || echo "missing")
  echo "  $deploy: $PDB"
done

echo ""
echo "=== Deployment complete ==="
echo "Monitor rollout: kubectl -n city-services get pods -w"
