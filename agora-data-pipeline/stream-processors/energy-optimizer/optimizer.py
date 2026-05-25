import os
import json
import logging
import signal
import threading
from typing import Optional

import numpy as np
from confluent_kafka import DeserializingConsumer, Producer
from confluent_kafka.avro import AvroDeserializer, AvroSerializer
from confluent_kafka.avro.cached_schema_registry_client import CachedSchemaRegistryClient
from confluent_kafka.error import ValueDeserializationError

logging.basicConfig(
    level=os.environ.get("LOG_LEVEL", "INFO"),
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
)
log = logging.getLogger("energy-optimizer")

GROUP_ID = os.environ.get("GROUP_ID", "energy-optimizer")
BOOTSTRAP_SERVERS = os.environ.get("BOOTSTRAP_SERVERS", "localhost:9092")
SCHEMA_REGISTRY_URL = os.environ.get("SCHEMA_REGISTRY_URL", "http://localhost:8081")
SASL_USERNAME = os.environ.get("SASL_USERNAME", "")
SASL_PASSWORD = os.environ.get("SASL_PASSWORD", "")

SENSOR_TOPIC = "sensor.environmental"
ENERGY_TOPIC = "building_energy"
COMMAND_TOPIC = "energy.commands"
ALERT_TOPIC = "alerts.notifications"

RUNNING = True


def _sasl_config():
    if SASL_USERNAME and SASL_PASSWORD:
        return {
            "sasl.mechanism": "AWS_MSK_IAM",
            "sasl.username": SASL_USERNAME,
            "sasl.password": SASL_PASSWORD,
            "security.protocol": "SASL_SSL",
        }
    return {}


def _base_consumer_config(group: str) -> dict:
    cfg = {
        "bootstrap.servers": BOOTSTRAP_SERVERS,
        "group.id": group,
        "auto.offset.reset": "latest",
        "enable.auto.commit": True,
        "max.poll.interval.ms": 5000,
        "session.timeout.ms": 10000,
    }
    cfg.update(_sasl_config())
    return cfg


def _base_producer_config() -> dict:
    cfg = {
        "bootstrap.servers": BOOTSTRAP_SERVERS,
        "linger.ms": 5,
        "acks": "all",
    }
    cfg.update(_sasl_config())
    return cfg


class EnergyOptimizer:
    def __init__(self):
        self.schema_client = CachedSchemaRegistryClient({"url": SCHEMA_REGISTRY_URL})

        self.env_deserializer = AvroDeserializer(self.schema_client)
        self.energy_deserializer = AvroDeserializer(self.schema_client)
        self.command_serializer = AvroSerializer(self.schema_client)
        self.alert_serializer = AvroSerializer(self.schema_client)

        self.consumer = DeserializingConsumer(
            _base_consumer_config(GROUP_ID)
            | {
                key: val
                for key, val in {
                    "value.deserializer": self.env_deserializer,
                    "key.deserializer": self.env_deserializer,
                }.items()
            }
        )
        self.consumer.subscribe([SENSOR_TOPIC, ENERGY_TOPIC])

        self.producer = Producer(
            _base_producer_config()
            | {
                key: val
                for key, val in {
                    "value.serializer": self.command_serializer,
                    "key.serializer": self.command_serializer,
                }.items()
            }
        )

        self.weather_buffer: list[dict] = []
        self.current_consumption: float = 0.0
        self.occupancy_pattern: dict[str, float] = {}
        self.building_thermal: dict[str, float] = {}

    def _predict_temperature_drop(self) -> float:
        if len(self.weather_buffer) < 3:
            return 0.0
        temps = [r.get("temperature", 20.0) for r in self.weather_buffer[-10:]]
        if len(temps) < 3:
            return 0.0
        slope = np.polyfit(range(len(temps)), temps, 1)[0]
        return slope * 60

    def _hvac_precool(self, drop_rate: float) -> Optional[dict]:
        if drop_rate < -0.5:
            return {
                "command": "precool",
                "hvac_mode": "cool",
                "setpoint_c": 18.0,
                "duration_min": 15,
                "reason": f"temperature_drop_rate={drop_rate:.2f}C_h",
            }
        return None

    def _optimize_solar(self) -> Optional[dict]:
        if self.current_consumption > 1000:
            return {
                "command": "solar_curtail",
                "load_shed_kw": min(self.current_consumption * 0.15, 50),
                "reason": f"consumption={self.current_consumption:.0f}W_exceeds_threshold",
            }
        return None

    def _detect_critical(self) -> Optional[dict]:
        if self.current_consumption > 5000:
            return {
                "alert_type": "energy_critical",
                "severity": "critical",
                "consumption_w": self.current_consumption,
                "message": f"Energy consumption critical at {self.current_consumption:.0f}W",
            }
        return None

    def _handle_env_message(self, msg_value: dict):
        ts = msg_value.get("timestamp")
        temp = msg_value.get("temperature")
        if temp is not None:
            self.weather_buffer.append({"timestamp": ts, "temperature": temp})

        occupancy = msg_value.get("occupancy")
        if occupancy is not None:
            zone = msg_value.get("zone", "unknown")
            self.occupancy_pattern[zone] = float(occupancy)

        drop = self._predict_temperature_drop()
        cmd = self._hvac_precool(drop)
        if cmd:
            self._produce_command(cmd)

    def _handle_energy_message(self, msg_value: dict):
        consumption = msg_value.get("consumption_w")
        if consumption is not None:
            self.current_consumption = float(consumption)

        thermal = msg_value.get("thermal_lag_min")
        if thermal is not None:
            zone = msg_value.get("zone", "unknown")
            self.building_thermal[zone] = float(thermal)

        cmd = self._optimize_solar()
        if cmd:
            self._produce_command(cmd)

        alert = self._detect_critical()
        if alert:
            self._produce_alert(alert)

    def _produce_command(self, command: dict):
        self.producer.produce(
            topic=COMMAND_TOPIC,
            value=command,
            on_delivery=self._delivery_report,
        )
        log.info("Emitted command: %s", command.get("command"))

    def _produce_alert(self, alert: dict):
        self.producer.produce(
            topic=ALERT_TOPIC,
            value=alert,
            on_delivery=self._delivery_report,
        )
        log.warning("Emitted alert: %s", alert.get("alert_type"))

    @staticmethod
    def _delivery_report(err, msg):
        if err is not None:
            log.error("Delivery failed: %s", err)

    def process(self):
        log.info("Starting energy-optimizer stream processor")
        while RUNNING:
            msg = self.consumer.poll(timeout=1.0)
            if msg is None:
                continue
            if msg.error():
                log.error("Consumer error: %s", msg.error())
                continue

            try:
                value = msg.value()
                if value is None:
                    continue
                if msg.topic() == SENSOR_TOPIC:
                    self._handle_env_message(value)
                elif msg.topic() == ENERGY_TOPIC:
                    self._handle_energy_message(value)
            except ValueDeserializationError as e:
                log.error("Deserialization error on %s: %s", msg.topic(), e)
            except Exception as e:
                log.exception("Unhandled error processing %s", msg.topic())

    def close(self):
        self.consumer.close()
        self.producer.flush()
        log.info("Energy-optimizer shut down")


def main():
    optimizer = EnergyOptimizer()
    signal.signal(signal.SIGINT, lambda *_: shutdown(optimizer))
    signal.signal(signal.SIGTERM, lambda *_: shutdown(optimizer))
    optimizer.process()


def shutdown(optimizer: EnergyOptimizer):
    global RUNNING
    RUNNING = False
    optimizer.close()


if __name__ == "__main__":
    main()
