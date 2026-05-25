#!/bin/bash
set -euo pipefail

KAFKA_BOOTSTRAP="${1:-b-1:9098,b-2:9098,b-3:9098}"
TOOLS_IMAGE="bitnami/kafka:3.6"

apply_topic() {
  local name="$1"
  local partitions="$2"
  local config="$3"
  echo "Creating topic: $name ($partitions partitions)"
  docker run --rm "$TOOLS_IMAGE" kafka-topics.sh \
    --bootstrap-server "$KAFKA_BOOTSTRAP" \
    --create --if-not-exists \
    --topic "$name" \
    --partitions "$partitions" \
    --replication-factor 3 \
    --config "$config"
}

apply_topic "vehicle.telemetry" 12 "cleanup.policy=delete,compact&retention.ms=604800000&compression.type=snappy&min.insync.replicas=2"
apply_topic "sensor.environmental" 6 "cleanup.policy=delete&retention.ms=604800000&compression.type=snappy&min.insync.replicas=2"
apply_topic "signal.events" 6 "cleanup.policy=delete&retention.ms=604800000&compression.type=snappy&min.insync.replicas=2"
apply_topic "incidents" 1 "cleanup.policy=delete&retention.ms=2592000000&min.insync.replicas=2"
apply_topic "signal.commands" 6 "cleanup.policy=delete&retention.ms=172800000&compression.type=snappy&min.insync.replicas=2"
apply_topic "data.anonymized.vehicle" 12 "cleanup.policy=delete&retention.ms=2592000000&compression.type=snappy&min.insync.replicas=2"
apply_topic "data.inventor.traffic" 3 "cleanup.policy=delete&retention.ms=604800000&compression.type=snappy&min.insync.replicas=2"
apply_topic "alerts.notifications" 1 "cleanup.policy=delete,compact&retention.ms=7776000000&min.insync.replicas=2"
apply_topic "dlq.all" 1 "cleanup.policy=delete&retention.ms=2592000000&min.insync.replicas=2"

echo "All topics created successfully"
