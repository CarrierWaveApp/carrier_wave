"""Thin wrapper around dvoacap-python's PredictionEngine.

The engine holds cached CCIR/URSI coefficient maps and is not thread-safe, so
all prediction calls are serialised through a global asyncio lock. Predictions
themselves are CPU-bound, so they run in a worker thread to avoid blocking
the FastAPI event loop.
"""

from __future__ import annotations

import asyncio
import logging
import math
from dataclasses import dataclass
from typing import Any, Optional

from dvoacap.path_geometry import GeoPoint  # type: ignore[import-not-found]
from dvoacap.prediction_engine import PredictionEngine  # type: ignore[import-not-found]

from .schemas import (
    BandPrediction,
    DEFAULT_WHEEL_AZIMUTH_STEP_DEG,
    PathGeometry,
    PointToPointRequest,
    PointToPointResponse,
    WheelRequest,
    WheelResponse,
    WheelSpoke,
)

logger = logging.getLogger(__name__)

# Mean Earth radius in km, used for great-circle destination math.
EARTH_RADIUS_KM = 6371.0088


@dataclass(slots=True)
class _EngineHolder:
    """Lazy singleton engine instance guarded by an asyncio lock."""

    engine: Optional[PredictionEngine] = None
    lock: asyncio.Lock = asyncio.Lock()

    def get(self) -> PredictionEngine:
        if self.engine is None:
            logger.info("Initialising dvoacap PredictionEngine (loads CCIR/URSI maps)")
            self.engine = PredictionEngine()
        return self.engine


_holder = _EngineHolder()


def _optional_float(value: Any) -> Optional[float]:
    """Return a float if the value is finite, otherwise None."""
    try:
        numeric = float(value)
    except (TypeError, ValueError):
        return None
    if math.isnan(numeric) or math.isinf(numeric):
        return None
    return numeric


def _optional_int(value: Any) -> Optional[int]:
    try:
        return int(value)
    except (TypeError, ValueError):
        return None


def _band_prediction(freq_mhz: float, raw: Any) -> BandPrediction:
    """Map a dvoacap prediction object into our wire schema, tolerating gaps."""
    signal = getattr(raw, "signal", None)
    return BandPrediction(
        freq_mhz=freq_mhz,
        hop_count=_optional_int(getattr(raw, "hop_count", None)),
        tx_elevation_deg=_optional_float(
            math.degrees(getattr(raw, "tx_elevation", float("nan")))
            if getattr(raw, "tx_elevation", None) is not None
            else None
        ),
        total_loss_db=_optional_float(getattr(signal, "total_loss_db", None)),
        snr_db=_optional_float(getattr(signal, "snr_db", None)),
        reliability=_optional_float(getattr(signal, "reliability", None)),
        service_prob=_optional_float(getattr(raw, "service_prob", None)),
        multipath_prob=_optional_float(getattr(raw, "multipath_prob", None)),
    )


def _great_circle(
    tx_lat: float, tx_lon: float, rx_lat: float, rx_lon: float
) -> PathGeometry:
    """Great-circle distance (km) and bearing (deg, clockwise from north)."""
    phi1 = math.radians(tx_lat)
    phi2 = math.radians(rx_lat)
    dphi = math.radians(rx_lat - tx_lat)
    dlon = math.radians(rx_lon - tx_lon)

    sin_dphi = math.sin(dphi / 2.0)
    sin_dlon = math.sin(dlon / 2.0)
    a = sin_dphi * sin_dphi + math.cos(phi1) * math.cos(phi2) * sin_dlon * sin_dlon
    c = 2.0 * math.atan2(math.sqrt(a), math.sqrt(max(0.0, 1.0 - a)))
    distance_km = EARTH_RADIUS_KM * c

    y = math.sin(dlon) * math.cos(phi2)
    x = math.cos(phi1) * math.sin(phi2) - math.sin(phi1) * math.cos(phi2) * math.cos(
        dlon
    )
    bearing_deg = (math.degrees(math.atan2(y, x)) + 360.0) % 360.0

    return PathGeometry(distance_km=distance_km, bearing_deg=bearing_deg)


