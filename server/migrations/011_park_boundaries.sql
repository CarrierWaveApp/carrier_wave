-- Park boundary polygons cache (requires PostGIS extension)
CREATE EXTENSION IF NOT EXISTS postgis;

CREATE TABLE park_boundaries (
    pota_reference  TEXT PRIMARY KEY,
    park_name       TEXT NOT NULL,
    designation     TEXT,
    manager         TEXT,
    acreage         DOUBLE PRECISION,
    match_quality   TEXT NOT NULL,
    geometry        GEOMETRY(MultiPolygon, 4326),
    geometry_simplified GEOMETRY(MultiPolygon, 4326),
    source          TEXT NOT NULL DEFAULT 'pad_us_4',
    fetched_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    matched_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_park_boundaries_geom ON park_boundaries USING GIST (geometry);
CREATE INDEX idx_park_boundaries_geom_simple ON park_boundaries USING GIST (geometry_simplified);
