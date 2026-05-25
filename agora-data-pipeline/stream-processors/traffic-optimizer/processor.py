import json
import logging
import os
import uuid
from collections import defaultdict
from datetime import datetime, timezone

from confluent_kafka import Consumer, Producer, KafkaError, KafkaException
from confluent_kafka.schema_registry import SchemaRegistryClient
from confluent_kafka.schema_registry.avro import AvroDeserializer, AvroSerializer
from confluent_kafka.serialization import SerializationContext, MessageField

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
logger = logging.getLogger("traffic-optimizer")

BOOTSTRAP_SERVERS = os.getenv("BOOTSTRAP_SERVERS", "b-1:9098,b-2:9098,b-3:9098")
SCHEMA_REGISTRY_URL = os.getenv("SCHEMA_REGISTRY_URL", "http://schema-registry:8081")
GROUP_ID = os.getenv("GROUP_ID", "traffic-optimizer-group")
CONSUMER_TOPICS = ["vehicle.telemetry", "signal.events"]
PRODUCER_TOPICS = {"signal.commands": None, "incidents": None}

WINDOW_SIZE_MS = 5000
QUEUE_THRESHOLD = 50
SPEED_THRESHOLD_KMH = 5
MIN_GREEN_MS = 10000
MAX_GREEN_MS = 60000
DEFAULT_GREEN_MS = 30000
NEAR_COLLISION_SPEED_DELTA = 30
NEAR_COLLISION_TIME_WINDOW_MS = 2000


