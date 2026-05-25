import json
import logging
import os
import pickle
import signal
import sys
from collections import defaultdict
from typing import Any, Dict, List, Optional, Tuple

import numpy as np
from confluent_kafka import Consumer, Producer
from confluent_kafka.schema_registry import SchemaRegistryClient
from confluent_kafka.schema_registry.avro import AvroDeserializer, AvroSerializer
from confluent_kafka.serialization import SerializationContext, MessageField
from prometheus_client import Counter, Gauge, Histogram, start_http_server

logger = logging.getLogger("anomaly-detector")
logging.basicConfig(
    level=getattr(logging, os.environ.get("LOG_LEVEL", "INFO").upper()),
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
)

TELEMETRY_TOPIC = "vehicle.telemetry"
INCIDENTS_TOPIC = "incidents"
ALERTS_TOPIC = "alerts.notifications"

ANOMALY_THRESHOLD = float(os.environ.get("ANOMALY_THRESHOLD", "0.8"))
GROUP_ID = os.environ.get("GROUP_ID", "anomaly-detector-group")

BOOTSTRAP_SERVERS = os.environ.get("BOOTSTRAP_SERVERS", "localhost:9092")
SCHEMA_REGISTRY_URL = os.environ.get("SCHEMA_REGISTRY_URL", "http://localhost:8081")
SASL_USERNAME = os.environ.get("SASL_USERNAME", "")
SASL_PASSWORD = os.environ.get("SASL_PASSWORD", "")
AWS_MSK_IAM_ENABLED = os.environ.get("AWS_MSK_IAM_ENABLED", "false").lower() == "true"

MODEL_PATH = os.environ.get("MODEL_PATH", "model/anomaly_model.pkl")

METRICS_PORT = int(os.environ.get("METRICS_PORT", "8000"))

prometheus_errors = Counter(
    "anomaly_detector_errors_total",
    "Total processing errors",
    ["error_type"],
)
prometheus_messages_processed = Counter(
    "anomaly_detector_messages_processed_total",
    "Total messages processed",
)
prometheus_anomalies_detected = Counter(
    "anomaly_detector_anomalies_detected_total",
    "Total anomalies detected",
    ["severity", "classification"],
)
prometheus_processing_duration = Histogram(
    "anomaly_detector_processing_duration_seconds",
    "Message processing duration in seconds",
    buckets=[0.001, 0.005, 0.01, 0.05, 0.1, 0.5, 1.0],
)
prometheus_anomaly_score = Gauge(
    "anomaly_detector_anomaly_score",
    "Latest anomaly score per vehicle",
    ["vehicle_id"],
)

ANOMALY_CLASSIFICATIONS = [
    "unusual_driving",
    "sensor_failure",
    "communication_loss",
    "pattern_deviation",
]


