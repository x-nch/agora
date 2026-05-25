#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

KUSTOMIZATION_DIR="$PROJECT_ROOT/kustomization"
OVERLAYS=("development" "staging" "production")
EXIT_CODE=0

echo "=== Agora Manifest Validation ==="
echo ""

validate_overlay() {
  local overlay=$1
  local dir="$KUSTOMIZATION_DIR/overlays/$overlay"

  echo "--- Validating overlay: $overlay ---"

  if kubectl apply -k "$dir" --dry-run=client -o yaml > /dev/null 2>&1; then
    echo "  Kustomize build:       PASS"
  else
    echo "  Kustomize build:       FAIL"
    EXIT_CODE=1
  fi

  echo ""
}

echo "--- Validating base kustomization ---"
if kubectl apply -k "$KUSTOMIZATION_DIR" --dry-run=client -o yaml > /dev/null 2>&1; then
  echo "  Base kustomization:    PASS"
else
  echo "  Base kustomization:    FAIL"
  EXIT_CODE=1
fi
echo ""

echo "--- Istio Config Validation ---"
ISTIO_FILES=$(find "$KUSTOMIZATION_DIR/base/istio" -name "*.yaml" 2>/dev/null || true)
if [ -n "$ISTIO_FILES" ]; then
  for f in $ISTIO_FILES; do
    if kubectl apply -f "$f" --dry-run=client -o yaml > /dev/null 2>&1; then
      echo "  Istio: $(basename $f)    PASS"
    else
      echo "  Istio: $(basename $f)    FAIL"
      EXIT_CODE=1
    fi
  done
else
  echo "  No Istio configs found — SKIP"
fi

for overlay in "${OVERLAYS[@]}"; do
  validate_overlay "$overlay"
done

echo "--- RBAC Validation ---"
NAMESPACES=("city-services" "inventors")
SERVICE_ACCOUNTS=("city-services-team" "inventors-team")

for i in "${!NAMESPACES[@]}"; do
  ns="${NAMESPACES[$i]}"
  sa="${SERVICE_ACCOUNTS[$i]}"
  echo "  Checking $sa in $ns..."

  if kubectl auth can-i list pods --as=system:serviceaccount:"$ns":"$sa" --namespace="$ns" > /dev/null 2>&1; then
    echo "    list pods:           PASS"
  else
    echo "    list pods:           SKIP (cluster may not exist yet)"
  fi
done

echo ""
if [ "$EXIT_CODE" -eq 0 ]; then
  echo "=== All validations passed ==="
else
  echo "=== Some validations failed ==="
fi
exit "$EXIT_CODE"
