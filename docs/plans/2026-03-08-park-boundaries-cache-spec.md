# Park Boundary Polygons Cache — Data Spec for activities-server

**Date:** 2026-03-08
**Purpose:** Spec for a server-side cache that serves POTA park boundary polygons to the iOS app. The activities-server fetches, processes, and caches boundary data so the app doesn't need to download or process large GIS datasets directly.

---

## Overview

The iOS app already has every POTA park's **point location** (lat/lon) via `all_parks_ext.csv`. What's missing is **boundary polygons** — the actual park outlines. These come from the USGS Protected Areas Database (PAD-US), which is large and complex. The server should act as a lightweight proxy that matches PAD-US boundaries to POTA references and serves simplified GeoJSON to the app.

## Data Sources

### Primary: PAD-US via ArcGIS REST API

The USGS hosts PAD-US as ArcGIS Feature Services. These can be queried for GeoJSON directly.

**Service endpoints (PAD-US 4.x on ArcGIS Online):**

| Layer | URL |
|-------|-----|
| Federal manager | `https://services.arcgis.com/P3ePLMYs2RVChkJx/arcgis/rest/services/Protected_Areas_by_Manager_Federal/FeatureServer/0` |
| State manager | `https://services.arcgis.com/P3ePLMYs2RVChkJx/arcgis/rest/services/Protected_Areas_by_Manager_State/FeatureServer/0` |

**Query pattern:**
```
{service_url}/query?where={sql}&outFields={fields}&f=geojson&outSR=4326
```

**Key PAD-US fields for matching:**

| Field | Type | Purpose |
|-------|------|---------|
| `Loc_Nm` | String | Location/park name (primary match field) |
| `Unit_Nm` | String | Management unit name |
| `Mang_Name` | String | Manager name (e.g. "NPS", "USFS") |
| `Mang_Type` | String | Manager type (FED, STAT, LOC, etc.) |
| `Des_Tp` | String | Designation type (NP, NF, SP, SRA, etc.) |
| `GAP_Sts` | String | GAP status code (1-4, conservation intent) |
| `State_Nm` | String | State name |
| `FeatClass` | String | Feature class (Fee, Designation, Easement, etc.) |
| `GIS_Acres` | Double | Area in acres |
| `SHAPE` | Polygon/MultiPolygon | The boundary geometry |

### Secondary: POTA Park Directory

**Source:** `https://pota.app/all_parks_ext.csv`

| Column | Type | Example |
|--------|------|---------|
| reference | String | `US-0001` |
| name | String | `Acadia National Park` |
| active | Bool | `1` |
| entityId | Int | `291` (USA) |
| locationDesc | String | `US-ME` |
| latitude | Double | `44.35` |
| longitude | Double | `-68.21` |
| grid | String | `FN54` |

### Tertiary: OpenStreetMap (international parks)

For non-US parks, OSM has a tagging convention: `communication:amateur_radio:pota=<reference>`. This could be used as a future data source via the Overpass API for international boundary support.

## Matching Strategy: POTA Reference → PAD-US Boundary

There is **no direct key** linking POTA references to PAD-US records. Matching must use a combination of:

### 1. Name + Location Matching (primary)

```
POTA: US-0001 "Acadia National Park" in US-ME
PAD-US query: WHERE Loc_Nm LIKE '%Acadia%' AND State_Nm = 'Maine'
```

- Normalize names: strip "National Park", "State Park", "National Forest", etc. suffixes before fuzzy matching
- Use the POTA `locationDesc` state code (e.g. `US-ME` → `Maine`) to filter PAD-US by `State_Nm`

### 2. Spatial Proximity (fallback)

When name matching is ambiguous or fails:
- Use the POTA park's lat/lon centroid as a spatial query against PAD-US
- Query: `geometry={lon},{lat}&geometryType=esriGeometryPoint&spatialRel=esriSpatialRelIntersects`
- Pick the result whose centroid is nearest the POTA coordinate
- Validate by checking name similarity (Levenshtein or token overlap) to avoid false matches

### 3. Designation Type Hints

