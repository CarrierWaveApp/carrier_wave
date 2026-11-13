# CW Field Remote Mode — Design Sketch

**Date:** 2026-05-02
**Status:** Draft (pre-implementation; no Linear issue yet)

iOS phone app (CW Field) acts as a thin remote head for the desk-side macOS app (CW Sweep). Sweep owns the radio, scope, audio, FT8 engine, spots, and log. Field shows curated views, fires commands, and receives push when away from the LAN.

This doc sketches the wire protocol, the Sweep publish/command surface, the iOS client shape, and the v1 feature cut. It is **not** an implementation plan — it is the surface to react to before we open issues.

---

## Goals (v1)

- One pairing flow, one wire protocol, one shared message namespace usable across all remote features.
- LAN-first; cloud relay is opt-in for off-LAN push notifications only.
- Phone is dumb: no decoding, no rig CAT, no spot aggregation, no log writes that bypass Sweep.
- Headless FT8 monitoring + tap-to-QSY spot feed + voice/CW keyer trigger ship together — they exercise enough of the protocol to validate it.

## Non-goals (v1)

- TX audio (voice TX from phone). Latency + mic chain is a separate problem.
- Full panadapter mirroring. Decimated scope strip is a stretch goal, not v1.
- Multi-tenant cloud relay. Single user, single Sweep instance.
- Browser / web client. Native iOS only.
- Replacing MultiOp. Remote Op runs alongside.

---

## Existing primitives we lean on

Sweep already ships most of the publishers and command sinks we need. We are **not** building these from scratch:

| Need | Existing component |
|------|---------------------|
| Bonjour-advertised TCP server with Codable messages | `Services/MultiOp/MultiOpServer.swift` (actor) |
| iOS Bonjour discovery + connect/disconnect | `Services/MultiOp/MultiOpClient.swift` (in iOS via shared package pattern) |
| Radio state + tune RPC | `RadioManager.tuneToSpot` (`RadioManager+Tune.swift`), `RadioSession` actor |
| Spot stream | `SpotAggregator` (publishes UnifiedSpot/EnrichedSpot at @MainActor) |
| FT8 decode + TX state | `MacFT8SessionManager`, `FT8TXEvent`, `FT8TXState` |
| Voice/CW keyer trigger | `MacroEngine` (F1–F12 with ESM sequencing), `VoiceKeyerService` |
| POTA self-spot | `POTASpotService` |
| iOS↔macOS handoff (deep linking) | `HandoffService` (NSUserActivity) |
| Push entitlement | Sweep already has Push Notifications entitlement (CKSyncEngine); iOS app already in same APNs ecosystem |
| Off-device push broker | `server/` (Rust) — already routes user-scoped data and accepts iOS device tokens via existing telemetry pipe |

**Implication:** the Remote Op transport is a sibling to `MultiOpServer`/`MultiOpClient`, not a fresh stack. Same pattern, different message namespace, different role.

---

## Architecture overview

```
┌───────────────────────────┐                   ┌─────────────────────────────┐
│  iOS — CW Field           │                   │  macOS — CW Sweep           │
│  ─────────────────        │                   │  ─────────────────          │
│  RemoteSweepClient (actor)│◄────TLS+WS────────┤ RemoteOpServer (actor)      │
│   – Bonjour browse        │   _cwsweep._tcp   │  – Bonjour advertise        │
│   – Pairing (QR)          │                   │  – Token validate           │
│   – Topic subscribe       │                   │  – Topic dispatch           │
│   – Command send          │                   │  – Command dispatch         │
│   – Reconnect/backoff     │                   │                             │
│                           │                   │  Publishers:                │
│  ObservableState:         │                   │   RadioManager  ──► state   │
│   – RemoteRadioState      │                   │   SpotAggregator ─► spots   │
│   – RemoteSpotFeed        │                   │   MacFT8SessionMgr ► ft8    │
│   – RemoteFT8Feed         │                   │   QSOLog ──────────► qso    │
│   – RemoteAlertsRules     │                   │                             │
│                           │                   │  Command sinks:             │
│  Views:                   │                   │   RadioManager.tuneToSpot   │
│   – RemoteHomeView        │                   │   MacroEngine.fire(slot:)   │
│   – RemoteSpotsView       │                   │   VoiceKeyerService.play    │
│   – RemoteFT8View         │                   │   POTASpotService.spot      │
│   – RemoteKeyerPad        │                   │   Mac FT8 TX pause/resume   │
└───────────────────────────┘                   └─────────────────────────────┘
                  ▲                                         │
                  │  APNs                                   │  HTTPS (events)
                  │                                         ▼
              ┌───┴──────────────────────────────────────────┐
              │  activities-server (Rust)                    │
              │   – /v1/remote/devices (register APNs token) │
              │   – /v1/remote/events (Sweep posts alerts)   │
              │   – APNs forwarder                           │
              └──────────────────────────────────────────────┘
```

