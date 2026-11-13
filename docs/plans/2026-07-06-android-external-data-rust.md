# Android External Data downloads, shared in Rust

**Goal:** Android gets every local data download iOS's External Data screen
offers, with download/parse/store logic living in the shared Rust core so
iOS can later swap its Swift caches onto the same code.

## Dataset inventory (from iOS `ExternalDataView`)

| Dataset | Source | Format | TTL | Rust today |
|---|---|---|---|---|
| SCP | supercheckpartial.com/MASTER.SCP | text, ETag | 7d | ✅ `ScpApi` (Android already uses) |
| Contest defs | `/v1/contests` | JSON v0.3 | 24h | ✅ `ContestApi` (Android not wired) |
| POTA parks | pota.app/all_parks_ext.csv | CSV 8 cols | 14d | table `pota_park` exists; download/parse is Swift |
| SOTA summits | sotadata.org.uk/summitslist.csv | CSV 17 cols | 30d | none |
| WWFF refs | wwff.co/wwff-data/wwff_directory.csv | CSV 26 cols | 30d | none |
| FCC callsigns | github jsvana/fcc-uls-etl releases: `amateur-callsigns.json` + `.db.gz` | JSON meta + gzip SQLite | 7d | none |
| Equipment catalog | `/v1/equipment/catalog` (bearer, ETag) | JSON | 24h | none |
| SOTA zones | POST `/v1/sota/zones` (500 summits/chunk) | GeoJSON | manual only | none |

## Architecture

New **`ReferenceDataApi`** (cw-ffi, `#[uniffi::export(async_runtime = "tokio")]`),
constructed with `(store: Arc<FieldStore>, base_url: String, data_dir: String)`.
`data_dir` holds the FCC SQLite (a plain, separate DB — not inside the
encrypted cw-store).

- `refresh_pota_parks(force)` → CSV → `pota_park` table (existing upsert)
- `refresh_sota_summits(force)` → CSV (expired summits filtered at parse,
  like iOS) → new `sota_summit` table
- `refresh_wwff_directory(force)` → CSV → new `wwff_reference` table
  (fields = iOS `WWFFReference`: reference/name/program/status/continent/
  iota/grid/lat/lon/iucn/country/region/dxcc)
- `refresh_equipment_catalog(bearer, force)` → ETag-conditional JSON → kv
  blob (mirrors iOS file + UserDefaults ETag)
- `refresh_fcc(force)` → metadata JSON, sha256 short-circuit (touch
  freshness without re-download when hash matches), else download `.db.gz`,
  verify sha256 of compressed bytes, gunzip, atomically replace
  `data_dir/amateur-callsigns.db`; schema_version > 1 guard
- `refresh_sota_zones()` → chunked POST from `sota_summit` rows → new
  `sota_zone` table (`code`, `altitude_m`, `geojson`); returns
  resolved/pending counts (server computes zones lazily)
- `statuses()` → per-dataset `{count, fetched_at}` for the UI
- `fcc_lookup(callsign)` → name/city/state/grid/class from the FCC SQLite
- Dataset freshness/ETag bookkeeping in cw-store kv (same pattern as
  `EnrichmentApi`)

Layer split: parsers in **cw-domain** (`csv.rs` quoted-line parser +
`reference_csv.rs` column mappers, unit-tested); HTTP in **cw-net**
(`reference_data.rs`, `fcc.rs`, equipment in `enrichment`-style client;
WWFF gets a dedicated 120 s/300 s-timeout client; CSV fetches send the
Accept/User-Agent headers and reject HTML challenge pages, as iOS does);
storage in **cw-store** migration v10.

## Android UI

`ExternalDataScreen` reached from the More/Account screen: Download All +
one row per dataset (count, "updated N ago", refresh button, error line) —
the iOS section layout. `CwApp` gains `referenceDataApi` and `contestApi`
(rebuilt on base-URL change). SCP row reuses the existing `ScpApi`.

## Deferred (documented, not silently dropped)

- Android *consumers* of the new data (park/summit/WWFF pickers, FCC
  callsign overlays, zone map overlays, awards rollups) — this phase ships
  download + cache + status only.
- iOS swap onto `ReferenceDataApi` (separate effort; storage/formats are
  designed to be faithful so the swap is mechanical).
- SCP "worked ≥2×" augmentation from QSO history (iOS-only today).
