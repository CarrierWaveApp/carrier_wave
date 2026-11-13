# Historic Trails Index

National Historic Trail geometry cache: fetches from NPS ArcGIS FeatureServer, caches in PostGIS, serves GeoJSON.

## Files

### `migrations/012_historic_trails.sql`
Database schema for historic trails cache and seed catalog.

**Tables:**
- `historic_trails` - Cached trail line geometries (trail_reference PK, PostGIS MultiLineString columns, match metadata)
- `historic_trail_catalog` - Seed catalog of 19 congressionally-designated National Historic Trails

**Indexes:**
- `idx_historic_trails_geom` - GIST index on full-resolution geometry
- `idx_historic_trails_geom_simple` - GIST index on pre-simplified geometry

### `src/models/historic_trail.rs`
Data structures for historic trails feature.

**Query params:**
- `struct TrailsQuery` - refs, bbox, limit, simplify parameters

**DB row types:**
- `struct HistoricTrailRow` - Row from historic_trails with geometry as GeoJSON string

**API response types:**
- `struct TrailFeature` - GeoJSON Feature with properties
- `struct TrailProperties` - reference, name, designation, managing_agency, length_miles, state, match_quality, source
- `struct TrailsResponse` - GeoJSON FeatureCollection with meta
- `struct TrailsMeta` - matched count and unmatched_refs list
- `struct TrailStatusResponse` - Sync progress and completion stats

**NPS ArcGIS API types (upstream JSON):**
- `struct NpsTrailResponse` - Response from NPS Trails FeatureServer query
- `struct NpsTrailFeature` - Single feature with attributes and geometry
- `struct NpsTrailAttributes` - NPS field mapping (Trail_Name, Mang_Agency, Designation, Length_MI, State)

### `src/db/historic_trails.rs`
Database queries for historic trails.

**API support:**
- `async fn get_trails_by_refs()` - Batch lookup by trail references (simplified geometry)
- `async fn get_trail_by_ref()` - Single trail lookup (full-resolution geometry)
- `async fn get_trails_by_bbox()` - Spatial query with pre-simplified geometry
- `async fn get_trails_by_bbox_simplified()` - Spatial query with custom simplification tolerance

**Aggregator support:**
- `async fn upsert_trail()` - Insert/update trail with PostGIS geometry conversion
- `async fn count_trails()` - Count total cached trails
- `async fn get_unfetched_trails()` - Get catalog trails without cached geometry
- `async fn get_stale_trails()` - Get trails older than N days for refresh
- `async fn get_trail_status()` - Get sync status statistics
- `async fn increment_trail_errors()` - Increment consecutive error counter for a failed trail
- `async fn reset_trail_consecutive_errors()` - Reset all error counters at cycle start

**Helper types:**
- `struct TrailStatusRow` - Status statistics from DB
- `struct UnfetchedTrail` - Trail needing geometry fetch (reference, name, location, agency, ntir_service)
- `struct StaleTrail` - Stale trail needing refresh (includes ntir_service)

### `src/aggregators/historic_trails.rs`
Background aggregator that fetches trail geometries from NPS ArcGIS API with NTIR fallback.

**Exports:**
- `struct HistoricTrailsConfig` - batch_size, cycle_hours, stale_days
- `async fn poll_loop()` - Main loop: fetch unfetched trails, refresh stale, sleep

**Internal functions:**
- `async fn fetch_trail()` - Fetch geometry for single trail (USGS name match → fuzzy → NTIR fallback)
- `async fn query_by_name()` - Query NPS Trails MapServer by name
- `async fn query_ntir_service()` - Query NTIR per-trail Feature Service (all features, merged)
- `async fn save_feature()` - Save NPS feature to database
- `fn normalize_trail_name()` - Strip common suffixes for search
- `fn urlencoded()` - URL-encode for ArcGIS REST API

**Data sources:**
- Primary: USGS National Map MapServer layer 11 (`carto.nationalmap.gov`)
- Fallback: NTIR ArcGIS Feature Services (`services1.arcgis.com/fBc8EJBxQRMcHlei`)

### `src/handlers/historic_trails.rs`
HTTP handlers for historic trails API endpoints.

**Exports:**
- `async fn get_trails()` - GET /v1/trails?refs=...&bbox=...
- `async fn get_trail()` - GET /v1/trails/:reference
- `async fn get_trail_status()` - GET /v1/trails/status
