# iMessage Enriched Text — Server Spec (separate `carrier-wave-server` repo)

**Status:** Spec / handoff
**Companion to:** [2026-04-07-imessage-enriched-text-design.md](2026-04-07-imessage-enriched-text-design.md)
**Date:** 2026-04-07

This document describes the server-side endpoints for the enriched text
feature. The server lives in a **separate repository** (`carrier-wave-server`,
Rust) — this monorepo only contains the iOS / macOS / shared Swift code.
Implement these endpoints in that repo, not here.

## Overview

The server's job is **deliberately small**. It only needs to:

1. Serve an HTML landing page with OpenGraph metadata for `/link/*` URLs.
2. Render PNG `og:image` cards for **callsign and park** previews (public
   data only — DXCC from `cty.dat`, park info from POTA reference cache).
3. Serve **two static generic OG images** for QSO and activation previews.
   The actual rich card is rendered by the recipient's browser using the
   URL fragment, which the server never sees.
4. Serve `.well-known/apple-app-site-association` for universal link
   verification.

The server **never**:
- Stores QSO or activation data, in any form.
- Accepts payload uploads from clients.
- Looks up callsigns from external APIs (QRZ, HamQTH, etc.).
- Tracks users.

All log data lives in the URL fragment, which is never sent in HTTP requests.

## Endpoints

### `GET /link/call/:callsign`

Returns HTML with OpenGraph metadata for a callsign preview.

**Path parameter:**
- `:callsign` — uppercase call, with `/` replaced by `-` (e.g. `KD9LSV-P`).

**Response:** HTML (`text/html; charset=utf-8`), with `Cache-Control: public,
max-age=86400, s-maxage=604800`.

**OG metadata** rendered into `<head>`:
```html
<meta property="og:type" content="website">
<meta property="og:site_name" content="Carrier Wave">
<meta property="og:url" content="https://carrierwave.app/link/call/W1AW">
<meta property="og:title" content="W1AW — United States">
<meta property="og:description" content="DXCC: United States · CQ Zone 5 · ITU Zone 8">
<meta property="og:image" content="https://carrierwave.app/link/call/W1AW/card.png">
<meta property="og:image:width" content="1200">
<meta property="og:image:height" content="630">
<meta name="twitter:card" content="summary_large_image">
<meta name="apple-itunes-app" content="app-id=APPID, app-argument=https://carrierwave.app/link/call/W1AW">
```

**Page body** is a minimal landing page with a "Get Carrier Wave" CTA. JS
on the page reads `window.location.hash` and, if a fragment payload is
present, decodes it and renders the richer client-side card (sharer's
QRZ-cached name, grid, etc.).

### `GET /link/call/:callsign/card.png`

Server-rendered PNG card for callsign previews. **Sharer-embedded data is
not used here** (the request comes from chat-app unfurlers, which strip the
fragment) — only public data from `cty.dat`.

**Content:** 1200×630 PNG. Layout:
- Large monospace callsign
- DXCC entity name + flag emoji
- CQ/ITU zones in small text
- "Carrier Wave" branding strip at bottom

**Implementation:** SVG template with placeholder substitution → rasterize
with `resvg`. Cache in CDN by URL forever (cty.dat updates trigger a path
change via a version query string when needed).

### `GET /link/park/:reference`

HTML + OpenGraph metadata for a park preview. Path param is a POTA
reference like `US-0791`.

**OG metadata:**
```html
<meta property="og:title" content="US-0791 — Hiram Percy Maxim Memorial">
<meta property="og:description" content="Newington, CT · United States">
<meta property="og:image" content="https://carrierwave.app/link/park/US-0791/card.png">
```

Park info pulled from the existing POTA parks cache (already used by the
server for other features). If the reference is unknown, return a 404 with
a generic "Park not found" page.

### `GET /link/park/:reference/card.png`

Server-rendered PNG. 1200×630. Layout:
- Park reference + name
- State / region
- Mini static map (composed from OSM tiles) with pin marker
- Carrier Wave branding

### `GET /link/qso/:token`

HTML landing page for QSO previews. **The token is opaque** — the server
treats it as a 10-character random string and doesn't look anything up.

