-- Community satellite status aggregated from amsat.org/status.
-- One row per AMSAT-tracked transmitter (their internal name, e.g.
-- 'SO-50_[FM]'), refreshed wholesale each aggregator cycle.
CREATE TABLE IF NOT EXISTS amsat_status (
    name TEXT PRIMARY KEY,
    norad_id BIGINT,
    last_heard_at TIMESTAMPTZ,
    last_reported_at TIMESTAMPTZ,
    last_report TEXT,
    last_callsign TEXT,
    last_grid TEXT,
    heard_reports_24h INT NOT NULL DEFAULT 0,
    total_reports_24h INT NOT NULL DEFAULT 0,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
