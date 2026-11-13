# iMessage Enriched Text — Design

**Status:** Design
**Author:** Claude + user
**Date:** 2026-04-07
**Scope:** Rich link previews for callsigns, park references, QSOs, and activations
shared from Carrier Wave. Works in iMessage, Mail, Notes, Slack, Discord, and
anywhere else `LPLinkMetadata` / OpenGraph is rendered.

## Goals

1. Sharing a callsign, park ref, QSO, or activation from Carrier Wave produces a
   **rich, informative preview** in any app that renders links.
2. Recipients **without Carrier Wave installed** still see a useful preview (via
   OpenGraph fallback served by the Rust backend).
3. Recipients **with Carrier Wave installed** tap the preview and deeplink into
   the app at the relevant context (universal links).
4. Zero gimmicks — every preview should answer "why should I care about this?"
   in one glance.

## Non-goals

- iMessage app extension (`MSMessage` / sticker pack). Deferred to a later spec.
- Automatic detection of bare callsigns typed into Messages by the user. We only
  enrich links that originated from a Carrier Wave share action.
- Server-side persistence of user log data. The backend only sees public
  reference data (callsign → DXCC, park ref → name/coords).

## URL Scheme

All enriched links are **universal links** on a single host:

```
https://carrierwave.app/link/<kind>/<identifier>[?params]
```

| Kind        | Example                                              |
|-------------|------------------------------------------------------|
| Callsign    | `https://carrierwave.app/link/call/W1AW`             |
| Park        | `https://carrierwave.app/link/park/US-0791`          |
| QSO         | `https://carrierwave.app/link/qso/<opaque-token>`    |
| Activation  | `https://carrierwave.app/link/act/<opaque-token>`    |

**Why universal links and not a custom scheme?**
- Rich previews require a fetchable HTTPS URL for OpenGraph fallback.
- Universal links open in-app for installed users, fall through to the web page
  otherwise. Custom schemes (`carrierwave://`) do neither.
- Apple's `associated-domains` entitlement handles the in-app routing.

**QSO / Activation opaque tokens:**
- Client generates a short random token (e.g. base62, 10 chars).
- Client encodes the QSO/activation payload into the URL fragment
  (`#d=<base64url>`), **not** the path. Fragments are never sent to the server,
  so the backend never sees private log data.
- The path token is only used as an OpenGraph cache key on the server (and can
  be a hash of the fragment for dedup).

### Payload fragment format

```
#d=<base64url(zstd(json))>
```

JSON schema for a QSO:
```json
{
  "v": 1,
  "kind": "qso",
  "c": "W1AW",          // their call
  "me": "KD9LSV",       // my call
  "b": "20m",
  "m": "SSB",
  "f": 14205000,
  "rs": "59",
  "rr": "59",
  "t": 1712534400,      // unix timestamp
  "g": "FN31pr",        // their grid
  "p": "US-0791",       // park ref (optional)
  "n": "Thanks for the P2P!"  // note (optional, truncated)
}
```

Activation schema (richer):
```json
{
  "v": 1,
  "kind": "act",
  "me": "KD9LSV",
  "p": "US-0791",
  "start": 1712520000,
  "end": 1712534400,
  "qsos": 47,
  "bands": ["40m", "20m", "15m"],
  "modes": ["SSB", "CW"],
  "p2p": 3,
  "dxcc": 5
}
```

Max payload: ~1.5 KB uncompressed. QSO notes are truncated to 140 chars.
Sensitive fields (private notes, comments flagged as private) are omitted.

## Client: iOS

### 1. Share builders

New file: `CarrierWaveCore/Sharing/EnrichedLinkBuilder.swift`

```swift
public enum EnrichedLink {
    case callsign(String)
    case park(String)
    case qso(QSOSnapshot)          // Sendable snapshot, not SwiftData model
    case activation(ActivationSnapshot)

    public var url: URL { /* builds universal link + fragment */ }
    public var title: String { /* e.g. "W1AW — Hiram Percy Maxim Memorial" */ }
    public var subtitle: String { /* e.g. "20m SSB · 59/59 · 2026-04-07 18:00Z" */ }
    public var iconImage: UIImage { /* generated card, see below */ }
}
```

