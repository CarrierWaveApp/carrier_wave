"""FastAPI entry point for the Carrier Wave propagation sidecar."""

from __future__ import annotations

import logging
import os

from fastapi import FastAPI, HTTPException

from . import __version__
from .engine import predict_point_to_point, predict_wheel
from .schemas import (
    HealthResponse,
    PointToPointRequest,
    PointToPointResponse,
    WheelRequest,
    WheelResponse,
)

logging.basicConfig(
    level=os.environ.get("PROPAGATION_LOG_LEVEL", "INFO"),
    format="%(asctime)s %(levelname)s %(name)s: %(message)s",
)

app = FastAPI(
    title="Carrier Wave Propagation Sidecar",
    version=__version__,
    docs_url="/docs",
    redoc_url=None,
    openapi_url="/openapi.json",
)


@app.get("/healthz", response_model=HealthResponse)
async def healthz() -> HealthResponse:
    """Liveness probe. Does not initialise the prediction engine."""
    return HealthResponse(status="ok", engine="dvoacap", version=__version__)


@app.post("/p2p", response_model=PointToPointResponse)
async def p2p(request: PointToPointRequest) -> PointToPointResponse:
    """Run a point-to-point HF propagation prediction."""
    try:
        return await predict_point_to_point(request)
    except ValueError as err:
        raise HTTPException(status_code=422, detail=str(err)) from err
    except Exception as err:  # pragma: no cover - defensive
        logging.exception("p2p prediction failed")
        raise HTTPException(status_code=500, detail="prediction engine failure") from err


@app.post("/wheel", response_model=WheelResponse)
async def wheel(request: WheelRequest) -> WheelResponse:
    """Run a CAP-style propagation wheel around a centre point."""
    try:
        return await predict_wheel(request)
    except ValueError as err:
        raise HTTPException(status_code=422, detail=str(err)) from err
    except Exception as err:  # pragma: no cover - defensive
        logging.exception("wheel prediction failed")
        raise HTTPException(status_code=500, detail="prediction engine failure") from err