**OG metadata** uses a **generic static image**:
```html
<meta property="og:title" content="Carrier Wave QSO">
<meta property="og:description" content="A QSO shared from Carrier Wave. Open in the app for full details.">
<meta property="og:image" content="https://carrierwave.app/static/og-qso.png">
```

The page body includes:
1. "Get Carrier Wave" CTA
2. A `<div id="card-container">` placeholder
3. A small JS bundle (`/static/link-card.js`) that:
   - Reads `window.location.hash` (e.g. `#d=eyJ2...`)
   - Decodes the base64url JSON payload (mirrors
     `EnrichedLinkPayload.swift` decoder logic)
   - Renders the card as inline SVG into `#card-container`

This is the **only** way QSO details ever appear on the web — they come
from the URL the user opened in their browser, never from a server-side
store.

### `GET /link/act/:token`

Same as `/link/qso/:token` but with activation-specific generic OG image
and JS rendering branch.

### `GET /static/og-qso.png` / `GET /static/og-activation.png`

Static 1200×630 PNGs. "Carrier Wave QSO" / "Carrier Wave Activation"
branded card with no specific data. Served from CDN, infinite cache.

### `GET /static/link-card.js`

The ~5 KB JS bundle that decodes URL fragments and renders cards
client-side. Includes implementations of:

- base64url decode (mirrors Swift)
- JSON schema decode for all four payload kinds
- SVG card renderers for callsign / park / qso / activation

**Important:** The JS schema **must stay in sync** with
`EnrichedLinkPayload.swift` and `EnrichedLinkPayload+QSO.swift` in this
monorepo. Any field rename or addition needs a coordinated change. The
schema version (`v` field) lets the JS gracefully handle older/newer
payloads.

### `GET /.well-known/apple-app-site-association`

Universal link verification file. Served as `application/json`, no
redirects, HTTPS only.

```json
{
  "applinks": {
    "apps": [],
    "details": [
      {
        "appID": "TEAMID.app.carrierwave.CarrierWave",
        "paths": ["/link/*"]
      },
      {
        "appID": "TEAMID.app.carrierwave.CWSweep",
        "paths": ["/link/*"]
      }
    ]
  }
}
```

Replace `TEAMID` with the actual Apple Developer team ID before deploying.

## Required server-side resources

- **`cty.dat`** — DXCC lookup table, refreshed quarterly via cron from
  https://www.country-files.com/cty/. Bundled into the binary or mounted
  at runtime.
- **POTA parks reference cache** — already exists on the server for other
  features.
- **Static OSM tile cache** — for park mini-map composition. Optional;
  fallback to a flat-color geographic gradient when tiles are unavailable.

## Schema version compatibility

The Swift `EnrichedLinkPayload.schemaVersion` constant (currently `1`) is
embedded in every fragment. When the schema changes:

1. Bump `schemaVersion` in
   `CarrierWaveCore/Sources/CarrierWaveCore/Sharing/EnrichedLinkPayload.swift`
2. Update the JS decoder in `static/link-card.js` to handle both versions
3. Old links continue to work because the JS reads `v` and dispatches
4. Field renames go through a deprecation window (one major release)

## Privacy properties (re-stated for the server team)

- The server **must never** log fragment contents. Fragments aren't sent
  in HTTP requests, but if a misconfigured proxy adds them, they should be
  redacted at the access-log layer.
- The server **must never** store anything per-token beyond the static
  card PNGs (which are stateless / public).
- All endpoints are unauthenticated. Rate limiting is by IP at the CDN.
- CORS is **not** required because the JS runs from the same origin.

## Test plan (server-side)

1. `curl https://carrierwave.app/link/call/W1AW` → returns HTML with the
   OpenGraph tags above.
2. `curl https://carrierwave.app/link/call/W1AW/card.png` → returns a
   1200×630 PNG.
3. `curl https://carrierwave.app/link/qso/abc1234567` → returns the
   landing page with the generic QSO OG image (token is opaque, any
   value works).
4. Open `https://carrierwave.app/link/qso/abc1234567#d=<valid-payload>`
   in a browser → JS decodes the fragment, renders the rich card.
5. Slack/Discord/iMessage unfurl test for each kind → verify generic
   `og:image` for QSO/activation, real `og:image` for callsign/park.
6. AASA verification: `curl https://carrierwave.app/.well-known/apple-app-site-association`
   returns JSON with both bundle IDs and `Content-Type: application/json`.
