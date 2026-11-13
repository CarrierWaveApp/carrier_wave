-- US administrative boundaries (states + counties) for the activity planning map.
-- Mirrors the park_boundaries pattern: full + simplified PostGIS MultiPolygon,
-- viewport (bbox) queries via a GIST index on the simplified geometry.
--
-- Data is loaded once from the US Census cartographic boundary files
-- (public domain) via scripts/import-admin-boundaries.sh — there is no
-- background aggregator, since admin boundaries change at most once a decade.
CREATE EXTENSION IF NOT EXISTS postgis;

CREATE TABLE admin_boundaries (
    id              TEXT PRIMARY KEY,    -- 'state:06' or 'county:06037'
    kind            TEXT NOT NULL,       -- 'state' | 'county'
    name            TEXT NOT NULL,       -- 'California' / 'Los Angeles'
    state_fips      TEXT,                -- '06'
    state_name      TEXT,                -- parent state name (counties only)
    fips            TEXT NOT NULL,       -- '06' (state) or '06037' (county)
    geometry            GEOMETRY(MultiPolygon, 4326),
    geometry_simplified GEOMETRY(MultiPolygon, 4326),
    source          TEXT NOT NULL DEFAULT 'census_cb',
    fetched_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_admin_boundaries_geom_simple
    ON admin_boundaries USING GIST (geometry_simplified);
CREATE INDEX idx_admin_boundaries_kind ON admin_boundaries (kind);