class TrafficOptimizer:
    def __init__(self):
        self.schema_registry = SchemaRegistryClient({"url": SCHEMA_REGISTRY_URL})
        self._init_avro_serdes()
        self.consumer = self._create_consumer()
        self.producer = self._create_producer()
        self.windows = defaultdict(lambda: {"events": [], "window_start": 0})
        self.running = True

    def _init_avro_serdes(self):
        self.signal_cmd_serializer = AvroSerializer(
            self.schema_registry,
            self._load_schema("output/signal.commands.schema.avsc"),
            lambda obj, ctx: obj,
        )
        self.incident_serializer = AvroSerializer(
            self.schema_registry,
            self._load_schema("incidents.schema.avsc"),
            lambda obj, ctx: obj,
        )
        self.telemetry_deserializer = AvroDeserializer(
            self.schema_registry,
            self._load_schema("vehicle.telemetry.schema.avsc"),
        )
        self.signal_event_deserializer = AvroDeserializer(
            self.schema_registry,
            self._load_schema("signal.events.schema.avsc"),
        )

    def _load_schema(self, path):
        base = os.path.join(os.path.dirname(__file__), "../../kafka-topics")
        with open(os.path.join(base, path)) as f:
            return f.read()

    def _create_consumer(self):
        conf = {
            "bootstrap.servers": BOOTSTRAP_SERVERS,
            "group.id": GROUP_ID,
            "enable.auto.commit": False,
            "auto.offset.reset": "earliest",
            "max.poll.records": 500,
            "session.timeout.ms": 45000,
            "heartbeat.interval.ms": 15000,
            "security.protocol": "SASL_SSL",
            "sasl.mechanism": "AWS_MSK_IAM",
            "sasl.jaas.config": "software.amazon.msk.auth.iam.IAMLoginModule required;",
            "sasl.client.callback.handler.class": "software.amazon.msk.auth.iam.IAMClientCallbackHandler",
        }
        c = Consumer(conf)
        c.subscribe(CONSUMER_TOPICS)
        return c

    def _create_producer(self):
        conf = {
            "bootstrap.servers": BOOTSTRAP_SERVERS,
            "acks": "all",
            "enable.idempotence": True,
            "compression.type": "snappy",
            "batch.size": 65536,
            "linger.ms": 10,
            "security.protocol": "SASL_SSL",
            "sasl.mechanism": "AWS_MSK_IAM",
            "sasl.jaas.config": "software.amazon.msk.auth.iam.IAMLoginModule required;",
            "sasl.client.callback.handler.class": "software.amazon.msk.auth.iam.IAMClientCallbackHandler",
        }
        return Producer(conf)

    def _process_telemetry(self, msg, key):
        try:
            value = self.telemetry_deserializer(
                msg.value(),
                SerializationContext(msg.topic(), MessageField.VALUE),
            )
            intersection_id = value.get("intersection_id") or value.get("district")
            now = value["timestamp"]
            window_start = (now // WINDOW_SIZE_MS) * WINDOW_SIZE_MS
            entry = {"speed": value["speed_kmh"], "vehicle_type": value["vehicle_type"], "timestamp": now}

            win = self.windows[intersection_id]
            if win["window_start"] != window_start:
                self._emit_decision(intersection_id, win)
                win["events"] = []
                win["window_start"] = window_start

            win["events"].append(entry)
            self._detect_near_collision(intersection_id, entry, win)
        except Exception as e:
            logger.error(f"Failed to process telemetry: {e}", exc_info=True)

    def _process_signal_event(self, msg, key):
        try:
            value = self.signal_event_deserializer(
                msg.value(),
                SerializationContext(msg.topic(), MessageField.VALUE),
            )
            intersection_id = value["intersection_id"]
            now = value["timestamp"]
            window_start = (now // WINDOW_SIZE_MS) * WINDOW_SIZE_MS

            win = self.windows[intersection_id]
            if win["window_start"] != window_start:
                self._emit_decision(intersection_id, win)
                win["events"] = []
                win["window_start"] = window_start

            win["events"].append({
                "queue_length": value["queue_length"],
                "avg_speed": value["avg_speed_kmh"],
                "emergency": value.get("emergency_vehicle_approach", False),
                "timestamp": now,
            })
        except Exception as e:
            logger.error(f"Failed to process signal event: {e}", exc_info=True)

    def _emit_decision(self, intersection_id, window):
        events = window["events"]
        if not events:
            return

        speeds = [e.get("speed") or e.get("avg_speed") for e in events if e.get("speed") or e.get("avg_speed")]
        queues = [e.get("queue_length") for e in events if e.get("queue_length") is not None]
        emergencies = any(e.get("emergency", False) for e in events)

        avg_speed = sum(speeds) / len(speeds) if speeds else 0
        avg_queue = sum(queues) / len(queues) if queues else 0

        cmd_type = None
        duration = DEFAULT_GREEN_MS
        reason = "normal_cycle"

        if emergencies:
            cmd_type = "emergency_preempt"
            duration = MAX_GREEN_MS
            reason = f"emergency_vehicle_approach_at_{window['window_start']}"
        elif avg_queue > QUEUE_THRESHOLD and avg_speed < SPEED_THRESHOLD_KMH:
            cmd_type = "extend_green"
            duration = min(int(avg_queue * 1000), MAX_GREEN_MS)
            reason = f"queue_{int(avg_queue)}_speed_{avg_speed:.1f}"
        elif avg_queue < 5 and avg_speed > SPEED_THRESHOLD_KMH:
            cmd_type = "reduce_green"
            duration = MIN_GREEN_MS
            reason = f"low_queue_{int(avg_queue)}"

        if cmd_type:
            cmd = {
                "command_id": str(uuid.uuid4()),
                "intersection_id": intersection_id,
                "timestamp": int(datetime.now(timezone.utc).timestamp() * 1000),
                "command_type": cmd_type,
                "target_phase": "green",
                "duration_ms": duration,
                "reason": reason,
                "processor_id": GROUP_ID,
                "original_event_offset": 0,
                "ttl_ms": 5000,
            }
            self.producer.produce(
                topic="signal.commands",
                key=str(intersection_id),
                value=self.signal_cmd_serializer(
                    cmd, SerializationContext("signal.commands", MessageField.VALUE)
                ),
                on_delivery=self._delivery_report,
            )
            logger.info(f"Decision: {intersection_id} -> {cmd_type} ({duration}ms) reason={reason}")

    def _detect_near_collision(self, intersection_id, entry, window):
        recent = [e for e in window["events"] if "speed" in e and abs(e["timestamp"] - entry["timestamp"]) < NEAR_COLLISION_TIME_WINDOW_MS]
        for other in recent:
            if other is entry:
                continue
            if abs(entry["speed"] - other["speed"]) > NEAR_COLLISION_SPEED_DELTA:
                incident = {
                    "incident_id": str(uuid.uuid4()),
                    "timestamp": entry["timestamp"],
                    "incident_type": "near_collision",
                    "severity": "high",
                    "source": GROUP_ID,
                    "source_topic": "vehicle.telemetry",
                    "source_partition": 0,
                    "source_offset": 0,
                    "district": intersection_id,
                    "entities_involved": [],
                    "anomaly_score": min(abs(entry["speed"] - other["speed"]) / 100.0, 1.0),
                    "description": f"Near-collision detected at {intersection_id}: speed delta {abs(entry['speed'] - other['speed']):.1f} km/h",
                    "recommended_action": "alert_traffic_control",
                }
                self.producer.produce(
                    topic="incidents",
                    key=str(uuid.uuid4()),
                    value=self.incident_serializer(
                        incident, SerializationContext("incidents", MessageField.VALUE)
                    ),
                    on_delivery=self._delivery_report,
                )

    def _delivery_report(self, err, msg):
        if err:
            logger.error(f"Delivery failed: {err}")
        else:
            logger.debug(f"Delivered to {msg.topic()} [{msg.partition()}]")

    def run(self):
        logger.info("Traffic optimizer starting")
        try:
            while self.running:
                msgs = self.consumer.consume(num_messages=100, timeout=1.0)
                for msg in msgs:
                    if msg is None:
                        continue
                    if msg.error():
                        if msg.error().code() == KafkaError._PARTITION_EOF:
                            continue
                        raise KafkaException(msg.error())
                    if msg.topic() == "vehicle.telemetry":
                        self._process_telemetry(msg, msg.key())
                    elif msg.topic() == "signal.events":
                        self._process_signal_event(msg, msg.key())
                if msgs:
                    self.consumer.commit(asynchronous=True)
                self.producer.poll(0)
        except KeyboardInterrupt:
            logger.info("Shutting down")
        finally:
            self.consumer.close()
            self.producer.flush()


if __name__ == "__main__":
    optimizer = TrafficOptimizer()
    optimizer.run()