Map POTA name patterns to PAD-US `Des_Tp`:
| POTA name contains | PAD-US `Des_Tp` |
|---------------------|-----------------|
| "National Park" | NP |
| "National Forest" | NF |
| "State Park" | SP |
| "National Wildlife Refuge" | NWR |
| "State Forest" | SF |
| "National Recreation Area" | NRA |
| "Wilderness" | WA |

### 4. Manual Override Table

Maintain a small JSON/TOML table for parks that fail automated matching:
```json
{
  "US-0001": { "pad_us_query": "Loc_Nm = 'Acadia National Park'", "notes": "exact match" },
  "US-4567": { "pad_us_id": "...", "notes": "name mismatch, manually verified" }
}
```

## Server API Design

### `GET /v1/parks/boundaries`

Batch endpoint — the app requests boundaries for parks visible in the current map viewport.

**Request:**
```
GET /v1/parks/boundaries?refs=US-0001,US-0045,US-1234
```

Or spatial query:
```
GET /v1/parks/boundaries?bbox=-70.5,43.0,-67.0,45.0&limit=50
```

**Parameters:**

| Param | Type | Description |
|-------|------|-------------|
| `refs` | String | Comma-separated POTA references (max 20) |
| `bbox` | String | Bounding box `west,south,east,north` (WGS84) |
| `limit` | Int | Max results for bbox query (default 50, max 100) |
| `simplify` | Float | Tolerance in degrees for polygon simplification (default 0.0005 ≈ ~50m) |

**Response (GeoJSON FeatureCollection):**
```json
{
  "type": "FeatureCollection",
  "features": [
    {
      "type": "Feature",
      "geometry": {
        "type": "Polygon",
        "coordinates": [[[lon, lat], [lon, lat], ...]]
      },
      "properties": {
        "reference": "US-0001",
        "name": "Acadia National Park",
        "designation": "NP",
        "manager": "NPS",
        "acreage": 49075.26,
        "match_quality": "exact",
        "source": "pad_us_4"
      }
    }
  ],
  "meta": {
    "matched": 3,
    "unmatched_refs": [],
    "cache_age_hours": 12
  }
}
```

**`match_quality` values:** `exact` (name + location), `fuzzy` (name similarity > 0.8), `spatial` (point-in-polygon), `manual` (override table), `none` (no boundary found — omitted from features).

### `GET /v1/parks/boundaries/{reference}`

Single park lookup with full-resolution boundary.

**Response:** Single GeoJSON Feature (same schema as above, no simplification applied).

## Server-Side Caching & Storage

### PostgreSQL Schema

```sql
CREATE TABLE park_boundaries (
    pota_reference  TEXT PRIMARY KEY,       -- "US-0001"
    park_name       TEXT NOT NULL,
    designation     TEXT,                    -- PAD-US Des_Tp
    manager         TEXT,                    -- PAD-US Mang_Name
    acreage         DOUBLE PRECISION,
    match_quality   TEXT NOT NULL,           -- exact, fuzzy, spatial, manual
    geometry        GEOMETRY(MultiPolygon, 4326),  -- PostGIS
    geometry_simplified GEOMETRY(MultiPolygon, 4326), -- pre-simplified for list views
    source          TEXT NOT NULL DEFAULT 'pad_us_4',
    fetched_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    matched_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_park_boundaries_geom ON park_boundaries USING GIST (geometry);
CREATE INDEX idx_park_boundaries_geom_simple ON park_boundaries USING GIST (geometry_simplified);
```

### Cache Lifecycle

| Step | Frequency | Action |
|------|-----------|--------|
| **Full sync** | Monthly (cron) | Re-download `all_parks_ext.csv`, attempt matching for all unmatched US parks |
| **On-demand** | Per request | If a requested `ref` has no row, attempt PAD-US lookup, cache result |
| **Simplification** | At insert time | Pre-compute `geometry_simplified` using ST_Simplify(geom, 0.001) |
| **Staleness** | 90 days | Re-query PAD-US for rows older than 90 days (boundaries rarely change) |
| **CSV refresh** | Weekly | Check for new/removed POTA parks, add rows for new ones |

### Polygon Simplification

