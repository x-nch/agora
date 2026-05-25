import time
import copy
from typing import Optional

PII_FIELDS = {"driver_id", "driver_name", "license_plate", "payment_info",
               "credit_card", "email", "phone", "home_address"}

SPEED_BUCKETS = [(0, 10), (10, 20), (20, 30), (30, 40), (40, 50),
                 (50, 60), (60, 70), (70, 80), (80, 90), (90, 100),
                 (100, 120), (120, 999)]

VEHICLE_ID_KEYS = {"vehicle_id", "vehicle_uuid", "vin", "device_id"}
GPS_KEYS = {"latitude", "lat", "longitude", "lon", "lng"}


def _round_gps(value: float) -> float:
    return round(value, 2)


def _bucket_speed(speed: float) -> str:
    for lo, hi in SPEED_BUCKETS:
        if lo <= speed < hi:
            return f"{lo}-{hi}"
    return "120+"


class Anonymizer:
    def process(self, data: Optional[dict], topic: str) -> Optional[dict]:
        if data is None:
            return None

        out = copy.deepcopy(data)

        for key in VEHICLE_ID_KEYS:
            if key in out:
                del out[key]

        if "vehicle_type" not in out:
            out["vehicle_type"] = "unknown"

        for lat_key in {"latitude", "lat"}:
            if lat_key in out:
                try:
                    out[lat_key] = _round_gps(float(out[lat_key]))
                except (ValueError, TypeError):
                    pass

        for lon_key in {"longitude", "lon", "lng"}:
            if lon_key in out:
                try:
                    out[lon_key] = _round_gps(float(out[lon_key]))
                except (ValueError, TypeError):
                    pass

        for speed_key in {"speed", "velocity", "speed_kph", "gps_speed"}:
            if speed_key in out:
                try:
                    out["speed_bucket"] = _bucket_speed(float(out[speed_key]))
                except (ValueError, TypeError):
                    pass

        for field in PII_FIELDS:
            out.pop(field, None)

        out["anonymized_at"] = time.time()

        return out
