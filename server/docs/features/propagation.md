# HF Propagation Predictions

End-to-end architecture for serving VOACAP-style HF propagation predictions
from the activities-server.

## Why a sidecar

The prediction engine we use is
[`dvoacap-python`](https://github.com/skyelaird/dvoacap-python) — an MIT-licensed
Python port of VE3NEA's DVOACAP with bundled CCIR/URSI ionospheric coefficient
data. Embedding it in the Rust server (static musl binary, Alpine image) would
bloat the deployment and break the static build. A small FastAPI sidecar keeps
the Python world isolated and lets the Rust server stay lean.

```
┌──────────────────────┐   HTTP (internal)   ┌─────────────────────────┐
│ activities-server    │ ──────────────────► │ cw-propagation (Python) │
│ /v1/propagation/p2p  │                     │ dvoacap PredictionEngine│
│ /v1/propagation/wheel│                     │ FastAPI + uvicorn       │
└──────────┬───────────┘                     └─────────────────────────┘
           │
           ▼
   propagation_cache
   (Postgres, 24h TTL)
```

The sidecar is exposed only on `127.0.0.1:8090` in production; it has no
public route of its own.

## Runtime layout

| Component | Where | Notes |
|-----------|-------|-------|
| Sidecar source | `server/propagation/` | FastAPI app, Dockerfile, pytest smoke tests |
| Rust handlers | `server/src/handlers/propagation.rs` | Proxy + cache |
| Request / response types | `server/src/models/propagation.rs` | Mirror `app/schemas.py` |
| Cache | `server/src/db/propagation_cache.rs` | Postgres-backed, keyed by SHA-256(normalised body) |
| Migration | `server/migrations/033_propagation_cache.sql` | Creates `propagation_cache` table |
| Local dev | `server/docker-compose.yml` | Adds `propagation` service with healthcheck |
| Prod deploy | `infra/ansible/roles/activities_server/tasks/propagation.yml` | systemd unit, opt-in via `activities_server_propagation_enabled` |

## Enabling the feature

### Local dev (docker-compose)

```bash
cd server
docker compose up --build
```

`server` now depends on `propagation` with a healthcheck and will not start
until the sidecar's `/healthz` returns 200. The sidecar image pulls
`dvoacap-python` from GitHub at build time.

### Production (Ansible)

Set the toggle in `infra/ansible/group_vars/…` or the inventory:

```yaml
activities_server_propagation_enabled: true
```

Then run the activities-server play:

```bash
ansible-playbook site.yml --tags activities-server
```

The role will:

1. Install `python3-venv`, `python3-pip`, `git`.
2. Sync `server/propagation/` to `/opt/cw-propagation/src/`.
3. Create a venv at `/opt/cw-propagation/venv` and `pip install .` from src.
4. Install `cw-propagation.service` (systemd) bound to 127.0.0.1:8090.
5. Wait for the sidecar's `/healthz` before proceeding.
6. Add `PROPAGATION_ENABLED=true` + `PROPAGATION_SERVICE_URL=http://127.0.0.1:8090`
   to `/etc/activities-server.env` so the Rust server knows how to reach it.

## Configuration (activities-server)

| Env var | Default | Purpose |
|---------|---------|---------|
| `PROPAGATION_ENABLED` | `false` | Gate; when false, no `/v1/propagation/*` routes are mounted |
| `PROPAGATION_SERVICE_URL` | `http://127.0.0.1:8090` | Sidecar base URL (no trailing slash) |
| `PROPAGATION_CACHE_TTL_HOURS` | `24` | Cache TTL for both endpoints |
| `PROPAGATION_REQUEST_TIMEOUT_SECS` | `30` | Per-request timeout to the sidecar |

## API

### `POST /v1/propagation/p2p`

Point-to-point HF prediction between two locations.

```bash
curl -s -X POST https://activities.carrierwave.app/v1/propagation/p2p \
  -H 'content-type: application/json' \
  -d '{
    "tx_lat": 42.0, "tx_lon": -71.0,
    "rx_lat": 51.5, "rx_lon": -0.1,
    "month": 4, "utc_hour": 14.0,
    "ssn": 120
  }' | jq
```

Response:

```json
{
  "muf_mhz": 22.0,
  "path": { "distance_km": 5272.1, "bearing_deg": 49.3 },
  "bands": [
    {
      "freq_mhz": 14.1,
      "hop_count": 2,
      "tx_elevation_deg": 12.4,
      "total_loss_db": 132.7,
      "snr_db": 6.1,
      "reliability": 0.71,
      "service_prob": 0.68,
      "multipath_prob": 0.22
    }
  ]
}
```

### `POST /v1/propagation/wheel`

CAP-style polar wheel — predictions at N azimuths around a centre.

```bash
curl -s -X POST https://activities.carrierwave.app/v1/propagation/wheel \
  -H 'content-type: application/json' \
  -d '{
    "lat": 42.0, "lon": -71.0,
    "month": 4, "utc_hour": 14.0,
    "ssn": 120,
    "azimuth_step_deg": 30
  }' | jq
```

Response shape:

```json
{
  "centre_lat": 42.0,
  "centre_lon": -71.0,
  "radius_km": 5000,
  "spokes": [
    {
      "azimuth_deg": 0.0,
      "rx_lat": 86.9,
      "rx_lon": -71.0,
      "bands": [ /* BandPrediction[] */ ]
    }
  ]
}
```

## Caching

Responses are cached in Postgres (`propagation_cache` table) keyed by
`sha256(endpoint + canonical_json(body))`. Canonical JSON sorts object keys so
clients that send the same logical request hit the same row regardless of
field ordering.

A single hour of SSN / UTC hour produces identical predictions for identical
paths, so a 24h default TTL comfortably captures the daily prediction window
without wasting engine cycles.

## Not yet implemented

- **Rate limiting** — public endpoints share the default (none). If abuse
  becomes a problem, wire these under `require_auth`.
- **Background cache purge** — `propagation_cache::purge_expired` exists but
  is not scheduled. Hit-path filtering via `expires_at > now()` keeps stale
  rows from being served; we only need a periodic purge when the table gets
  large enough to matter.
- **CI/CD image** — the Docker image is built locally via docker-compose. A
  GitHub Actions workflow that pushes a versioned image is a natural follow-up.
