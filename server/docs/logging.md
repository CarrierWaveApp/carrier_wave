# Logging

Structured logs and per-request correlation for the activities server
(CAR-156; audit items T4-2 and T4-10). Code: `src/observability.rs`,
`config::LogFormat` in `src/config.rs`.

## Configuration

| Env var | Default | Values | Notes |
|---|---|---|---|
| `LOG_FORMAT` | `json` | `json`, `pretty`, `compact` (case-insensitive) | Selects the `tracing_subscriber` fmt layer. Unknown values fall back to `json` and log a WARN at startup. Read before the rest of the config so a bad `DATABASE_URL` is still reported in the chosen format. |
| `RUST_LOG` | `info,activities_server=debug` | `tracing_subscriber::EnvFilter` directives | Unchanged. Production and staging set `info`. |

Both are read from the process environment and from `.env` (dotenv runs
before the subscriber is installed). The Ansible env templates
(`infra/ansible/roles/activities_server*/templates/*.env.j2`) set
`LOG_FORMAT` to `json` unless `activities_server_log_format` /
`activities_server_staging_log_format` is overridden.

`pretty` (multi-line, coloured) and `compact` (one line of text) are for a
human watching a terminal in local dev; `.env.example` ships `pretty`.

## JSON line shape

One object per line, event fields flattened to the top level, the enclosing
span under `span`:

```json
{
  "timestamp": "2026-09-26T18:41:02.123456Z",
  "level": "INFO",
  "target": "activities_server::observability",
  "message": "request completed",
  "status": 200,
  "latency_ms": 3.412,
  "span": {
    "name": "request",
    "request_id": "0d5d0c7a-3c1e-4d1b-9c5b-2f7d8e6a1b23",
    "method": "GET",
    "path": "/v1/challenges/17",
    "route": "/v1/challenges/:id"
  }
}
```

### Envelope (every line)

| Field | Meaning |
|---|---|
| `timestamp` | RFC 3339 UTC, microsecond precision. |
| `level` | `TRACE` / `DEBUG` / `INFO` / `WARN` / `ERROR`. |
| `target` | Rust module path that emitted the event (`activities_server::handlers::sync`, `sqlx::query`, …). Filter on it with `RUST_LOG`. |
| `message` | The event's message text. |
| *event fields* | Any `key = value` pairs from the `tracing::info!(...)` call, flattened alongside `message`. |
| `span` | Fields of the innermost span the event was emitted in, plus `name`. Absent when the event was outside any span (startup, aggregators). Ancestor spans are not listed. |

### The `request` span

Every HTTP request runs inside `info_span!("request", …)`, so *any* line a
handler or the DB layer emits while serving it carries these under `span`:

| Field | Meaning |
|---|---|
| `request_id` | Correlation id. Taken from the incoming `X-Request-Id` header when present (truncated to 128 chars in the log only), otherwise a freshly generated UUID v4. Always echoed back on the response as `X-Request-Id`. |
| `method` | HTTP method. |
| `path` | Request path. The query string is deliberately not logged (it can carry OAuth codes, invite tokens). Path segments such as `/invite/:token` do appear; treat logs as sensitive. |
| `route` | Matched axum route pattern (`/v1/challenges/:id`). Absent for static assets, `/logbook`, and unmatched paths. Use this for grouping; `path` for a single request. |

### The completion line

Exactly one per request, `message = "request completed"`, emitted after the
response is produced:

| Field | Meaning |
|---|---|
| `status` | HTTP status code (number). |
| `latency_ms` | Wall-clock time from the middleware seeing the request to the response headers being ready, milliseconds (float, µs precision). |

Level is `INFO`, except `/v1/health` and `/metrics` which log at `DEBUG` so
uptime probes and Prometheus scrapes stay out of `RUST_LOG=info` output.
Responses short-circuited by the rate limiter (429) or CORS still get a
completion line and an `X-Request-Id` — the middleware sits outermost.

The Prometheus HTTP metrics (`http_requests_total`,
`http_request_duration_seconds`) are recorded by a separate middleware on the
`/v1` sub-router (`src/metrics.rs`) and are not affected by any of this.

## Correlating a client report

Ask for the `X-Request-Id` from the failing response (the iOS app and
`logbook-web` can surface it from response headers; nginx passes it through
untouched). Then on the host:

```sh
# Everything the server logged for that request, in order.
journalctl -u activities-server -o cat --since -1h \
  | jq -c 'select(.span.request_id == "0d5d0c7a-3c1e-4d1b-9c5b-2f7d8e6a1b23")'
```

Clients that want to correlate proactively can send their own
`X-Request-Id` (any header-safe string); it is used as-is.

## Reading logs on the host

The service runs under systemd and writes JSON to stdout, so journald stores
one JSON document per entry. `-o cat` strips journald's own prefix so `jq`
gets clean input.