### 2. Generated card images

`CarrierWave/Sharing/LinkPreviewCardRenderer.swift` (iOS app target — uses
`ImageRenderer` + SwiftUI):

- **Callsign card:** large monospace callsign, DXCC flag, grid, optional
  "Worked 3× · Last 20m SSB 2026-03-14" line if the call exists in the local
  log. Dark gradient background matching design language.
- **Park card:** park name, ref, state/province, static mini-map with the park
  pin (uses MapKit snapshot — no network for polygon).
- **QSO card:** both calls, band/mode, signal reports, timestamp, park ref
  badge if present, small world map with a great-circle line.
- **Activation card:** park name, QSO count, duration, band sparkline.

All cards: 1200×630 (OpenGraph standard), also rendered at 400×400 for the
iMessage square thumbnail.

### 3. `LPLinkMetadata` hand-off

`CarrierWave/Sharing/EnrichedLinkItemProvider.swift`:

```swift
final class EnrichedLinkItemProvider: NSObject, UIActivityItemSource {
    let link: EnrichedLink

    func activityViewController(
        _: UIActivityViewController,
        itemForActivityType _: UIActivity.ActivityType?
    ) -> Any? { link.url }

    func activityViewControllerLinkMetadata(
        _: UIActivityViewController
    ) -> LPLinkMetadata? {
        let md = LPLinkMetadata()
        md.originalURL = link.url
        md.url = link.url
        md.title = link.title
        md.imageProvider = NSItemProvider(object: link.iconImage)
        return md
    }
}
```

Share sheet integration points:
- **QSO row long-press → Share** (existing context menu extension)
- **Activation detail → Share button** (existing)
- **Callsign detail view → Share button** (new, small addition)
- **Park detail view → Share button** (new)

### 4. Universal link handling

`CarrierWave/App/CarrierWaveApp.swift` already has `.onOpenURL`. Extend the
router to recognize `/link/call/`, `/link/park/`, `/link/qso/`, `/link/act/`
and push the appropriate detail view. Fragment payload is decoded locally if
present; otherwise the app fetches fresh data (e.g. re-resolve the callsign
against QRZ).

Add to `CarrierWave/Info.plist` the `applinks:carrierwave.app` associated
domain, and publish `.well-known/apple-app-site-association` from the backend.

### 5. Privacy

- Fragment payloads contain log data — **never logged, never sent to analytics**.
- The server sees only the opaque token and public reference data in the path.
- Users can disable enriched sharing in Settings > Privacy (falls back to plain
  text sharing).
- Private notes, QSO comments marked private, and operator name/address are
  never included in payloads.

## Server: Rust backend

New service: `carrier-wave-server/src/link_preview/`

### Endpoints

```
GET /link/call/:callsign
GET /link/park/:park_ref
GET /link/qso/:token
GET /link/act/:token
GET /.well-known/apple-app-site-association
```

All four `/link/*` endpoints return an HTML page with OpenGraph meta tags.
User agents that are "real" browsers get a fuller landing page with a
"Download Carrier Wave" CTA. Crawlers (Facebook, Slack, Twitter, LPLinkMetadata
fetcher) get the minimal OpenGraph HTML.

### OpenGraph tags

```html
<meta property="og:title" content="W1AW — Hiram Percy Maxim Memorial">
<meta property="og:description" content="ARRL HQ · FN31pr · 🇺🇸">
<meta property="og:image" content="https://carrierwave.app/link/call/W1AW/card.png">
<meta property="og:url" content="https://carrierwave.app/link/call/W1AW">
<meta property="og:type" content="website">
<meta property="og:site_name" content="Carrier Wave">
<meta name="twitter:card" content="summary_large_image">
<meta name="apple-itunes-app" content="app-id=6499999999, app-argument=https://carrierwave.app/link/call/W1AW">
```

### Card image generation (`/link/*/card.png`)

- **Callsign cards:** rendered server-side with `resvg` (SVG → PNG). Template
  pulls DXCC info from a pre-loaded lookup (cty.dat), grid from QRZ if we have
  a backend QRZ integration, otherwise just shows the call + flag.