### Transport

- **Protocol:** WebSocket over TLS, framed JSON messages. Reasoning:
  - WebSocket fits Network.framework cleanly (`URLSessionWebSocketTask` on iOS, `NWConnection` ws on macOS).
  - JSON keeps debugging trivial; the volume isn't enough to need binary framing in v1. Audio (later) will bypass JSON entirely.
  - `MultiOpProtocol` already uses Codable — same pattern, same headache budget.
- **Discovery:** Bonjour `_cwsweep._tcp` advertised by `RemoteOpServer`. `MultiOpServer` already advertises a different service type — they coexist.
- **Off-LAN:** v1 is LAN-only for command/state. Push is the only off-LAN path; see "Push pipeline" below.
- **Reconnect:** exponential backoff, 1s → 30s cap. Resubscribe on reconnect; server replays the last `state_snapshot` per topic the client was subscribed to.

### Pairing

1. Sweep generates a one-time 6-digit code + ephemeral keypair, displays a QR code.
2. Field scans QR (camera permission already in app), submits code to Sweep over the LAN.
3. Sweep validates, returns a long-lived bearer token bound to a friendly device name ("Jay's iPhone").
4. Token stored in iOS Keychain. Sweep maintains a paired-devices list in its UserDefaults / a Codable plist; user can revoke.
5. No account system in v1 — pairing is local and physical (you have to see the QR).

---

## Topic taxonomy

Two directions: **publish** (Sweep → Field) and **command** (Field → Sweep). Subscriptions are explicit so the phone only burns bytes on what it shows.

### Publish topics

| Topic | Rate | Payload (sketch) |
|-------|------|------------------|
| `radio.state` | on-change | `{ vfo, freqHz, mode, split{...}?, tx, ptt, profileId }` |
| `radio.meters` | 5 Hz when shown, 0.5 Hz when backgrounded | `{ s, swr, power, alc, temp }` |
| `radio.command_log` | on-change | last N CAT TX/RX lines (mirrors `RadioCommandLog`) |
| `spots.feed` | on-event | `EnrichedSpot` subset (`call, freqHz, mode, source, age, needed, snr?`) |
| `spots.bandmap` | on-change | grouped per-band counts for badge UI |
| `ft8.session_state` | on-change | `{ running, band, mode, qsoState{...}, ourCallTx?, txSequence }` |
| `ft8.decodes` | on-event | `{ utc, dB, hz, message, dxcc?, distanceKm?, neededFlags? }` |
| `ft8.audio` | on-change | `{ overload, level, inputName }` (reuses iOS `FT8AudioOverloadTracker` shape) |
| `qso.appended` | on-event | tail of just-logged QSO (for confirmation toast) |
| `session.stats` | 1 Hz when shown | `{ qsosLastHour, totalQSOs, byBand{...}, byMode{...}, score? }` |
| `activation.context` | on-change | `{ kind: pota|sota|tota|none, refs[], gridSubsquare? }` |
| `keyer.slots` | on-change | per-mode slot list `{ mode, slots: [{ index, label, kind: cw|voice }] }` |
| `radio.tx_capabilities` | on-change | `{ canPauseFT8, canPlayKeyer, canTransmit }` |

### Command topics

