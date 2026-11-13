"""Smoke tests for the propagation sidecar API."""

from __future__ import annotations

from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def test_healthz() -> None:
    response = client.get("/healthz")
    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "ok"
    assert body["engine"] == "dvoacap"


def test_p2p_returns_per_band_predictions() -> None:
    response = client.post(
        "/p2p",
        json={
            "tx_lat": 42.0,
            "tx_lon": -71.0,
            "rx_lat": 51.5,
            "rx_lon": -0.1,
            "month": 4,
            "utc_hour": 14.0,
            "ssn": 120,
        },
    )
    assert response.status_code == 200, response.text
    body = response.json()
    assert body["muf_mhz"] == 22.0
    assert 5000 < body["path"]["distance_km"] < 6000
    # Default band list has ten entries (160m..10m).
    assert len(body["bands"]) == 10
    # Each band must be a valid prediction row.
    for band in body["bands"]:
        assert "freq_mhz" in band
        assert band["hop_count"] in (1, 2)


def test_p2p_rejects_out_of_range_lat() -> None:
    response = client.post(
        "/p2p",
        json={
            "tx_lat": 500.0,
            "tx_lon": 0.0,
            "rx_lat": 0.0,
            "rx_lon": 0.0,
            "month": 1,
            "utc_hour": 0.0,
            "ssn": 100,
        },
    )
    assert response.status_code == 422


def test_wheel_produces_azimuth_spokes() -> None:
    response = client.post(
        "/wheel",
        json={
            "lat": 42.0,
            "lon": -71.0,
            "month": 4,
            "utc_hour": 14.0,
            "ssn": 120,
            "azimuth_step_deg": 45,
            "radius_km": 3000,
        },
    )
    assert response.status_code == 200, response.text
    body = response.json()
    # 360 / 45 = 8 azimuths starting at 0.
    assert len(body["spokes"]) == 8
    assert body["spokes"][0]["azimuth_deg"] == 0
    # Each spoke must have per-band rows.
    assert len(body["spokes"][0]["bands"]) == 10
    # Destinations should not equal the centre.
    first = body["spokes"][0]
    assert (first["rx_lat"], first["rx_lon"]) != (body["centre_lat"], body["centre_lon"])
