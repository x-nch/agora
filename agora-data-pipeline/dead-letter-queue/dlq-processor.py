import json
import logging
import os
from collections import defaultdict
from datetime import datetime, timezone

from confluent_kafka import Consumer, Producer, KafkaError, KafkaException

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
logger = logging.getLogger("dlq-processor")

BOOTSTRAP_SERVERS = os.getenv("BOOTSTRAP_SERVERS", "b-1:9098,b-2:9098,b-3:9098")
GROUP_ID = os.getenv("GROUP_ID", "dlq-processor-group")
DLQ_TOPIC = "dlq.all"
MAX_RETRIES = 3
RETRY_TOPICS = {}  # populated dynamically


class DLQProcessor:
    def __init__(self):
        self.consumer = self._create_consumer()
        self.producer = self._create_producer()
        self.retry_counts = defaultdict(int)
        self.running = True

    def _create_consumer(self):
        conf = {
            "bootstrap.servers": BOOTSTRAP_SERVERS,
            "group.id": GROUP_ID,
            "enable.auto.commit": False,
            "auto.offset.reset": "earliest",
            "max.poll.records": 100,
            "security.protocol": "SASL_SSL",
            "sasl.mechanism": "AWS_MSK_IAM",
            "sasl.jaas.config": "software.amazon.msk.auth.iam.IAMLoginModule required;",
            "sasl.client.callback.handler.class": "software.amazon.msk.auth.iam.IAMClientCallbackHandler",
        }
        c = Consumer(conf)
        c.subscribe([DLQ_TOPIC])
        return c

    def _create_producer(self):
        conf = {
            "bootstrap.servers": BOOTSTRAP_SERVERS,
            "acks": "all",
            "enable.idempotence": True,
            "security.protocol": "SASL_SSL",
            "sasl.mechanism": "AWS_MSK_IAM",
            "sasl.jaas.config": "software.amazon.msk.auth.iam.IAMLoginModule required;",
            "sasl.client.callback.handler.class": "software.amazon.msk.auth.iam.IAMClientCallbackHandler",
        }
        return Producer(conf)

    def _classify_failure(self, dlq_msg):
        error_details = dlq_msg.get("error_details", {})
        error_type = error_details.get("type", "")

        if "Schema" in error_type or "schema" in error_type or "compatibility" in error_type:
            return "schema_violation"
        if "deserialization" in error_type.lower() or "parse" in error_type.lower():
            return "deserialization_error"
        if "timeout" in error_type.lower() or "retriable" in error_type.lower():
            return "transient_error"
        if "poison" in error_type.lower():
            return "poison_pill"

        return "unknown"

    def _handle_schema_violation(self, dlq_msg):
        logger.warning(f"Schema violation: {dlq_msg.get('source_topic', 'unknown')} "
                       f"[{dlq_msg.get('source_partition')}@{dlq_msg.get('source_offset')}]")
        # Notify schema registry team via alert topic
        alert = {
            "type": "schema_violation",
            "source": dlq_msg.get("source_topic"),
            "partition": dlq_msg.get("source_partition"),
            "offset": dlq_msg.get("source_offset"),
            "timestamp": int(datetime.now(timezone.utc).timestamp() * 1000),
        }
        self.producer.produce(
            "alerts.notifications",
            key="schema_registry_team",
            value=json.dumps(alert).encode(),
        )

    def _handle_deserialization_error(self, dlq_msg):
        logger.error(f"Deserialization error: data corruption detected in "
                     f"{dlq_msg.get('source_topic')} [{dlq_msg.get('source_partition')}@{dlq_msg.get('source_offset')}]")
        # Log and alert - data corruption needs investigation
        alert = {
            "type": "data_corruption",
            "source": dlq_msg.get("source_topic"),
            "partition": dlq_msg.get("source_partition"),
            "offset": dlq_msg.get("source_offset"),
            "timestamp": int(datetime.now(timezone.utc).timestamp() * 1000),
        }
        self.producer.produce(
            "alerts.notifications",
            key="data_engineering",
            value=json.dumps(alert).encode(),
        )

    def _handle_transient_error(self, dlq_msg):
        msg_id = f"{dlq_msg.get('source_topic')}:{dlq_msg.get('source_partition')}:{dlq_msg.get('source_offset')}"
        self.retry_counts[msg_id] += 1

        if self.retry_counts[msg_id] <= MAX_RETRIES:
            logger.info(f"Retrying ({self.retry_counts[msg_id]}/{MAX_RETRIES}): {msg_id}")
            # Reproduce to original topic
            self.producer.produce(
                dlq_msg.get("source_topic"),
                key=dlq_msg.get("original_key"),
                value=dlq_msg.get("original_value"),
            )
        else:
            logger.error(f"Max retries exhausted for {msg_id}, discarding")
            del self.retry_counts[msg_id]

    def _handle_poison_pill(self, dlq_msg):
        logger.error(f"Poison pill message from {dlq_msg.get('source_topic')} - "
                     f"producer: {dlq_msg.get('producer_id', 'unknown')}")
        alert = {
            "type": "poison_pill",
            "source": dlq_msg.get("source_topic"),
            "producer": dlq_msg.get("producer_id", "unknown"),
            "timestamp": int(datetime.now(timezone.utc).timestamp() * 1000),
        }
        self.producer.produce(
            "alerts.notifications",
            key="security_team",
            value=json.dumps(alert).encode(),
        )

    def process(self, dlq_msg):
        classification = self._classify_failure(dlq_msg)
        logger.info(f"DLQ message classified as: {classification}")

        handlers = {
            "schema_violation": self._handle_schema_violation,
            "deserialization_error": self._handle_deserialization_error,
            "transient_error": self._handle_transient_error,
            "poison_pill": self._handle_poison_pill,
        }

        handler = handlers.get(classification, self._handle_unknown)
        handler(dlq_msg)

    def _handle_unknown(self, dlq_msg):
        logger.warning(f"Unknown failure type, logging only: {dlq_msg.get('error_details', {})}")

    def run(self):
        logger.info("DLQ processor starting")
        try:
            while self.running:
                msgs = self.consumer.consume(num_messages=50, timeout=1.0)
                for msg in msgs:
                    if msg is None:
                        continue
                    if msg.error():
                        if msg.error().code() == KafkaError._PARTITION_EOF:
                            continue
                        raise KafkaException(msg.error())
                    try:
                        dlq_msg = json.loads(msg.value())
                        self.process(dlq_msg)
                    except json.JSONDecodeError:
                        logger.error("Failed to decode DLQ message")
                    self.producer.poll(0)
                if msgs:
                    self.consumer.commit(asynchronous=True)
        except KeyboardInterrupt:
            logger.info("Shutting down")
        finally:
            self.consumer.close()
            self.producer.flush()


if __name__ == "__main__":
    processor = DLQProcessor()
    processor.run()
