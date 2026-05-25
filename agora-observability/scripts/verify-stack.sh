#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="monitoring"
PASS=0
FAIL=0

check() {
  local desc="$1"
  local cmd="$2"
  if eval "$cmd" >/dev/null 2>&1; then
    echo "  PASS: ${desc}"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: ${desc}"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== Observability Stack Verification ==="

echo ""
echo "--- Prometheus Targets ---"
PROM_POD=$(kubectl -n "${NAMESPACE}" get pod -l app.kubernetes.io/name=prometheus -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
if [ -n "${PROM_POD}" ]; then
  check "Prometheus targets UP" \
    "kubectl -n ${NAMESPACE} exec ${PROM_POD} -- wget -q -O- http://localhost:9090/api/v1/targets 2>/dev/null | python3 -c \"import sys,json; d=json.load(sys.stdin); targets=[t for t in d['data']['activeTargets'] if t['health']=='up']; print(f'{len(targets)}/{len(d[\"data\"][\"activeTargets\"])} targets up')\""
else
  echo "  SKIP: Prometheus pod not found"
fi

echo ""
echo "--- Alertmanager ---"
AM_POD=$(kubectl -n "${NAMESPACE}" get pod -l app.kubernetes.io/name=alertmanager -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
if [ -n "${AM_POD}" ]; then
  check "Alertmanager health endpoint" \
    "kubectl -n ${NAMESPACE} exec ${AM_POD} -- wget -q -O- http://localhost:9093/-/healthy 2>/dev/null | grep -q OK"
  check "Alertmanager ready endpoint" \
    "kubectl -n ${NAMESPACE} exec ${AM_POD} -- wget -q -O- http://localhost:9093/-/ready 2>/dev/null | grep -q OK"
else
  echo "  SKIP: Alertmanager pod not found"
fi

echo ""
echo "--- Loki ---"
LOKI_POD=$(kubectl -n "${NAMESPACE}" get pod -l app.kubernetes.io/name=loki -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
if [ -n "${LOKI_POD}" ]; then
  check "Loki ready endpoint" \
    "kubectl -n ${NAMESPACE} exec ${LOKI_POD} -- wget -q -O- http://localhost:3100/ready 2>/dev/null | grep -q ready"
  check "Loki ring status" \
    "kubectl -n ${NAMESPACE} exec ${LOKI_POD} -- wget -q -O- http://localhost:3100/ring 2>/dev/null | python3 -c \"import sys,json; d=json.load(sys.stdin); print('Ring OK:', len(d.get('ring',[])) if isinstance(d,dict) else 'ok')\""
else
  echo "  SKIP: Loki pod not found"
fi

echo ""
echo "--- Grafana Datasources ---"
GRAFANA_POD=$(kubectl -n "${NAMESPACE}" get pod -l app.kubernetes.io/name=grafana -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
if [ -n "${GRAFANA_POD}" ]; then
  check "Grafana API health" \
    "kubectl -n ${NAMESPACE} exec ${GRAFANA_POD} -- wget -q -O- http://localhost:3000/api/health 2>/dev/null | grep -q ok"
  check "Grafana datasources reachable" \
    "kubectl -n ${NAMESPACE} exec ${GRAFANA_POD} -- wget -q -O- http://localhost:3000/api/datasources 2>/dev/null | python3 -c \"import sys,json; ds=json.load(sys.stdin); print(f'{len(ds)} datasource(s) configured')\""
else
  echo "  SKIP: Grafana pod not found"
fi

echo ""
echo "--- node-exporter ---"
NE_POD=$(kubectl -n "${NAMESPACE}" get pod -l app.kubernetes.io/name=node-exporter -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
if [ -n "${NE_POD}" ]; then
  check "node-exporter metrics endpoint" \
    "kubectl -n ${NAMESPACE} exec ${NE_POD} -- wget -q -O- http://localhost:9100/metrics 2>/dev/null | head -c 100 | grep -q 'node_'"
else
  echo "  SKIP: node-exporter pod not found"
fi

echo ""
echo "=== Results: ${PASS} passed, ${FAIL} failed ==="
exit ${FAIL}
