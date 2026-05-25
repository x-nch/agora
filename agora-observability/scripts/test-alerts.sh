#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="monitoring"

AM_POD=$(kubectl -n "${NAMESPACE}" get pod -l app.kubernetes.io/name=alertmanager -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -z "${AM_POD}" ]; then
  echo "ERROR: Alertmanager pod not found in namespace ${NAMESPACE}"
  exit 1
fi

echo "=== Firing test alerts to Alertmanager ==="

echo ""
echo "--- Critical Test Alert ---"
kubectl -n "${NAMESPACE}" exec "${AM_POD}" -- sh -c '
cat <<AMEOF | curl -s -XPOST -H "Content-Type: application/json" --data-binary @- http://localhost:9093/api/v2/alerts
[
  {
    "labels": {
      "alertname": "TestCriticalAlert",
      "severity": "critical",
      "instance": "test-node-01",
      "job": "test-job",
      "namespace": "city-services"
    },
    "annotations": {
      "summary": "This is a test critical alert",
      "description": "A manually fired test critical alert to verify Alertmanager routing to PagerDuty",
      "runbook": "https://github.com/anomalyco/agora/docs/observability/RUNBOOKS.md"
    },
    "generatorURL": "http://localhost:9090/graph?g0.expr=test_alert",
    "startsAt": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"
  }
]
AMEOF
'
echo "Critical alert sent."

echo ""
echo "--- Warning Test Alert ---"
kubectl -n "${NAMESPACE}" exec "${AM_POD}" -- sh -c '
cat <<AMEOF | curl -s -XPOST -H "Content-Type: application/json" --data-binary @- http://localhost:9093/api/v2/alerts
[
  {
    "labels": {
      "alertname": "TestWarningAlert",
      "severity": "warning",
      "instance": "test-node-01",
      "job": "test-job",
      "namespace": "city-services"
    },
    "annotations": {
      "summary": "This is a test warning alert",
      "description": "A manually fired test warning alert to verify Alertmanager routing to Slack",
      "runbook": "https://github.com/anomalyco/agora/docs/observability/RUNBOOKS.md"
    },
    "generatorURL": "http://localhost:9090/graph?g0.expr=test_alert",
    "startsAt": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"
  }
]
AMEOF
'
echo "Warning alert sent."

echo ""
echo "--- Info Test Alert ---"
kubectl -n "${NAMESPACE}" exec "${AM_POD}" -- sh -c '
cat <<AMEOF | curl -s -XPOST -H "Content-Type: application/json" --data-binary @- http://localhost:9093/api/v2/alerts
[
  {
    "labels": {
      "alertname": "TestInfoAlert",
      "severity": "info",
      "instance": "test-node-01",
      "job": "test-job",
      "namespace": "city-services"
    },
    "annotations": {
      "summary": "This is a test info alert",
      "description": "A manually fired test info alert to verify null/blackhole routing"
    },
    "generatorURL": "http://localhost:9090/graph?g0.expr=test_alert",
    "startsAt": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"
  }
]
AMEOF
'
echo "Info alert sent."

echo ""
echo "=== To view active alerts, run: ==="
echo "  kubectl -n ${NAMESPACE} exec ${AM_POD} -- curl -s http://localhost:9093/api/v2/alerts | python3 -m json.tool"
echo ""
echo "=== Test alerts fired successfully ==="
