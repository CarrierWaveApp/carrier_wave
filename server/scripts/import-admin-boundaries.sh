#!/usr/bin/env bash
#
# Import US administrative boundaries (states + counties) into the
# admin_boundaries table from the US Census cartographic boundary files
# (public domain, ~1:500k generalized — small and map-friendly).
#
# Run ONCE after migration 042 (and again only when the Census publishes a new
# vintage — admin boundaries change at most once a decade). There is no
# background aggregator for this data.
#
# Requirements: GDAL (ogr2ogr), psql, unzip, curl.
# Usage:
#   DATABASE_URL=postgres://user:pass@host/db ./import-admin-boundaries.sh
#   # or rely on PG* env vars (PGHOST/PGUSER/PGDATABASE/PGPASSWORD)
#
# Override the vintage year with YEAR=2023 (default below).
set -euo pipefail

YEAR="${YEAR:-2023}"
BASE="https://www2.census.gov/geo/tiger/GENZ${YEAR}/shp"
STATE_ZIP="cb_${YEAR}_us_state_500k.zip"
COUNTY_ZIP="cb_${YEAR}_us_county_500k.zip"
# Stored-geometry simplification tolerance (degrees, ~Douglas–Peucker).
SIMPLIFY="${SIMPLIFY:-0.002}"

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT
cd "$WORKDIR"

if [[ -n "${DATABASE_URL:-}" ]]; then
    PG="$DATABASE_URL"
else
    PG="PG:dbname=${PGDATABASE:-carrier_wave}"
fi

echo "==> Downloading Census cartographic boundary files (${YEAR})"
curl -fsSLO "${BASE}/${STATE_ZIP}"
curl -fsSLO "${BASE}/${COUNTY_ZIP}"
unzip -oq "$STATE_ZIP"
unzip -oq "$COUNTY_ZIP"

echo "==> Loading shapefiles into PostGIS staging tables"
ogr2ogr -f PostgreSQL "$PG" "cb_${YEAR}_us_state_500k.shp" \
    -nln _stage_admin_states -overwrite -lco GEOMETRY_NAME=geom \
    -t_srs EPSG:4326 -nlt MULTIPOLYGON
ogr2ogr -f PostgreSQL "$PG" "cb_${YEAR}_us_county_500k.shp" \
    -nln _stage_admin_counties -overwrite -lco GEOMETRY_NAME=geom \
    -t_srs EPSG:4326 -nlt MULTIPOLYGON

echo "==> Normalizing into admin_boundaries"
psql "${DATABASE_URL:-}" <<SQL
BEGIN;

DELETE FROM admin_boundaries;

-- States: GEOID is the 2-digit state FIPS; NAME is the state name.
INSERT INTO admin_boundaries
    (id, kind, name, state_fips, state_name, fips, geometry, geometry_simplified, source)
SELECT
    'state:' || s.geoid,
    'state',
    s.name,
    s.statefp,
    s.name,
    s.geoid,
    ST_Multi(s.geom),
    ST_Multi(ST_SimplifyPreserveTopology(s.geom, ${SIMPLIFY})),
    'census_cb_${YEAR}'
FROM _stage_admin_states s;

-- Counties: GEOID is the 5-digit state+county FIPS; join states for the
-- parent state name so the client can label "County, State".
INSERT INTO admin_boundaries
    (id, kind, name, state_fips, state_name, fips, geometry, geometry_simplified, source)
SELECT
    'county:' || c.geoid,
    'county',
    c.name,
    c.statefp,
    s.name,
    c.geoid,
    ST_Multi(c.geom),
    ST_Multi(ST_SimplifyPreserveTopology(c.geom, ${SIMPLIFY})),
    'census_cb_${YEAR}'
FROM _stage_admin_counties c
LEFT JOIN _stage_admin_states s ON s.statefp = c.statefp;

DROP TABLE _stage_admin_states;
DROP TABLE _stage_admin_counties;

COMMIT;
SQL

echo "==> Done. Row counts:"
psql "${DATABASE_URL:-}" -c \
    "SELECT kind, COUNT(*) FROM admin_boundaries GROUP BY kind ORDER BY kind;"
