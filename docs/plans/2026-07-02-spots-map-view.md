# Spots page map view (logbook-web)

**Date:** 2026-07-02 · **Scope:** `server/logbook-web` + a spots-API
enrichment (see revision below).

> **Revision (same day):** live data showed 0/250 spots carry `spotterGrid`
> (POTA/SOTA sources never set it), so the original web-only plan would have
> rendered an empty map — and web receiver ranking was already silently
> unranked. Approved change: `GET /v1/spots` now LEFT JOINs `pota_parks`
> (full catalog with coords) and cached `sota_activation_zones` centroids,
> returning optional `latitude`/`longitude` per spot. The web client prefers
> those over the spotter grid (`spotCoords()`), for both the map and receiver
> ranking. Verifiable on staging only after a server release (local Postgres
> lacks PostGIS).

## Goal

Add a map view option to the web Spots page: (1) a Table | Map toggle for the
spots list, and (2) a Chips | Map toggle in the listen panel's receiver picker.
Visually indicate which KiwiSDR receivers are more likely to hear a given spot.

## Design

### View toggle (spots)

- `Table | Map` segmented toggle in the page header, persisted to
  `localStorage` (`cw-spots-view`).
- Map mode renders a full-width Leaflet map (CARTO dark-matter raster tiles,
  OSM attribution) instead of the table.
- Spots plotted at spotter-grid centers via existing `gridToLatLon`; circle
  markers colored by `bandColor` (matches table band chips).
- Spots without a usable grid are unmappable — show "N of M spots mappable".
- Clicking a spot marker calls the existing `openListenPanel(spot)`
  (auto-connect best receiver, same as the table's Listen button); the map
  then overlays that spot's ranked receivers.

### Likelihood score (`src/spots/likelihood.ts`, pure)

- `score = 0.6 × distanceFactor + 0.4 × snrFactor`
  - `distanceFactor = max(0, 1 − distanceKm / 2000)` (matches the 2000 km
    ranking radius; missing distance → 0)
  - `snrFactor` = `snrHf` (fallback `snrAll`) normalized over 10–30 dB
- Buckets: **good** ≥ 0.6 (green), **fair** ≥ 0.3 (amber), else **weak**
  (gray). Full (`!isAvailable`) or antenna-disconnected receivers render
  dimmed with a red ring regardless of score.
- Visuals only — WASM distance ranking still decides list order and
  auto-connect. Shared Rust untouched.

### Receiver overlay

- Receiver markers are square glyphs (vs spot circles), colored by bucket;
  the connected receiver gets a blue highlight ring; clicking connects
  (same as a chip). Legend explains colors.

### Listen panel picker map

- `Chips | Map` toggle next to the "Receiver" label; map mode is a compact
  (~14 rem) instance of the same component fit to spot + receivers.

### Component

- One reusable `src/components/SpotsMap.tsx` (react-leaflet) with props
  `{spots?, activeSpot?, receivers?, selectedReceiverId?, onSpotClick?,
  onReceiverClick?, compact?}`. Markers are `divIcon`s styled to the CW
  dark theme.

## Dependencies

`leaflet@^1.9`, `react-leaflet@^4.2.1` (React 18-compatible line),
`@types/leaflet`. Server sets no CSP on logbook-web static serving, so tile
requests are not blocked.

## Accepted trade-offs

- Spot positions are approximate (spotter grid, not the spotted station) —
  the same approximation the existing ranking uses.
- Tile requests hit a third-party CDN; the page shows only public spots data.

## Verification

No test runner in logbook-web: `npm run lint` + `npm run build` (tsc) +
manual browser verification of both surfaces.