- **Park cards:** templated from POTA reference data (already cached on the
  server per existing POTA integration). Mini-map rendered via static tile
  composition.
- **QSO / Activation cards:** Server returns a **generic** Carrier Wave-branded
  `og:image` (one of two static assets: "Carrier Wave QSO" or "Carrier Wave
  Activation"). The real card is rendered by the recipient, not the server.
  See the resolved decisions section for the full rationale. This means:
  - The web landing page at `/link/qso/:token` ships a small JS bundle that
    decodes `window.location.hash` and renders the card client-side as SVG.
  - Chat app link unfurlers see the generic card.
  - Recipients with Carrier Wave installed get the rich card in-app via the
    universal link route.

### Storage

- **Callsign/park previews:** stateless, generated on demand from `cty.dat` /
  POTA reference cache, CDN-cached by URL indefinitely.
- **QSO/activation previews:** no storage at all. Generic OG images are static
  CDN assets. The web landing page is templated HTML + a static JS bundle.
- **No blob store, no Redis, no per-share state on the server.**

### Rate limiting

Public preview endpoints are unauthenticated but cached aggressively in the
CDN. No upload endpoints exist.

## Universal link verification

`.well-known/apple-app-site-association`:
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

Both bundle IDs are pre-populated in Phase 1 even though CW Sweep wires its
share UI in Phase 4 — this avoids a server redeploy when CW Sweep ships.

Served with `Content-Type: application/json`, no redirect, HTTPS only.

## Rollout

1. **Phase 1 (client-only, no server):** Ship all four share actions
   (callsign, park, QSO, activation) in iOS, producing `LPLinkMetadata` with
   client-rendered card images via the cross-platform `CarrierWaveCore/Sharing/`
   module. URL points at `carrierwave.app/link/...` which 404s for now. Rich
   previews work in Messages because the sender's `LPLinkMetadata` travels
   with the message. Recipients without the app see a broken link if they
   actually tap through — acceptable for internal beta.
2. **Phase 2 (backend OpenGraph for callsign/park + generic OG for QSO/activation):**
   Stand up stateless preview endpoints for callsign and park. Add the two
   static generic OG images for QSO and activation. Now non-app recipients see
   a useful web preview for callsign/park, and a "this is a Carrier Wave link"
   preview for QSO/activation.
3. **Phase 3 (universal link deeplinking + web fallback page):** Publish AASA
   (with both iOS and CW Sweep bundle IDs from day one), add
   `associated-domains` entitlement to iOS, wire `.onOpenURL` router. Ship the
   web landing page with the small JS bundle that decodes the fragment and
   renders QSO/activation cards client-side as SVG. After this phase, non-app
   recipients tapping a QSO/activation link see the real card in their browser.
4. **Phase 4 (CW Sweep wiring):** Add `NSSharingServicePicker` integration to
   CW Sweep contact/QSO context menus, wire macOS universal link handling.
   Almost entirely glue code on top of the existing shared package.
5. **Phase 5 (propagation/live status extras):** "20m open to EU" on callsign
   cards, "Active now" on park cards. Ties into existing solar + spots data.

Each phase is independently shippable and testable. There is no server-side
blob storage in any phase.

## Resolved Decisions

These were open questions in the first draft. Decided 2026-04-07 with the user.

### Callsign card enrichment source — RESOLVED: cty.dat + sharer-embedded data only

The server **never** enriches callsigns from external APIs. Two sources only:

1. **Server side:** Offline `cty.dat` (refreshed quarterly via cron, or bundled
   with the release) provides DXCC entity, flag emoji, CQ/ITU zones. Fully
   deterministic, no rate limits, no external dependencies, no per-user creds.
2. **Client side:** Whatever the sharer already has locally — QRZ cache,
   previous QSO history, local op database — gets embedded into the fragment
   payload as an optional `qrz` sub-object: `{name, grid, qth, country}`.

**Share action behavior:** When the user taps Share on a callsign, the client
triggers a synchronous QRZ lookup (if creds present) before building the card,
so the fragment has fresh data. The user was about to look that callsign up
anyway.

**Why:** Zero ops burden, no external API monitoring, no rate-limit alerting,
trivially explainable privacy story ("we don't look anything up — your card
shows what you know"). Carrier Wave users already have rich QRZ caches for any
callsign they've interacted with, so the fragment is the richest possible
source. Graceful degradation: even a cold share of `VK9XX` still shows
🇦🇺 Christmas Island from `cty.dat`.

### Fragment size budget — RESOLVED: hard 1.5 KB URL ceiling, client-only, always

Every share kind fits in **≤1,500 bytes of total URL**, which is **~1,450
bytes of base64url fragment**, which is **~1,080 bytes of compressed
payload**, which is **~2-3 KB of raw JSON** depending on redundancy.

This ceiling is chosen so that *every* share kind survives every common
transport including QR codes (max ~1,500 bytes for reliable scanning), Discord
embeds, Signal, and Slack — not just iMessage and Mail.

**Implications:**
- Server **never** sees log data, ever, even transiently. Only opaque tokens
  + cty.dat-derived public reference data.
- Activation payloads get aggressive truncation: band/mode arrays capped at 5
  entries, no top-DX list, notes truncated to ~80 chars. The encoder drops
  optional fields one-by-one until it fits, never refuses to share.
- All four share kinds are QR-code-shareable. Field Day "scan this for my
  activation" comes free.
- The fragment encoder exposes a typed "would this overflow?" check; the share
  UI handles overflow by progressive truncation, never by failing.
- There is no "always client-only" privacy toggle because that's the only mode.

Activation truncation order (drop in this sequence until under budget):
1. Drop `notes` field
2. Truncate `bands`/`modes` arrays to 5 entries
3. Drop `dxcc` count
4. Drop `p2p` count
5. Drop `start`/`end`, keep duration only
6. (Last resort) Show generic "Activation by KD9LSV" card with no specifics

### QSO/activation card storage — RESOLVED: hybrid (server cards for callsign/park, fragment-only for QSO/activation)

**Callsign and park cards:** Server-rendered from path data alone (cty.dat +
POTA reference cache). Stateless, fully derivable from URL, CDN-cached
indefinitely. No privacy concerns — all public data.

**QSO and activation cards:** Server **never** stores card PNGs or payloads.
The rich card is rendered fresh by the recipient:

- **Recipient with Carrier Wave installed:** Universal link opens app → app
  decodes fragment → app renders rich card in the detail view they land on.
- **Recipient without the app (browser):** Web landing page ships a small
  (~5 KB) JS bundle that reads `window.location.hash`, decodes the fragment,
  and renders the card client-side as SVG. Includes a "Get Carrier Wave" CTA
  below the card. Fragment never touches the server — it's never sent in HTTP
  requests, only read by the browser locally.
- **Chat app link unfurlers (Slack/Discord/iMessage server-side fetcher):**
  Hit `https://carrierwave.app/link/qso/abc123#d=eyJ2...` → fragment is
  stripped before the request hits the server → server returns OpenGraph HTML
  with a **generic Carrier Wave-branded `og:image`** ("Carrier Wave QSO" or
  "Carrier Wave Activation"), not the actual details. The generic image is a
  static asset, served from CDN, infinite cache.

**Why this is actually better than storing card PNGs:**
- Zero blob storage, zero TTL, zero 404s when previews expire, zero ops cost.
- Server never sees log data **even as opaque image bytes**.
- Chat app link unfurlers (which themselves cache aggressively and are a known
  privacy risk) never see the rich card. Rich details stay between sender and
  intended recipient.
- The generic preview is honest: "this is a Carrier Wave link, click to see"
  rather than spilling the QSO into every #ham-radio channel that scrolls past.

**Tradeoff acknowledged:** Slack/Discord/iMessage previews show generic cards
instead of the real details. This is a feature, not a bug.

### CW Sweep (macOS) inclusion — RESOLVED: cross-platform shared package from day one, iOS-only wiring in Phase 1

The `CarrierWaveCore/Sharing/` module is built **cross-platform** from the
start:
- Card renderer uses SwiftUI `ImageRenderer` (cross-platform on iOS 16+ /
  macOS 13+).
- `LPLinkMetadata` and `LinkPresentation` are cross-platform.
- `EnrichedLinkBuilder`, `EnrichedLinkPayload`, and the card views live in
  `CarrierWaveCore` with **no UIKit imports**. The only platform-specific edge
  is `UIImage` vs `NSImage`, handled by a single `PlatformImage` typealias.
- AASA is **pre-populated with both the iOS and CW Sweep bundle IDs** in
  Phase 1, so adding macOS share UI later doesn't require a server redeploy.

**Phase 1 wires up iOS only.** Share buttons in `UIActivityViewController`,
universal link routing in the iOS app target.

**CW Sweep follow-up (post Phase 1)** is a small glue patch:
- Add a "Share" item to the QSO/contact context menus in CW Sweep
- Instantiate `EnrichedLinkBuilder` (already exists in `CarrierWaveCore`)
- Hand to `NSSharingServicePicker`
- Wire `.onOpenURL` in the macOS app for universal link handling

This is ~1 day of work because all the heavy lifting is already done in the
shared package.

**Discipline rule:** No `import UIKit` in `CarrierWaveCore/Sharing/`. CI lint
rule to enforce.

## Open questions

(None — all resolved.)

## Files to add/change

**New (cross-platform shared package — iOS + CW Sweep, no UIKit):**
- `CarrierWaveCore/Sharing/EnrichedLinkBuilder.swift`
- `CarrierWaveCore/Sharing/EnrichedLinkPayload.swift` (Codable schema + zstd + truncation)
- `CarrierWaveCore/Sharing/LinkPreviewCardRenderer.swift` (SwiftUI ImageRenderer)
- `CarrierWaveCore/Sharing/PlatformImage.swift` (UIImage/NSImage typealias)

**New (iOS app target):**
- `CarrierWave/Sharing/EnrichedLinkItemProvider.swift` (UIActivityItemSource)
- `CarrierWave/App/Routing/UniversalLinkRouter.swift`

**New (server):**
- `carrier-wave-server/src/link_preview/mod.rs`
- `carrier-wave-server/src/link_preview/cards.rs` (callsign + park SVG→PNG only)
- `carrier-wave-server/src/link_preview/opengraph.rs`
- `carrier-wave-server/src/link_preview/aasa.rs` (serves apple-app-site-association)
- `carrier-wave-server/src/link_preview/cty_dat.rs` (DXCC lookup)
- `carrier-wave-server/templates/preview.html` (web landing page + JS card renderer)
- `carrier-wave-server/static/og-qso.png` (generic Carrier Wave QSO card)
- `carrier-wave-server/static/og-activation.png` (generic Carrier Wave Activation card)
- `carrier-wave-server/static/link-card.js` (~5 KB, decodes fragment, renders SVG)

**Changed:**
- `CarrierWave/Views/QSO/QSODetailView.swift` — wire share button
- `CarrierWave/Views/Activation/ActivationDetailView.swift` — wire share button
- `CarrierWave/Views/Callsign/CallsignDetailView.swift` — add share button
- `CarrierWave/Views/Park/ParkDetailView.swift` — add share button
- `CarrierWave/Info.plist` — associated domains entitlement
- `CarrierWave/App/CarrierWaveApp.swift` — router extension
- `CarrierWave/Views/Settings/PrivacySettingsView.swift` — enriched sharing toggle
- `docs/FILE_INDEX.md` — new files
- `CHANGELOG.md` — Unreleased / Added

## Testing

- **Unit:** Payload round-trip (encode → URL → decode), truncation rules,
  privacy filter (private notes excluded).
- **Snapshot:** Card renderer for callsign / park / QSO / activation in light
  and dark mode, short and long values.
- **Integration:** Universal link routing — tap preview, assert correct view
  pushed with correct payload decoded.
- **Manual matrix:** Send each link type through Messages, Mail, Notes, Slack,
  Discord, Signal. Verify preview renders in each and that recipient without
  the app sees the web fallback.