```sh
# Follow live traffic, one line per request.
journalctl -u activities-server -o cat -f \
  | jq -r 'select(.message == "request completed")
           | "\(.timestamp) \(.status) \(.latency_ms)ms \(.span.method) \(.span.path) \(.span.request_id)"'

# Errors and warnings in the last day.
journalctl -u activities-server -o cat --since -1d \
  | jq -c 'select(.level == "ERROR" or .level == "WARN")'

# Slowest 20 requests this hour.
journalctl -u activities-server -o cat --since -1h \
  | jq -c 'select(.message == "request completed")' \
  | jq -s 'sort_by(-.latency_ms) | .[:20][] | {latency_ms, status, route: .span.route, request_id: .span.request_id}'

# Status histogram per route.
journalctl -u activities-server -o cat --since -1h \
  | jq -r 'select(.message == "request completed") | "\(.span.route // .span.path) \(.status)"' \
  | sort | uniq -c | sort -rn | head

# Everything a particular subsystem said.
journalctl -u activities-server -o cat --since -6h \
  | jq -c 'select(.target | startswith("activities_server::aggregators"))'
```

Staging is the `activities-server-staging` unit. Lines that are not JSON
(panics, `RUST_BACKTRACE` output) make `jq` complain; add `-R 'fromjson? //
empty'` style guards if you are piping unknown ranges:
`jq -R 'fromjson? | select(.level == "ERROR")'`.

## Shipping to Loki / Grafana Cloud (recommended next step — not deployed)

Nothing here is provisioned yet. The recommended shape, once a Grafana Cloud
stack (or self-hosted Loki) exists:

1. Run **Grafana Alloy** (successor to promtail) on the Hetzner host as a
   systemd unit, reading journald directly — no file tailing, no log rotation
   to manage, and journald's own metadata (`_SYSTEMD_UNIT`, `PRIORITY`)
   becomes labels.
2. Keep the Loki **label set tiny** (`host`, `unit`, `env`) and let Loki's
   JSON parser pull `level`, `status`, `span.route` etc. at query time.
   High-cardinality values (`request_id`, `path`) must never be labels.
3. Credentials (Loki URL, tenant id, API key) belong in the Ansible vault,
   templated into Alloy's config.

Sketch of the Alloy config (`/etc/alloy/config.alloy`):

```river
loki.source.journal "activities" {
  max_age    = "12h"
  path       = "/var/log/journal"
  matches    = "_SYSTEMD_UNIT=activities-server.service"
  labels     = { host = "hetzner-1", env = "prod", unit = "activities-server" }
  forward_to = [loki.process.json.receiver]
}

loki.source.journal "activities_staging" {
  max_age    = "12h"
  path       = "/var/log/journal"
  matches    = "_SYSTEMD_UNIT=activities-server-staging.service"
  labels     = { host = "hetzner-1", env = "staging", unit = "activities-server-staging" }
  forward_to = [loki.process.json.receiver]
}

loki.process "json" {
  // Promote only the low-cardinality level so alerts/queries can filter
  // cheaply; everything else stays in the line for `| json` at query time.
  stage.json {
    expressions = { level = "level" }
  }
  stage.labels {
    values = { level = "" }
  }
  forward_to = [loki.write.grafana_cloud.receiver]
}

loki.write "grafana_cloud" {
  endpoint {
    url = "https://logs-prod-XXX.grafana.net/loki/api/v1/push"
    basic_auth {
      username = "<grafana cloud stack id>"
      password = "<vaulted API key>"
    }
  }
}
```

Equivalent promtail (`scrape_configs`) if Alloy is not wanted:

```yaml
scrape_configs:
  - job_name: journal
    journal:
      max_age: 12h
      labels: { host: hetzner-1 }
    relabel_configs:
      - source_labels: ['__journal__systemd_unit']
        regex: 'activities-server(-staging)?\.service'
        action: keep
      - source_labels: ['__journal__systemd_unit']
        target_label: unit
    pipeline_stages:
      - json: { expressions: { level: level } }
      - labels: { level: }
```

Useful LogQL once shipped:

```logql
# 5xx rate per route, 5m windows
sum by (route) (rate({unit="activities-server"} | json | status >= 500 | route=~".+" [5m]))

# p95 latency per route
quantile_over_time(0.95, {unit="activities-server"} | json | message="request completed" | unwrap latency_ms [5m]) by (span_route)

# One request end to end
{unit="activities-server"} | json | span_request_id="0d5d0c7a-…"
```

Alerting on `level="ERROR"` and on `status>=500` rate are the first two
rules worth adding. Retention: 14–30 days is plenty; logs contain paths with
invite tokens (see `path` above) so do not extend it casually.

## Testing

- `tests/request_id.rs` — drives a router through `observability::instrument`
  with `tower::ServiceExt::oneshot`: header echo, UUID generation,
  uniqueness, 404/teapot propagation, and captures the JSON subscriber into
  a buffer to assert the exact completion-line fields and the DEBUG level for
  `/v1/health`.
- Unit tests in `src/config.rs` (`LogFormat` parsing/default) and
  `src/observability.rs` (quiet-path set, request-id truncation).