Raw PAD-US polygons can be very detailed (thousands of vertices for large parks). The server should:

1. Store the full-resolution polygon in `geometry`
2. Pre-compute a simplified version in `geometry_simplified` using PostGIS `ST_Simplify(geom, 0.001)` (~100m tolerance)
3. For bbox queries, serve simplified geometries by default
4. For single-park detail, serve full resolution
5. Allow client to request custom simplification via `simplify` param

Target: each simplified polygon should be under ~5KB of GeoJSON coordinates for mobile performance.

## Data Volume Estimates

| Metric | Estimate |
|--------|----------|
| Total US POTA parks | ~18,000 |
| Parks with matchable PAD-US boundary | ~12,000–15,000 (some small sites may lack PAD-US records) |
| Average simplified polygon size | ~2–5 KB GeoJSON |
| Total cache size (simplified) | ~40–75 MB |
| Total cache size (full resolution) | ~200–500 MB |
| Typical bbox query (city-level viewport) | 5–30 parks |
| Typical bbox response size | 50–150 KB |

## Rate Limiting

| Endpoint | Limit |
|----------|-------|
| `GET /v1/parks/boundaries` (batch) | 30/min per device |
| `GET /v1/parks/boundaries/{ref}` | 60/min per device |

## Client Integration Notes

The iOS app would:

1. Use `POTAParksCache` point data for annotation pins (already works)
2. When the user opens a parks map view, fetch boundaries for visible parks via bbox query
3. Cache boundary GeoJSON locally (Core Data blob or file cache, keyed by reference)
4. Render polygons as MapKit overlays (`MKPolygon`)
5. Re-fetch on region change (debounced, 500ms after map stops moving)
6. Local cache TTL: 30 days (boundaries don't change often)

## Non-US Parks (Future)

For international parks, potential data sources:

| Region | Source | Notes |
|--------|--------|-------|
| Canada (VE-xxxx) | Canadian Protected Areas Database (CPAD) | Similar to PAD-US, GeoJSON available |
| Europe | OpenStreetMap `communication:amateur_radio:pota` tag | Query via Overpass API |
| Global | World Database on Protected Areas (WDPA) | UN-maintained, downloadable |

The server schema supports this via the `source` field. International support can be added incrementally without API changes.

## Open Questions

1. **Match rate** — What percentage of POTA parks will successfully match to PAD-US records? Should be testable with a sample of ~100 parks.
2. **Multi-polygon parks** — Some parks (e.g. national forests) have disjoint polygons. PAD-US may return multiple records for one POTA reference. The server should merge them into a single MultiPolygon.
3. **Duplicate PAD-US records** — PAD-US has overlapping feature classes (Fee vs Designation). Prefer `FeatClass = 'Designation'` for the canonical boundary, fall back to `Fee`.
4. **Trail-only parks** — Some POTA parks are trails (e.g. Appalachian Trail segments). These would be LineString geometries, not polygons. Consider supporting `MultiLineString` geometry type as well.

## Sources

- [PAD-US Data Download (USGS)](https://www.usgs.gov/programs/gap-analysis-project/science/pad-us-data-download)
- [PAD-US Web Services (USGS)](https://www.usgs.gov/programs/gap-analysis-project/science/pad-us-web-services)
- [PAD-US Federal FeatureServer](https://services.arcgis.com/P3ePLMYs2RVChkJx/arcgis/rest/services/Protected_Areas_by_Manager_Federal/FeatureServer)
- [PAD-US State FeatureServer](https://services.arcgis.com/P3ePLMYs2RVChkJx/arcgis/rest/services/Protected_Areas_by_Manager_State/FeatureServer)
- [potamap.ol (GitHub)](https://github.com/cwhelchel/potamap.ol) — reference implementation for PAD-US → POTA matching
- [potamap_park_updater (GitHub)](https://github.com/cwhelchel/potamap_park_updater) — POTA park GeoJSON generator
- [POTA Park Directory CSV](https://pota.app/all_parks_ext.csv)
- [ArcGIS REST API Query Reference](https://developers.arcgis.com/rest/services-reference/enterprise/query-feature-service-layer/)
