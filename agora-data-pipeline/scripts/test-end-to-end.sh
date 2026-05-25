#!/bin/bash
set -euo pipefail

NAMESPACE="city-services"
BOOTSTRAP_SERVERS="${1:-b-1:9098,b-2:9098,b-3:9098}"

echo "=== End-to-End Pipeline Test ==="
PASS=0
FAIL=0

check() {
  local desc="$1"
  local result="$2"
  if [ "$result" -eq 0 ]; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc"
    FAIL=$((FAIL + 1))
  fi
}

# 1. Seed test data
echo "[1/8] Seeding test data..."
kafka-console-producer --bootstrap-server "$BOOTSTRAP_SERVERS" \
  --topic vehicle.telemetry \
  --property "parse.key=true" \
  --property "key.separator=:" <<'EOF'
test-vehicle-1:{"vehicle_id":"test-001","vehicle_type":"autonomous","timestamp":1715000000000,"gps_lat":35.123,"gps_lng":140.456,"speed_kmh":45.0,"heading_degrees":90.0,"acceleration_x":0.1,"acceleration_y":0.0,"acceleration_z":-0.1,"battery_level":85.0,"occupancy":2,"district":"mobility","event_type":"periodic"}
EOF
check "Seed test data" $?

# 2. Wait for processing
echo "[2/8] Waiting 10s for processing..."
sleep 10
check "Wait for processing" $?

# 3. Check signal.commands topic
echo "[3/8] Verifying traffic optimizer output..."
kafka-console-consumer --bootstrap-server "$BOOTSTRAP_SERVERS" \
  --topic signal.commands \
  --from-beginning \
  --max-messages 1 \
  --timeout-ms 10000 > /dev/null 2>&1
check "Traffic optimizer produced commands" $?

# 4. Check incidents topic (expect no false positives for normal data)
echo "[4/8] Verifying no false positive incidents..."
INCIDENTS=$(kafka-console-consumer --bootstrap-server "$BOOTSTRAP_SERVERS" \
  --topic incidents \
  --from-beginning \
  --max-messages 1 \
  --timeout-ms 5000 2>/dev/null | wc -l)
check "No anomalous incidents from normal data" $((INCIDENTS == 0 ? 0 : 1))

# 5. Check S3 data lake
echo "[5/8] Verifying S3 archival..."
aws s3 ls s3://agora-prod-data-lake/raw/vehicle.telemetry/ --region ap-northeast-1 > /dev/null 2>&1
check "Kafka Connect archived to S3" $?

# 6. Check data-broker anonymization
echo "[6/8] Verifying data broker output..."
kafka-console-consumer --bootstrap-server "$BOOTSTRAP_SERVERS" \
  --topic data.anonymized.vehicle \
  --from-beginning \
  --max-messages 1 \
  --timeout-ms 10000 > /dev/null 2>&1
check "Data broker produced anonymized data" $?

# 7. Check consumer lag
echo "[7/8] Verifying consumer lag..."
docker run --rm bitnami/kafka:3.6 kafka-consumer-groups.sh \
  --bootstrap-server "$BOOTSTRAP_SERVERS" \
  --group traffic-optimizer-group \
  --describe 2>/dev/null | awk 'NR>1 {lag+=$NF} END {if (lag < 100) exit 0; else exit 1}'
check "Consumer lag < 100" $?

# 7b. DR readiness: check lag within RPO
echo "[7b/8] DR readiness: consumer lag within RPO..."
LAG=$(docker run --rm bitnami/kafka:3.6 kafka-consumer-groups.sh \
  --bootstrap-server "$BOOTSTRAP_SERVERS" \
  --group traffic-optimizer-group \
  --describe 2>/dev/null | awk 'NR>1 {lag+=$NF} END {print lag}')
if [[ "$LAG" -lt 1000 ]]; then
  check "Consumer lag within RPO (< 1000)" 0
else
  check "Consumer lag within RPO (< 1000)" 1
fi

# 7c. DR readiness: verify Terraform state backup exists
echo "[7c/8] DR readiness: Terraform state backup exists..."
BACKUP_COUNT=$(aws s3 ls s3://agora-prod-backups/terraform-state-backups/production/ \
  --region ap-northeast-1 2>/dev/null | wc -l)
if [[ "$BACKUP_COUNT" -gt 0 ]]; then
  check "State backup exists (${BACKUP_COUNT} backup(s))" 0
else
  check "State backup exists" 1
fi

# 8. Clean up test data
echo "[8/8] Cleaning up test data..."
kafka-console-producer --bootstrap-server "$BOOTSTRAP_SERVERS" \
  --topic vehicle.telemetry \
  --property "parse.key=true" \
  --property "key.separator=:" <<'EOF'
cleanup-test-data:{"vehicle_id":"cleanup-marker","vehicle_type":"regular","timestamp":1715000000000,"gps_lat":0,"gps_lng":0,"speed_kmh":0,"heading_degrees":0,"acceleration_x":0,"acceleration_y":0,"acceleration_z":0,"battery_level":null,"occupancy":null,"district":"mobility","event_type":"periodic"}
EOF
check "Test data cleanup" $?

echo ""
echo ""
echo "=== DR Readiness Summary ==="
if [ -f /tmp/dr-readiness.json ]; then
  cat /tmp/dr-readiness.json
fi
echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
exit $FAIL
