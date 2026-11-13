# Carrier Wave Propagation Sidecar

Small FastAPI service that wraps [`dvoacap-python`](https://github.com/skyelaird/dvoacap-python)
to provide HF propagation predictions (MUF, per-band reliability, SNR) to the
main Rust `activities-server` via a tiny internal HTTP contract.

The Rust server is a statically-linked musl binary; pulling Python into that
build path would bloat the image and break the static build, so this runs as
its own service. In production it is managed by systemd
(`propagation.service`) alongside `activities-server`; locally it is brought up
by `docker-compose.yml`.

## Endpoints

| Method | Path | Purpose |
|--------|------|---------|
| `GET`  | `/healthz` | Liveness probe |
| `POST` | `/p2p`     | Point-to-point HF prediction |
| `POST` | `/wheel`   | CAP-style wheel (predictions around a centre) |
| `GET`  | `/docs`    | Interactive OpenAPI UI |

Request/response schemas live in `app/schemas.py`.

## Local development

```bash
cd server/propagation
python -m venv .venv
source .venv/bin/activate
pip install -e ".[dev]"
uvicorn app.main:app --reload --port 8090
```

Then hit it:

```bash
curl -s http://127.0.0.1:8090/healthz
curl -s -X POST http://127.0.0.1:8090/p2p \
  -H 'content-type: application/json' \
  -d '{
    "tx_lat": 42.0, "tx_lon": -71.0,
    "rx_lat": 51.5, "rx_lon": -0.1,
    "month": 4, "utc_hour": 14.0,
    "ssn": 120
  }' | jq
```

## Tests

```bash
pytest
```

The tests monkey-patch the dvoacap engine so they run without the upstream
package installed. The real engine is exercised end-to-end via the Rust
server's integration tests.

## Configuration

| Environment variable | Default | Purpose |
|----------------------|---------|---------|
| `PROPAGATION_LOG_LEVEL` | `INFO` | Python logging level |

The service binds to `0.0.0.0:8090` by default (configurable via uvicorn CLI
flags). In production the systemd unit binds to `127.0.0.1:8090` and is only
reachable from the activities-server process on the same host.
