import time
import logging
from collections import defaultdict
from typing import Optional

log = logging.getLogger(__name__)

WINDOW_SECONDS = 10

DISTRICT_KEY = "district_id"


class WindowBucket:
    def __init__(self):
        self.speeds: list[float] = []
        self.vehicle_counts: dict[str, int] = defaultdict(int)
        self.total_vehicles = 0

    def add(self, data: dict):
        speed = data.get("speed") or data.get("velocity")
        if speed is not None:
            try:
                self.speeds.append(float(speed))
            except (ValueError, TypeError):
                pass

        vtype = data.get("vehicle_type", "unknown")
        self.vehicle_counts[vtype] += 1
        self.total_vehicles += 1

    def avg_speed(self) -> float:
        if not self.speeds:
            return 0.0
        return sum(self.speeds) / len(self.speeds)

    def congestion_level(self) -> str:
        if self.total_vehicles < 5:
            return "low"
        avg = self.avg_speed()
        if self.total_vehicles > 50 and avg < 20:
            return "severe"
        if self.total_vehicles > 20 and avg < 30:
            return "high"
        if self.total_vehicles > 10 and avg < 40:
            return "moderate"
        return "low"

    def to_output(self, district: str, window_start: float) -> dict:
        return {
            "district_id": district,
            "window_start": window_start,
            "window_end": window_start + WINDOW_SECONDS,
            "avg_speed": round(self.avg_speed(), 2),
            "vehicle_count": dict(self.vehicle_counts),
            "total_vehicles": self.total_vehicles,
            "congestion_level": self.congestion_level(),
        }


class Aggregator:
    def __init__(self):
        self._buckets: dict[str, WindowBucket] = {}
        self._window_start: Optional[float] = None

    def _current_window(self) -> float:
        now = time.time()
        return (now // WINDOW_SECONDS) * WINDOW_SECONDS

    def add(self, topic: str, data: dict) -> Optional[dict]:
        district = data.get(DISTRICT_KEY)
        if district is None:
            return None

        current_win = self._current_window()

        if self._window_start is not None and current_win > self._window_start:
            result = self._emit()
            self._buckets.clear()
            self._window_start = current_win
            self._buckets[district] = WindowBucket()
            self._buckets[district].add(data)
            return result

        if self._window_start is None:
            self._window_start = current_win

        if district not in self._buckets:
            self._buckets[district] = WindowBucket()
        self._buckets[district].add(data)

        return None

    def _emit(self) -> dict:
        districts = []
        for d, bucket in self._buckets.items():
            districts.append(bucket.to_output(d, self._window_start))
        return {
            "type": "aggregated_traffic",
            "window_start": self._window_start,
            "window_end": self._window_start + WINDOW_SECONDS,
            "districts": districts,
        }