| Command | Effect | Sweep sink |
|---------|--------|------------|
| `radio.tune` `{freqHz, mode?, vfo?}` | QSY current radio | `RadioManager.tuneToSpot` (extract base) |
| `radio.split` `{enabled, freqHz?}` | Set/clear split | new RadioSession method |
| `keyer.play` `{mode, slot}` | Fire macro slot | `MacroEngine.fire(slot:)` / `VoiceKeyerService` |
| `ft8.tx_pause` / `ft8.tx_resume` | Pause TX queue (don't kill session) | `MacFT8SessionManager` |
| `ft8.tx_send_73` | Inject 73 into next TX cycle | `MacFT8SessionManager` |
| `spot.self_post` `{network, comment?}` | Post to POTA/SOTA self-spot | `POTASpotService` (extend for SOTA) |
| `qso.append` `{call, mode, freqHz, rstSent, rstRcvd, ...}` | Append a QSO from the phone | new sink in `LoggingSessionManager` |
| `subscribe` / `unsubscribe` `{topic, filter?}` | Manage subscriptions | server bookkeeping |
| `meters.tier` `{tier: full|low|off}` | Bandwidth tier hint | server adjusts publish rates |
| `alerts.rules.set` `[ Rule ]` | Push notification rules | persisted on Sweep + uploaded to activities-server for off-LAN |

### Filters worth supporting in v1

- `spots.feed` filter: `bands[]`, `modes[]`, `sources[]`, `neededOnly`, `minSNR`.
- `ft8.decodes` filter: `bands[]`, `myCallOnly`, `watchlist[]`.

---

## Sweep subsystem mapping (who publishes what)

```
RadioManager  ──── publishes ──► radio.state, radio.meters, radio.command_log
              ──── accepts  ◄── radio.tune, radio.split

SpotAggregator ─── publishes ──► spots.feed, spots.bandmap

MacFT8SessionManager ─ publishes ──► ft8.session_state, ft8.decodes, ft8.audio
                       accepts  ◄── ft8.tx_pause, ft8.tx_resume, ft8.tx_send_73

MacroEngine    ──── accepts  ◄── keyer.play (CW slots)
                    publishes ──► keyer.slots

VoiceKeyerService ─ accepts  ◄── keyer.play (voice slots)

POTASpotService  ── accepts  ◄── spot.self_post

LoggingSessionManager ─ accepts ◄── qso.append
                       publishes ──► qso.appended, session.stats

ActivationCoordinator (existing) ── publishes ──► activation.context
```

A single new component — **`RemoteOpServer`** (actor, `swift/macos/CWSweep/Services/Remote/`) — owns the WebSocket lifecycle, pairing, token validation, subscription bookkeeping, and dispatch. It does **not** own state — it reads from existing publishers and forwards to existing sinks. That's the design test: if `RemoteOpServer` tries to hold business state, we've drawn the boundary wrong.

The shared message namespace lives in **`CarrierWaveCore`** (new module `Remote/`) so iOS and macOS speak the same Codable types from one source of truth.

---

## iOS Field client

New target-internal module under `swift/ios/CarrierWave/Services/Remote/`:

- `RemoteSweepSession` (actor) — owns the WebSocket, subscribe/command surface, reconnect logic.
- `RemoteSweepDiscovery` (@MainActor @Observable) — Bonjour browse + paired-device list.
- `RemoteState` (@MainActor @Observable) — typed live state (`radioState`, `spotFeed`, `ft8Feed`, `meters`, …) populated from incoming topics. One observable hub the views read from.
- `RemoteSweepCommands` — thin facade so views don't talk to the WebSocket directly (`tune(_:)`, `playKeyer(...)`, `pauseFT8()`, `selfSpotPOTA(...)`).

New screens (additive — Field's existing screens keep working):

- `RemoteHomeView` — current radio state, big tune dial, mode/band switches, S-meter, "TX in progress" indicator. Phone-shaped.
- `RemoteSpotsView` — filtered spot feed; tap → tune.
- `RemoteFT8View` — decode list, QSO state, overload banner, "pause TX / I'm coming" button. Reuses existing `FT8DecodeListView` styling.
- `RemoteKeyerPad` — big buttons for F1–F8 per current mode.
- `RemoteSettingsView` — pair / unpair, alerts rules.

Entry point: a new sidebar/tab in Field (gated by "is paired") that swaps the app into "remote mode." Local Field functionality remains intact when not paired.

---

## Push pipeline (off-LAN alerts)

Required for tier-1 features 1, 7, and the FT8 "come to the desk" alert. Without this, push notifications only fire when the phone is on the same Wi-Fi as the desk, which defeats half the use case.

```
Sweep                          activities-server               iOS Field
─────                          ─────────────────               ─────────
emit AlertEvent  ───POST───►  /v1/remote/events
                                   │
                                   ▼
                              Look up registered device
                              tokens for this user
                                   │
                                   ▼
                              POST APNs (token-based JWT)  ────► APNs ────► device
```

- iOS registers APNs token on first run via existing telemetry pipe extended with a new `/v1/remote/devices` route.
- Pairing flow exchanges a per-user identifier (already present in CK records) so server can route Sweep's events to the right device(s).
- Sweep posts events only when `phone is off-LAN` *or* `topic priority = critical` — to keep traffic + battery sane.
- Alert rules live on Sweep (truth) and are mirrored to activities-server so the server can do the cheap matching without Sweep online (e.g., RBN spots when Sweep is asleep).
- Notification deep links carry `{topic, refId}` so tap → opens the right screen with context.

This adds one new model, three new endpoints, and an APNs forwarder to the Rust server. Modest.

### Notification categories (v1)

- `ft8.calling_me` — someone responded to our CQ
- `spots.needed` — needed DXCC/grid/mult appeared
- `spots.watchlist` — watched callsign appeared
- `radio.fault` — overload / SWR / temp threshold tripped

---

## Bandwidth tiers

Phone tells server its current tier; server adapts rates and topic membership.

| Tier | When | Drops |
|------|------|-------|
| `full` | Wi-Fi, app foreground | nothing |
| `low` | cell, app foreground | meters 5→1 Hz, command_log off, scope strip off |
| `idle` | app backgrounded | meters off, decodes throttled, only on-change topics |
| `off` | unsubscribed | nothing flows except keepalive |

Tier transitions are explicit commands so Sweep doesn't guess.

---

## v1 cut

Ship as a single phase, because the protocol is the hard part and three features test it adequately:

1. **Pairing + transport + reconnect** (foundation).
2. **`radio.state` + `radio.tune` + spot feed + tap-to-QSY** (smallest end-to-end loop, validates publishers and commands).
3. **FT8 decode feed + TX state + pause/resume + "calling me" Live Activity** (validates higher-rate publish, real push pipeline).
4. **Keyer pad** (validates command-only flow, no state).

After that loop is solid, batch the next slice: rate panel, self-skimmer, self-spotting, watch-list alerts.

Out of v1: audio streaming, scope strip, panadapter, watchOS app, voice TX, Maestro-style multi-radio focus toggle.

---

## Open questions

1. **Multiple Sweeps?** SO2R desk could run two Sweeps. v1 = single pair only; revisit when SO2R is real.
2. **Token revocation UX.** Sweep needs a "Paired Devices" settings tab. Where does it live? Likely under Settings → Remote.
3. **Push privacy.** Alert rules going through activities-server means callsigns and grids leave the device. Acceptable? Probably yes for opt-in, but worth a settings toggle.
4. **Spot feed dedup vs. mirror.** Sweep already enriches and dedupes; phone displays Sweep's view, not raw. Confirm we never re-aggregate on the phone.
5. **Pairing without bringing the iOS QR scanner up to current.** Field doesn't yet have a QR scanner surface — adding one is a small ask but not free.
6. **Field while not paired.** Should "Remote" tab be hidden, or shown with an empty-state CTA? Empty state feels right.
7. **Conflict with `MultiOpClient`.** If the Field user is *also* a multi-op participant, do we want one connection or two? v1 = two; they serve different roles.
8. **Time sync.** Decode timestamps need to be Sweep's clock, not the phone's. Send UTC + monotonic offset on connect.

---

## What this commits us to

- A new shared message module in `CarrierWaveCore` (small).
- A new `RemoteOpServer` actor in CW Sweep (medium — mostly plumbing, not logic).
- Extracting tune/split/append APIs from existing managers into testable seams (small-medium).
- A new screen tree in CW Field gated by pairing (medium).
- Three small endpoints + APNs in activities-server (small-medium, but real ops surface).
- A QR-pairing UI on both sides (small).

Total: roughly two weeks of focused work for v1 if we don't get clever, or three if we ship audio in the same pass (don't).

---

## Next step (if approved)

Open Linear issues:

- `CAR-???` — RemoteOp protocol & shared message types in CarrierWaveCore
- `CAR-???` — RemoteOpServer + pairing in CW Sweep
- `CAR-???` — RemoteSweepSession + state hub in CW Field
- `CAR-???` — Remote Home/Spots/FT8/Keyer screens in CW Field
- `CAR-???` — `/v1/remote/{devices,events}` + APNs forwarder in activities-server
- `CAR-???` — "Calling me" Live Activity + alert rules

Each is a vertical slice of the v1 cut above.
