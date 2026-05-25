#!/bin/bash
set -euo pipefail

GROUP="${1:?Usage: $0 <group-id> [--to-earliest|--to-latest]}"
OFFSET="${2:---to-earliest}"
BOOTSTRAP_SERVERS="${3:-b-1:9098,b-2:9098,b-3:9098}"

echo "Resetting consumer group '$GROUP' to $OFFSET"
echo "Bootstrap servers: $BOOTSTRAP_SERVERS"
echo ""
echo "WARNING: This will reset consumer offsets. Continue? (y/N)"
read -r confirm
if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
  echo "Aborted"
  exit 1
fi

# Get current topics for the group
TOPICS=$(kafka-consumer-groups --bootstrap-server "$BOOTSTRAP_SERVERS" \
  --group "$GROUP" \
  --describe 2>/dev/null | awk 'NR>1 {print $3}' | sort -u)

if [ -z "$TOPICS" ]; then
  echo "No topics found for group $GROUP"
  exit 1
fi

for topic in $TOPICS; do
  echo "Resetting offset for topic: $topic"
  kafka-consumer-groups --bootstrap-server "$BOOTSTRAP_SERVERS" \
    --group "$GROUP" \
    --topic "$topic" \
    --reset-offsets "$OFFSET" \
    --execute
done

echo "Reset complete for group $GROUP"
echo "Restart consumer pods to pick up new offsets:"
echo "  kubectl -n city-services rollout restart deployment/<processor-name>"
