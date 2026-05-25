#!/bin/bash
set -euo pipefail

BOOTSTRAP_SERVERS="${1:-b-1:9098,b-2:9098,b-3:9098}"
COUNT="${2:-1000}"

echo "Seeding $COUNT test IoT events to $BOOTSTRAP_SERVERS"

VEHICLE_TYPES=("autonomous" "regular" "emergency" "public_transport" "micro_mobility")
DISTRICTS=("mobility" "living" "working" "wellness" "innovation")
EVENT_TYPES=("periodic" "periodic" "periodic" "periodic" "emergency_brake" "collision_risk")

for i in $(seq 1 "$COUNT"); do
  VEHICLE_ID="test-vehicle-$(printf '%04d' $i)"
  TYPE=${VEHICLE_TYPES[$((RANDOM % ${#VEHICLE_TYPES[@]}))]}
  DISTRICT=${DISTRICTS[$((RANDOM % ${#DISTRICTS[@]}))]}
  EVENT=${EVENT_TYPES[$((RANDOM % ${#EVENT_TYPES[@]}))]}
  SPEED=$((RANDOM % 80 + 10))
  LAT=$(python3 -c "print(35.1 + ($RANDOM % 1000) / 10000.0)")
  LNG=$(python3 -c "print(139.4 + ($RANDOM % 1000) / 10000.0)")
  TIMESTAMP=$(date +%s%3N)

  echo "$VEHICLE_ID:{\"vehicle_id\":\"$VEHICLE_ID\",\"vehicle_type\":\"$TYPE\",\"timestamp\":$TIMESTAMP,\"gps_lat\":$LAT,\"gps_lng\":$LNG,\"speed_kmh\":$SPEED,\"heading_degrees\":$((RANDOM % 360)),\"acceleration_x\":0.0,\"acceleration_y\":0.0,\"acceleration_z\":-0.1,\"battery_level\":$((RANDOM % 100 + 1)),\"occupancy\":$((RANDOM % 5 + 1)),\"district\":\"$DISTRICT\",\"event_type\":\"$EVENT\"}"

  if [ $((i % 100)) -eq 0 ]; then
    echo "  ... $i events generated" >&2
  fi
done | kafka-console-producer --bootstrap-server "$BOOTSTRAP_SERVERS" \
  --topic vehicle.telemetry \
  --property "parse.key=true" \
  --property "key.separator=:" \
  --property "compression.type=snappy" \
  --request-required-acks all

echo "Done: $COUNT events seeded to vehicle.telemetry"
