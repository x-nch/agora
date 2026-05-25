import logging
from typing import Optional

log = logging.getLogger(__name__)

TOPIC_ANONYMIZED = "data.anonymized.vehicle"
TOPIC_INVENTOR = "data.inventor.traffic"

ANON_FIELDS = {"speed_bucket", "vehicle_type", "latitude", "longitude",
               "anonymized_at", "district_id", "event_type", "temperature",
               "humidity", "air_quality_index"}

INVENTOR_FIELDS = {"avg_speed", "vehicle_count", "total_vehicles",
                   "congestion_level", "district_id", "window_start", "window_end"}


def _filter_keys(data: dict, allowed: set) -> dict:
    return {k: v for k, v in data.items() if k in allowed}


class AccessController:
    def route(self, anon: dict, agg: Optional[dict], topic: str) -> list[tuple[str, dict]]:
        routes: list[tuple[str, dict]] = []

        agg_allowed = agg is not None
        is_external = topic in {"sensor.environmental", "signal.events"}

        if is_external:
            if agg_allowed:
                routes.append(self._inventor_entry(agg))
            return routes

        if agg_allowed:
            routes.append(self._inventor_entry(agg))

        anon_filtered = _filter_keys(anon, ANON_FIELDS)
        routes.append((TOPIC_ANONYMIZED, anon_filtered))

        return routes

    def _inventor_entry(self, agg: dict) -> tuple[str, dict]:
        districts = agg.get("districts", [])
        filtered_districts = []
        for d in districts:
            filtered_districts.append(_filter_keys(d, INVENTOR_FIELDS))
        payload = dict(agg)
        payload["districts"] = filtered_districts
        return (TOPIC_INVENTOR, payload)
