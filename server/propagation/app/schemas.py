"""Request/response models for the propagation API."""

from __future__ import annotations

from typing import Optional

from pydantic import BaseModel, Field, field_validator

# Amateur HF bands (centre frequencies in MHz) used when a caller does not
# supply an explicit frequency list.
DEFAULT_HF_BANDS_MHZ: list[float] = [
    1.9,  # 160m
    3.6,  # 80m
    5.3,  # 60m
    7.1,  # 40m
    10.1,  # 30m
    14.1,  # 20m
    18.1,  # 17m
    21.1,  # 15m
    24.9,  # 12m
    28.3,  # 10m
]

# Default radius used for wheel predictions (km).
DEFAULT_WHEEL_RADIUS_KM: float = 5000.0

# Default azimuth step used for wheel predictions (degrees).
DEFAULT_WHEEL_AZIMUTH_STEP_DEG: float = 15.0


def _default_band_list() -> list[float]:
    return list(DEFAULT_HF_BANDS_MHZ)


class PointToPointRequest(BaseModel):
    """Inputs for a single point-to-point HF prediction."""

    tx_lat: float = Field(..., ge=-90.0, le=90.0)
    tx_lon: float = Field(..., ge=-180.0, le=180.0)
    rx_lat: float = Field(..., ge=-90.0, le=90.0)
    rx_lon: float = Field(..., ge=-180.0, le=180.0)
    month: int = Field(..., ge=1, le=12)
    utc_hour: float = Field(..., ge=0.0, lt=24.0)
    ssn: float = Field(..., ge=0.0, le=400.0)
    tx_power_w: float = Field(100.0, gt=0.0, le=10_000.0)
    frequencies_mhz: list[float] = Field(default_factory=_default_band_list)

    @field_validator("frequencies_mhz", mode="before")
    @classmethod
    def _default_frequencies(cls, value: Optional[list[float]]) -> list[float]:
        if value is None or len(value) == 0:
            return _default_band_list()
        for freq in value:
            if not 0.5 <= float(freq) <= 60.0:
                raise ValueError("frequencies_mhz entries must be within 0.5..60 MHz")
        return value


class BandPrediction(BaseModel):
    """Per-frequency prediction output."""

    freq_mhz: float
    hop_count: Optional[int]
    tx_elevation_deg: Optional[float]
    total_loss_db: Optional[float]
    snr_db: Optional[float]
    reliability: Optional[float]
    service_prob: Optional[float]
    multipath_prob: Optional[float]


class PathGeometry(BaseModel):
    """Great-circle path metadata."""

    distance_km: float
    bearing_deg: float


class PointToPointResponse(BaseModel):
    """Response for /p2p."""

    muf_mhz: Optional[float]
    path: PathGeometry
    bands: list[BandPrediction]


class WheelRequest(BaseModel):
    """Inputs for a CAP-style propagation wheel."""

    lat: float = Field(..., ge=-90.0, le=90.0)
    lon: float = Field(..., ge=-180.0, le=180.0)
    month: int = Field(..., ge=1, le=12)
    utc_hour: float = Field(..., ge=0.0, lt=24.0)
    ssn: float = Field(..., ge=0.0, le=400.0)
    tx_power_w: float = Field(100.0, gt=0.0, le=10_000.0)
    radius_km: float = Field(DEFAULT_WHEEL_RADIUS_KM, gt=100.0, le=20_000.0)
    azimuth_step_deg: float = Field(
        DEFAULT_WHEEL_AZIMUTH_STEP_DEG, gt=1.0, le=90.0,
    )
    frequencies_mhz: list[float] = Field(default_factory=_default_band_list)

    @field_validator("frequencies_mhz", mode="before")
    @classmethod
    def _default_frequencies(cls, value: Optional[list[float]]) -> list[float]:
        if value is None or len(value) == 0:
            return _default_band_list()
        for freq in value:
            if not 0.5 <= float(freq) <= 60.0:
                raise ValueError("frequencies_mhz entries must be within 0.5..60 MHz")
        return value


class WheelSpoke(BaseModel):
    """Predictions at a single azimuth from the centre."""

    azimuth_deg: float
    rx_lat: float
    rx_lon: float
    bands: list[BandPrediction]


class WheelResponse(BaseModel):
    """Response for /wheel."""

    centre_lat: float
    centre_lon: float
    radius_km: float
    spokes: list[WheelSpoke]


class HealthResponse(BaseModel):
    """Response for /healthz."""

    status: str
    engine: str
    version: str
