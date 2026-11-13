# Tests Index

Integration and unit tests.

## Files

### `tests/integration_test.rs`
Integration tests for API endpoints.

**Current State:**
- Placeholder test only - real integration tests not yet implemented

**Imports (for future use):**
- `axum::body::Body`
- `axum::http::{Request, StatusCode}`
- `tower::ServiceExt`

**Tests:**
- `test_placeholder` - Placeholder that always passes

### `tests/request_id.rs`
Request-correlation middleware (CAR-156). Builds a tiny router through `observability::instrument` and drives it with `tower::ServiceExt::oneshot`; no database.

**Tests:**
- `echoes_supplied_request_id` - Incoming `X-Request-Id` is returned verbatim
- `generates_uuid_when_absent` - Missing header → UUID v4 on the response
- `each_request_gets_a_distinct_id` - Generated ids are unique
- `non_2xx_and_unmatched_routes_still_carry_the_header` - 418 from a handler and the 404 fallback both carry the id
- `json_completion_line_carries_correlation_fields` - Captures the JSON subscriber into a buffer; asserts `timestamp`/`level`/`target`/`message`, `status`, `latency_ms`, and `span.{name,request_id,method,path,route}`; query string is not logged
- `health_and_metrics_completion_lines_are_debug` - `/v1/health` completion line is `DEBUG`
