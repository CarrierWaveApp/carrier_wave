-- Propagation prediction cache.
--
-- Entries are keyed by the SHA-256 of the normalised request body sent to the
-- propagation sidecar. Because both /p2p and /wheel responses are a pure
-- function of their inputs for a given SSN / month / UTC hour, we can cache
-- them cheaply and avoid re-running the dvoacap engine for repeat queries.
CREATE TABLE propagation_cache (
    cache_key TEXT PRIMARY KEY,
    endpoint TEXT NOT NULL,  -- 'p2p' or 'wheel'
    response JSONB NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at TIMESTAMPTZ NOT NULL
);

CREATE INDEX idx_propagation_cache_expires_at ON propagation_cache (expires_at);
CREATE INDEX idx_propagation_cache_endpoint ON propagation_cache (endpoint, created_at DESC);