def _destination_point(
    lat_deg: float, lon_deg: float, bearing_deg: float, distance_km: float
) -> tuple[float, float]:
    """Compute a destination lat/lon given a start, bearing, and distance."""
    ang = distance_km / EARTH_RADIUS_KM
    phi1 = math.radians(lat_deg)
    lam1 = math.radians(lon_deg)
    theta = math.radians(bearing_deg)

    sin_phi2 = math.sin(phi1) * math.cos(ang) + math.cos(phi1) * math.sin(ang) * math.cos(
        theta
    )
    phi2 = math.asin(max(-1.0, min(1.0, sin_phi2)))
    y = math.sin(theta) * math.sin(ang) * math.cos(phi1)
    x = math.cos(ang) - math.sin(phi1) * math.sin(phi2)
    lam2 = lam1 + math.atan2(y, x)

    # Normalise longitude to [-180, 180].
    lon_out = (math.degrees(lam2) + 540.0) % 360.0 - 180.0
    return math.degrees(phi2), lon_out


def _run_prediction(
    engine: PredictionEngine,
    tx_lat: float,
    tx_lon: float,
    rx_lat: float,
    rx_lon: float,
    month: int,
    utc_hour: float,
    ssn: float,
    tx_power_w: float,
    frequencies_mhz: list[float],
) -> tuple[Optional[float], list[BandPrediction]]:
    """Execute a single p2p prediction against the shared engine."""
    engine.params.ssn = ssn
    engine.params.month = month
    engine.params.tx_power = tx_power_w
    engine.params.tx_location = GeoPoint.from_degrees(tx_lat, tx_lon)

    engine.predict(
        rx_location=GeoPoint.from_degrees(rx_lat, rx_lon),
        utc_time=float(utc_hour) / 24.0,
        frequencies=list(frequencies_mhz),
    )

    muf_obj = getattr(engine, "muf_calculator", None)
    muf_value = _optional_float(getattr(muf_obj, "muf", None))
    predictions = list(getattr(engine, "predictions", []) or [])

    bands: list[BandPrediction] = []
    for freq, pred in zip(frequencies_mhz, predictions):
        bands.append(_band_prediction(freq, pred))
    # If the engine returned fewer predictions than frequencies (shouldn't
    # happen, but be defensive), emit empty rows for the tail so clients can
    # still render a table.
    for freq in frequencies_mhz[len(predictions):]:
        bands.append(
            BandPrediction(
                freq_mhz=freq,
                hop_count=None,
                tx_elevation_deg=None,
                total_loss_db=None,
                snr_db=None,
                reliability=None,
                service_prob=None,
                multipath_prob=None,
            )
        )
    return muf_value, bands


async def predict_point_to_point(
    request: PointToPointRequest,
) -> PointToPointResponse:
    """Run a single point-to-point HF prediction."""
    frequencies = request.frequencies_mhz or []

    async with _holder.lock:
        engine = _holder.get()
        muf, bands = await asyncio.to_thread(
            _run_prediction,
            engine,
            request.tx_lat,
            request.tx_lon,
            request.rx_lat,
            request.rx_lon,
            request.month,
            request.utc_hour,
            request.ssn,
            request.tx_power_w,
            frequencies,
        )

    path = _great_circle(request.tx_lat, request.tx_lon, request.rx_lat, request.rx_lon)
    return PointToPointResponse(muf_mhz=muf, path=path, bands=bands)


async def predict_wheel(request: WheelRequest) -> WheelResponse:
    """Run wheel (CAP-style) predictions around a centre point."""
    step_deg = request.azimuth_step_deg or DEFAULT_WHEEL_AZIMUTH_STEP_DEG
    azimuths: list[float] = []
    current = 0.0
    while current < 360.0:
        azimuths.append(current)
        current = round(current + step_deg, 6)

    frequencies = request.frequencies_mhz or []
    spokes: list[WheelSpoke] = []

    async with _holder.lock:
        engine = _holder.get()
        for azimuth in azimuths:
            rx_lat, rx_lon = _destination_point(
                request.lat, request.lon, azimuth, request.radius_km
            )
            _, bands = await asyncio.to_thread(
                _run_prediction,
                engine,
                request.lat,
                request.lon,
                rx_lat,
                rx_lon,
                request.month,
                request.utc_hour,
                request.ssn,
                request.tx_power_w,
                frequencies,
            )
            spokes.append(
                WheelSpoke(
                    azimuth_deg=azimuth,
                    rx_lat=rx_lat,
                    rx_lon=rx_lon,
                    bands=bands,
                )
            )

    return WheelResponse(
        centre_lat=request.lat,
        centre_lon=request.lon,
        radius_km=request.radius_km,
        spokes=spokes,
    )
