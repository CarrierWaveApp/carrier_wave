-- SOTA activation-zone polygons, computed from open DEM (Terrarium / AWS
-- Terrain Tiles) using the official "25 vertical metres below the summit" rule.
--
-- There is no summit catalog on the server; the client (which ships the full
-- summitslist.csv) posts visible summit codes + coordinates, and the server
-- computes-and-caches the zone polygon. Rows are keyed by SOTA summit code.
--
-- status: 'pending' (compute enqueued), 'ok' (geometry present), 'none'
-- (compute attempted but no usable zone — e.g. DEM void or runaway fill).
CREATE EXTENSION IF NOT EXISTS postgis;

CREATE TABLE sota_activation_zones (
    summit_code         TEXT PRIMARY KEY,
    status              TEXT NOT NULL DEFAULT 'pending',
    altitude_m          DOUBLE PRECISION,
    geometry            GEOMETRY(Polygon, 4326),
    geometry_simplified GEOMETRY(Polygon, 4326),
    source              TEXT NOT NULL DEFAULT 'terrarium_az',
    computed_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_sota_az_geom_simple
    ON sota_activation_zones USING GIST (geometry_simplified);
CREATE INDEX idx_sota_az_status ON sota_activation_zones (status);