class AnomalyDetector:
    def __init__(self):
        self.model = self._load_model()
        self.heuristic_weights = {
            "speed": 0.3,
            "acceleration": 0.4,
            "battery": 0.2,
            "emergency_brake": 0.5,
            "collision_risk": 0.7,
        }
        self._running = True
        signal.signal(signal.SIGINT, self._stop)
        signal.signal(signal.SIGTERM, self._stop)

    def _stop(self, *_args: Any) -> None:
        logger.info("Shutdown signal received")
        self._running = False

    def _load_model(self) -> Optional[Any]:
        if not os.path.exists(MODEL_PATH):
            logger.warning("Model file %s not found; using heuristic scoring only", MODEL_PATH)
            return None
        try:
            with open(MODEL_PATH, "rb") as f:
                model = pickle.load(f)
            logger.info("Loaded model from %s", MODEL_PATH)
            return model
        except Exception as e:
            logger.error("Failed to load model: %s; falling back to heuristic scoring", e)
            prometheus_errors.labels(error_type="model_load").inc()
            return None

    def _build_kafka_config(self, client_type: str = "consumer") -> Dict[str, str]:
        config: Dict[str, str] = {
            "bootstrap.servers": BOOTSTRAP_SERVERS,
            "security.protocol": "SASL_SSL",
        }
        if AWS_MSK_IAM_ENABLED:
            config["sasl.mechanisms"] = "AWS_MSK_IAM"
            config["sasl.username"] = SASL_USERNAME
            config["sasl.password"] = SASL_PASSWORD
        else:
            config["sasl.mechanism"] = "PLAIN"
            config["sasl.username"] = SASL_USERNAME
            config["sasl.password"] = SASL_PASSWORD

        if client_type == "consumer":
            config["group.id"] = GROUP_ID
            config["auto.offset.reset"] = "earliest"
            config["enable.auto.commit"] = "false"
        return config

    def _create_schema_registry_client(self) -> SchemaRegistryClient:
        conf = {"url": SCHEMA_REGISTRY_URL}
        return SchemaRegistryClient(conf)

    def _heuristic_score(self, record: Dict[str, Any]) -> Tuple[float, Dict[str, float]]:
        score = 0.0
        breakdown: Dict[str, float] = {}

        if record.get("speed", 0) > 120:
            breakdown["speed"] = self.heuristic_weights["speed"]
            score += breakdown["speed"]

        accel = abs(record.get("acceleration", 0))
        if accel > 8:
            breakdown["acceleration"] = self.heuristic_weights["acceleration"]
            score += breakdown["acceleration"]

        battery = record.get("battery_level", 100)
        if battery is not None and battery < 5:
            breakdown["battery"] = self.heuristic_weights["battery"]
            score += breakdown["battery"]

        if record.get("emergency_brake", False):
            breakdown["emergency_brake"] = self.heuristic_weights["emergency_brake"]
            score += breakdown["emergency_brake"]

        if record.get("collision_risk", False):
            breakdown["collision_risk"] = self.heuristic_weights["collision_risk"]
            score += breakdown["collision_risk"]

        return min(score, 1.0), breakdown

    def _model_score(self, record: Dict[str, Any]) -> Optional[float]:
        if self.model is None:
            return None
        try:
            features = np.array([[
                record.get("speed", 0),
                record.get("acceleration", 0),
                record.get("battery_level", 100),
                record.get("temperature", 25),
                1 if record.get("emergency_brake", False) else 0,
                1 if record.get("collision_risk", False) else 0,
            ]])
            if hasattr(self.model, "score_samples"):
                score = self.model.score_samples(features)[0]
                return float(1.0 - (score + 0.5))
            elif hasattr(self.model, "decision_function"):
                score = self.model.decision_function(features)[0]
                return float(1.0 - (score + 0.5))
            else:
                pred = self.model.predict(features)[0]
                return 1.0 if pred == -1 else 0.0
        except Exception as e:
            logger.warning("Model scoring failed: %s", e)
            prometheus_errors.labels(error_type="model_score").inc()
            return None

    def _classify_anomaly(self, record: Dict[str, Any], breakdown: Dict[str, float]) -> str:
        if breakdown.get("collision_risk", 0) > 0:
            return "unusual_driving"
        if breakdown.get("emergency_brake", 0) > 0:
            return "unusual_driving"
        if breakdown.get("acceleration", 0) > 0:
            return "sensor_failure"
        if record.get("battery_level", 100) < 5 and record.get("communication_loss", False):
            return "communication_loss"
        return "pattern_deviation"

    def _determine_severity(self, score: float) -> str:
        if score >= 0.9:
            return "critical"
        elif score >= ANOMALY_THRESHOLD:
            return "high"
        return "medium"

    def _process_message(self, record: Dict[str, Any]) -> Optional[Dict[str, Any]]:
        prometheus_messages_processed.inc()

        heuristic_score, breakdown = self._heuristic_score(record)
        model_score = self._model_score(record)

        final_score = model_score if model_score is not None else heuristic_score
        vehicle_id = record.get("vehicle_id", "unknown")

        prometheus_anomaly_score.labels(vehicle_id=vehicle_id).set(final_score)

        if final_score < ANOMALY_THRESHOLD:
            return None

        severity = self._determine_severity(final_score)
        classification = self._classify_anomaly(record, breakdown)

        incident = {
            "vehicle_id": vehicle_id,
            "anomaly_score": final_score,
            "severity": severity,
            "classification": classification,
            "score_breakdown": breakdown,
            "telemetry_snapshot": {
                k: record.get(k) for k in [
                    "speed", "acceleration", "battery_level", "temperature",
                    "emergency_brake", "collision_risk", "timestamp",
                ]
            },
            "source": "model" if model_score is not None else "heuristic",
            "timestamp": record.get("timestamp", ""),
        }

        prometheus_anomalies_detected.labels(
            severity=severity, classification=classification
        ).inc()

        return incident

    def _create_alert(self, incident: Dict[str, Any]) -> Dict[str, Any]:
        return {
            "type": "anomaly_alert",
            "severity": incident["severity"],
            "title": f"Anomaly detected on vehicle {incident['vehicle_id']}",
            "message": (
                f"Vehicle {incident['vehicle_id']} triggered a {incident['classification']} "
                f"anomaly with score {incident['anomaly_score']:.2f}."
            ),
            "incident_ref": {
                "vehicle_id": incident["vehicle_id"],
                "timestamp": incident["timestamp"],
                "classification": incident["classification"],
            },
            "timestamp": incident["timestamp"],
        }

    def run(self) -> None:
        logger.info(
            "Starting anomaly detector (threshold=%.2f, group=%s, servers=%s)",
            ANOMALY_THRESHOLD, GROUP_ID, BOOTSTRAP_SERVERS,
        )
        start_http_server(METRICS_PORT)
        logger.info("Metrics server started on port %d", METRICS_PORT)

        consumer_conf = self._build_kafka_config("consumer")
        producer_conf = self._build_kafka_config("producer")

        schema_registry = self._create_schema_registry_client()

        avro_deserializer = AvroDeserializer(schema_registry)
        avro_serializer = AvroSerializer(schema_registry)

        consumer = Consumer(consumer_conf)
        producer = Producer(producer_conf)

        consumer.subscribe([TELEMETRY_TOPIC])
        logger.info("Subscribed to %s", TELEMETRY_TOPIC)

        try:
            while self._running:
                msg = consumer.poll(timeout=1.0)
                if msg is None:
                    continue
                if msg.error():
                    logger.error("Consumer error: %s", msg.error())
                    prometheus_errors.labels(error_type="consumer").inc()
                    continue

                try:
                    with prometheus_processing_duration.time():
                        record = avro_deserializer(
                            msg.value(),
                            SerializationContext(msg.topic(), MessageField.VALUE),
                        )
                except Exception as e:
                    logger.warning("Deserialization failed, trying JSON: %s", e)
                    try:
                        record = json.loads(msg.value().decode("utf-8"))
                    except Exception as e2:
                        logger.error("JSON fallback also failed: %s", e2)
                        prometheus_errors.labels(error_type="deserialization").inc()
                        continue

                try:
                    incident = self._process_message(record)
                except Exception as e:
                    logger.error("Processing error: %s", e)
                    prometheus_errors.labels(error_type="processing").inc()
                    continue

                if incident is None:
                    consumer.commit(asynchronous=False)
                    continue

                try:
                    ctx = SerializationContext(INCIDENTS_TOPIC, MessageField.VALUE)
                    incident_bytes = avro_serializer(incident, ctx)
                    producer.produce(INCIDENTS_TOPIC, value=incident_bytes)
                except Exception:
                    try:
                        incident_bytes = json.dumps(incident).encode("utf-8")
                        producer.produce(INCIDENTS_TOPIC, value=incident_bytes)
                    except Exception as e:
                        logger.error("Failed to produce incident: %s", e)
                        prometheus_errors.labels(error_type="produce_incident").inc()
                        consumer.commit(asynchronous=False)
                        continue

                if incident["severity"] in ("critical", "high"):
                    alert = self._create_alert(incident)
                    try:
                        ctx = SerializationContext(ALERTS_TOPIC, MessageField.VALUE)
                        alert_bytes = avro_serializer(alert, ctx)
                        producer.produce(ALERTS_TOPIC, value=alert_bytes)
                    except Exception:
                        try:
                            alert_bytes = json.dumps(alert).encode("utf-8")
                            producer.produce(ALERTS_TOPIC, value=alert_bytes)
                        except Exception as e:
                            logger.error("Failed to produce alert: %s", e)
                            prometheus_errors.labels(error_type="produce_alert").inc()

                producer.flush()
                consumer.commit(asynchronous=False)

        except Exception as e:
            logger.error("Fatal error: %s", e)
            prometheus_errors.labels(error_type="fatal").inc()
        finally:
            consumer.close()
            producer.flush()
            logger.info("Shutdown complete")


if __name__ == "__main__":
    detector = AnomalyDetector()
    detector.run()
