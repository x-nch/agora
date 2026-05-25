import os
import json
import logging
import threading
from typing import Optional
from datetime import datetime, timezone

from confluent_kafka import DeserializingConsumer, SerializingProducer
from confluent_kafka.schema_registry import SchemaRegistryClient
from confluent_kafka.schema_registry.avro import AvroDeserializer, AvroSerializer
from confluent_kafka.serialization import StringDeserializer, StringSerializer
from prometheus_client import start_http_server, Counter, Histogram, Gauge

from transformations.anonymizer import Anonymizer
from transformations.aggregator import Aggregator
from transformations.access_control import AccessController

logging.basicConfig(level=os.environ.get("LOG_LEVEL", "INFO"))
log = logging.getLogger("data-broker")

METRIC_READ = Counter("broker_messages_read_total", "Messages read from source", ["topic"])
METRIC_WRITTEN = Counter("broker_messages_written_total", "Messages written to sink", ["topic"])
METRIC_LATENCY = Histogram("broker_processing_seconds", "End-to-end processing latency")
METRIC_EVENT_AGE = Histogram("broker_event_age_seconds", "Age of events being processed")
METRIC_ANON_COUNT = Counter("broker_anonymized_total", "Events anonymized")
METRIC_AGG_COUNT = Counter("broker_aggregated_total", "Aggregation windows emitted")
METRIC_ACCESS_DENIED = Counter("broker_access_denied_total", "Events denied by access control", ["reason"])
METRIC_UP = Gauge("broker_up", "Broker processor running status")
METRIC_LAG = Gauge("broker_consumer_lag", "Consumer lag per partition", ["partition"])

SOURCE_TOPICS = ["vehicle.telemetry", "sensor.environmental", "signal.events"]
SINK_TOPICS = ["data.anonymized.vehicle", "data.inventor.traffic"]
S3_PREFIX = "s3://agora-data-lake/processed/"

BOOTSTRAP_SERVERS = os.environ.get("BOOTSTRAP_SERVERS", "localhost:9092")
SCHEMA_REGISTRY_URL = os.environ.get("SCHEMA_REGISTRY_URL", "http://localhost:8081")
GROUP_ID = os.environ.get("GROUP_ID", "data-broker-group")
CLIENT_ID = os.environ.get("CLIENT_ID", "data-broker")
AWS_REGION = os.environ.get("AWS_REGION", "us-east-1")

SASL_USERNAME = os.environ.get("SASL_USERNAME", "")
SASL_PASSWORD = os.environ.get("SASL_PASSWORD", "")

def _kafka_conf(extra: Optional[dict] = None) -> dict:
    conf = {
        "bootstrap.servers": BOOTSTRAP_SERVERS,
        "client.id": CLIENT_ID,
        "security.protocol": "SASL_SSL",
        "sasl.mechanisms": "AWS_MSK_IAM",
        "sasl.username": SASL_USERNAME,
        "sasl.password": SASL_PASSWORD,
        "session.timeout.ms": 45000,
        "heartbeat.interval.ms": 15000,
    }
    if extra:
        conf.update(extra)
    return conf


class Broker:
    def __init__(self):
        self.schema_registry = SchemaRegistryClient({"url": SCHEMA_REGISTRY_URL})
        self._running = False
        self._threads: list[threading.Thread] = []

        self.anonymizer = Anonymizer()
        self.aggregator = Aggregator()
        self.access_control = AccessController()

        self._producers: dict[str, SerializingProducer] = {}

    def _avro_consumer(self, topic: str) -> DeserializingConsumer:
        subject = f"{topic}-value"
        try:
            schema = self.schema_registry.get_latest_version(subject)
            avro_deserializer = AvroDeserializer(schema, self.schema_registry)
        except Exception:
            log.warning("Schema for %s not found, using raw JSON", subject)
            avro_deserializer = None

        conf = _kafka_conf({
            "group.id": GROUP_ID,
            "enable.auto.commit": True,
            "auto.offset.reset": "earliest",
            "key.deserializer": StringDeserializer("utf_8"),
            "value.deserializer": avro_deserializer or "none",
        })
        return DeserializingConsumer(conf)

    def _producer_for(self, topic: str) -> SerializingProducer:
        if topic not in self._producers:
            avro_serializer = None
            try:
                schema = self.schema_registry.get_latest_version(f"{topic}-value")
                avro_serializer = AvroSerializer(schema, self.schema_registry)
            except Exception:
                log.warning("Schema for %s not found, using raw JSON", topic)

            conf = _kafka_conf({
                "key.serializer": StringSerializer("utf_8"),
                "value.serializer": avro_serializer or "none",
                "acks": "all",
                "linger.ms": 10,
                "batch.num.messages": 1000,
                "compression.type": "snappy",
            })
            self._producers[topic] = SerializingProducer(conf)
        return self._producers[topic]

    def _delivery_report(self, err, msg):
        if err:
            log.error("Delivery failed: %s", err)
        else:
            METRIC_WRITTEN.labels(topic=msg.topic()).inc()

    def process_message(self, msg, topic: str):
        start = datetime.now(timezone.utc)
        key = msg.key()
        value = msg.value()
        if value is None:
            return

        METRIC_READ.labels(topic=topic).inc()

        if isinstance(value, dict):
            ts = value.get("timestamp") or value.get("event_time") or value.get("generated_at")
            if ts:
                try:
                    age = (datetime.now(timezone.utc) - datetime.fromisoformat(ts.replace("Z", "+00:00"))).total_seconds()
                    METRIC_EVENT_AGE.observe(age)
                except Exception:
                    pass

        anon = self.anonymizer.process(value, topic)
        if anon is None:
            return
        METRIC_ANON_COUNT.inc()

        agg = self.aggregator.add(topic, anon)

        routes = self.access_control.route(anon, agg, topic)
        for sink_topic, payload in routes:
            producer = self._producer_for(sink_topic)
            producer.produce(
                topic=sink_topic,
                key=key,
                value=payload,
                on_delivery=self._delivery_report,
            )

        latency = (datetime.now(timezone.utc) - start).total_seconds()
        METRIC_LATENCY.observe(latency)

    def consume_loop(self, topic: str):
        consumer = self._avro_consumer(topic)
        consumer.subscribe([topic])
        log.info("Started consuming from %s", topic)

        while self._running:
            try:
                msg = consumer.poll(0.1)
                if msg is None:
                    continue
                if msg.error():
                    log.error("Consumer error on %s: %s", topic, msg.error())
                    continue

                self.process_message(msg, topic)
            except Exception:
                log.exception("Error processing message from %s", topic)

        consumer.close()
        log.info("Consumer for %s shut down", topic)

    def flush_all(self):
        for topic, producer in self._producers.items():
            producer.flush()
            log.info("Flushed producer for %s", topic)

    def run(self):
        METRIC_UP.set(1)
        metrics_port = int(os.environ.get("METRICS_PORT", "8000"))
        start_http_server(metrics_port)
        log.info("Prometheus metrics on :%d", metrics_port)

        self._running = True
        for topic in SOURCE_TOPICS:
            t = threading.Thread(target=self.consume_loop, args=(topic,), daemon=True)
            t.start()
            self._threads.append(t)

        try:
            for t in self._threads:
                t.join()
        except KeyboardInterrupt:
            log.info("Shutting down...")
        finally:
            self._running = False
            self.flush_all()
            METRIC_UP.set(0)


if __name__ == "__main__":
    Broker().run()
