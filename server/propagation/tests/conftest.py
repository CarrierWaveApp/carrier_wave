"""Pytest bootstrap that installs a minimal dvoacap stub.

The real dvoacap-python package is only pulled in by the Docker build. Local
tests run a stub that returns deterministic numbers so we can exercise the
FastAPI surface and the engine wiring without the heavy scientific dep.
"""

from __future__ import annotations

import math
import sys
import types


class _Signal:
    def __init__(self, freq_mhz: float, distance_km: float) -> None:
        # Arbitrary but monotonic-with-distance values so tests can assert on
        # ordering without caring about the true VOACAP numbers.
        self.total_loss_db = 80.0 + distance_km / 100.0
        self.snr_db = max(-30.0, 20.0 - distance_km / 500.0 - abs(freq_mhz - 14.0))
        self.reliability = max(0.0, min(1.0, 0.9 - distance_km / 20_000.0))


class _Prediction:
    def __init__(self, freq_mhz: float, distance_km: float) -> None:
        self.signal = _Signal(freq_mhz, distance_km)
        self.hop_count = 1 if distance_km <= 4_000.0 else 2
        self.tx_elevation = math.radians(max(5.0, 25.0 - distance_km / 400.0))
        self.service_prob = 0.7
        self.multipath_prob = 0.2


class _Muf:
    def __init__(self) -> None:
        self.muf = 22.0


class _Path:
    def __init__(self) -> None:
        self.dist = 0.0
        self.azim_tr = 0.0


class _Params:
    def __init__(self) -> None:
        self.ssn = 0.0
        self.month = 1
        self.tx_power = 100.0
        self.tx_location = None


class _FakeEngine:
    def __init__(self) -> None:
        self.params = _Params()
        self.muf_calculator = _Muf()
        self.path = _Path()
        self.predictions: list[_Prediction] = []

    def predict(self, rx_location, utc_time, frequencies):  # noqa: ANN001
        tx = self.params.tx_location
        if tx is None or rx_location is None:
            distance_km = 0.0
        else:
            distance_km = _great_circle_km(tx, rx_location)
        self.predictions = [_Prediction(f, distance_km) for f in frequencies]


def _great_circle_km(a, b) -> float:
    lat1 = getattr(a, "lat_deg", None) or math.degrees(getattr(a, "lat", 0.0))
    lon1 = getattr(a, "lon_deg", None) or math.degrees(getattr(a, "lon", 0.0))
    lat2 = getattr(b, "lat_deg", None) or math.degrees(getattr(b, "lat", 0.0))
    lon2 = getattr(b, "lon_deg", None) or math.degrees(getattr(b, "lon", 0.0))
    phi1, phi2 = math.radians(lat1), math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlon = math.radians(lon2 - lon1)
    sin_dphi = math.sin(dphi / 2.0)
    sin_dlon = math.sin(dlon / 2.0)
    root = sin_dphi * sin_dphi + math.cos(phi1) * math.cos(phi2) * sin_dlon * sin_dlon
    return 6371.0088 * 2.0 * math.atan2(math.sqrt(root), math.sqrt(max(0.0, 1.0 - root)))


class _GeoPoint:
    def __init__(self, lat_deg: float, lon_deg: float) -> None:
        self.lat_deg = lat_deg
        self.lon_deg = lon_deg

    @classmethod
    def from_degrees(cls, lat: float, lon: float) -> "_GeoPoint":
        return cls(lat, lon)


def _install_stub() -> None:
    if "dvoacap" in sys.modules:
        return
    dvoacap_pkg = types.ModuleType("dvoacap")
    path_geometry = types.ModuleType("dvoacap.path_geometry")
    path_geometry.GeoPoint = _GeoPoint
    prediction_engine = types.ModuleType("dvoacap.prediction_engine")
    prediction_engine.PredictionEngine = _FakeEngine
    dvoacap_pkg.path_geometry = path_geometry
    dvoacap_pkg.prediction_engine = prediction_engine
    sys.modules["dvoacap"] = dvoacap_pkg
    sys.modules["dvoacap.path_geometry"] = path_geometry
    sys.modules["dvoacap.prediction_engine"] = prediction_engine


_install_stub()
