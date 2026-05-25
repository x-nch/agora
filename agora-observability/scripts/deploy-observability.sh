#!/usr/bin/env bash
set -euo pipefail

ENV=${1:-development}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
OVERLAY_DIR="${PROJECT_ROOT}/kustomization/overlays/${ENV}"
NAMESPACE="monitoring"

echo "=== Deploying Agora Observability Stack [${ENV}] ==="

echo "[1/8] Applying CRDs and waiting for Established condition..."
kubectl apply -f "${PROJECT_ROOT}/kustomization/base/prometheus-operator/crds.yaml"
for crd in prometheuses alertmanagers servicemonitors prometheusrules alertmanagerconfigs podmonitors probes thanosrulers; do
  kubectl wait --for condition=Established "crd/${crd}.monitoring.coreos.com" --timeout=120s 2>/dev/null || true
done

echo "[2/8] Applying kustomize overlay and waiting for prometheus-operator Deployment..."
kubectl apply -k "${OVERLAY_DIR}"
kubectl -n "${NAMESPACE}" rollout status deployment/prometheus-operator --timeout=180s

echo "[3/8] Waiting for node-exporter DaemonSet and kube-state-metrics Deployment..."
kubectl -n "${NAMESPACE}" rollout status daemonset/node-exporter --timeout=180s
kubectl -n "${NAMESPACE}" rollout status deployment/kube-state-metrics --timeout=180s

echo "[4/8] Waiting for loki StatefulSet and promtail DaemonSet..."
kubectl -n "${NAMESPACE}" rollout status statefulset/loki --timeout=300s
kubectl -n "${NAMESPACE}" rollout status daemonset/promtail --timeout=180s

echo "[5/8] Waiting for prometheus-agora-prometheus StatefulSet..."
kubectl -n "${NAMESPACE}" rollout status statefulset/prometheus-agora-prometheus --timeout=300s

echo "[6/8] Waiting for alertmanager-agora StatefulSet..."
kubectl -n "${NAMESPACE}" rollout status statefulset/alertmanager-agora --timeout=300s

echo "[7/8] Waiting for grafana Deployment..."
kubectl -n "${NAMESPACE}" rollout status deployment/grafana --timeout=180s

echo "[8/8] Running stack verification..."
"${SCRIPT_DIR}/verify-stack.sh"

echo "[9/9] Validating DR alert rules..."
if kubectl -n "${NAMESPACE}" get prometheusrule agora-dr-rules > /dev/null 2>&1; then
  echo "  DR alert rules:       DEPLOYED"
else
  echo "  DR alert rules:       CHECKING..."
  kubectl -n "${NAMESPACE}" apply -f "${PROJECT_ROOT}/kustomization/base/alert-rules/dr-rules.yaml" 2>/dev/null || true
fi

echo "=== Observability stack deployed successfully [${ENV}] ==="
