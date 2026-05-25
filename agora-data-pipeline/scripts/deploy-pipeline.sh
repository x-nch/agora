#!/bin/bash
set -euo pipefail

NAMESPACE="city-services"
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

echo "=== Deploying Agora Data Pipeline ==="

# 1. Apply topic definitions
echo "[1/8] Applying Kafka topic definitions..."
kubectl -n "$NAMESPACE" apply -f "$SCRIPT_DIR/iam/service-accounts.yaml"

# 2. Deploy Schema Registry
echo "[2/8] Deploying Schema Registry..."
kubectl -n "$NAMESPACE" apply -f "$SCRIPT_DIR/schema-registry/"

# 3. Deploy Kafka Connect
echo "[3/8] Deploying Kafka Connect..."
kubectl -n "$NAMESPACE" apply -f "$SCRIPT_DIR/kafka-connect/connect-configmap.yaml"
kubectl -n "$NAMESPACE" apply -f "$SCRIPT_DIR/kafka-connect/connect-deployment.yaml"
kubectl -n "$NAMESPACE" apply -f "$SCRIPT_DIR/kafka-connect/connect-service.yaml"
kubectl -n "$NAMESPACE" apply -f "$SCRIPT_DIR/kafka-connect/connect-pdb.yaml"
kubectl -n "$NAMESPACE" apply -f "$SCRIPT_DIR/kafka-connect/connect-hpa.yaml"

# Wait for Schema Registry + Connect to be ready
echo "Waiting for Schema Registry..."
kubectl -n "$NAMESPACE" rollout status deployment/schema-registry --timeout=120s
echo "Waiting for Kafka Connect..."
kubectl -n "$NAMESPACE" rollout status deployment/kafka-connect --timeout=120s

# 4. Apply S3 sink connectors
echo "[4/8] Deploying S3 sink connectors..."
for f in "$SCRIPT_DIR/kafka-connect/connectors/"*.json; do
  name=$(basename "$f" .json)
  echo "  Creating connector: $name"
  curl -X POST http://localhost:8083/connectors \
    -H "Content-Type: application/json" \
    -d @"$f" || echo "  Connector $name may already exist"
done

# 5. Deploy stream processors
echo "[5/8] Deploying stream processors..."
kubectl -n "$NAMESPACE" apply -f "$SCRIPT_DIR/stream-processors/traffic-optimizer/"
kubectl -n "$NAMESPACE" apply -f "$SCRIPT_DIR/stream-processors/anomaly-detector/"
kubectl -n "$NAMESPACE" apply -f "$SCRIPT_DIR/stream-processors/energy-optimizer/"
kubectl -n "$NAMESPACE" apply -f "$SCRIPT_DIR/stream-processors/data-broker/"

# 6. Deploy DLQ processor
echo "[6/8] Deploying DLQ processor..."
kubectl -n "$NAMESPACE" apply -f "$SCRIPT_DIR/dead-letter-queue/"

# 7. Apply client configs
echo "[7/8] Applying client configurations..."
kubectl -n "$NAMESPACE" apply -f "$SCRIPT_DIR/client-configs/"

# 8. Apply monitoring
echo "[8/8] Applying monitoring rules..."
kubectl -n "$NAMESPACE" apply -f "$SCRIPT_DIR/monitoring/"

# 9. DR readiness check
echo "[9/9] Running DR readiness checks..."
echo "  Checking Terraform state lock..."
LOCK_COUNT=$(aws dynamodb scan \
  --table-name terraform-lock \
  --region ap-northeast-1 \
  --query "length(Items)" \
  --output text 2>/dev/null || echo "0")
if [[ "$LOCK_COUNT" -gt 0 ]]; then
  echo "  WARNING: ${LOCK_COUNT} active Terraform lock(s) found"
else
  echo "  No active locks — OK"
fi

echo "  Checking backup S3 bucket..."
if aws s3 ls s3://agora-prod-backups/ --region ap-northeast-1 > /dev/null 2>&1; then
  echo "  Backup bucket accessible — OK"
else
  echo "  WARNING: Backup bucket not accessible"
fi

echo "=== Pipeline deployment complete ==="
echo ""
echo "Verify with:"
echo "  kubectl -n $NAMESPACE get pods"
echo "  kubectl -n $NAMESPACE get deployments"
