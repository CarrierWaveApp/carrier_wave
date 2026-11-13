# CW Sweep → N1MM Competitor Roadmap

**Status:** Planning checkpoint, 2026-04-07
**Companion to:** [`cw-sweep-development-plan.md`](cw-sweep-development-plan.md)
**Branch this lives on:** `claude/contest-scoring-engine-lkez4`

---

## Strategic angle

The pitch is **not** "N1MM clone on Mac." It is:

> The only logger that does **POTA activations *and* serious contests**, natively
> on macOS, with iCloud sync to your iPhone.

N1MM doesn't do POTA. POTA loggers don't do contests. CW Sweep does both. That
is the wedge. Everything in this roadmap exists to make CW Sweep credible enough
that a serious contester will use it for CQ WW *and* keep it open for a Tuesday
night POTA activation.

The unlock for the "serious contester" market is the moment CW Sweep can produce
a valid CQ WW Cabrillo with correct live scoring. Phase 1 of this roadmap
exists to reach that moment.

---

## Current state audit (v0.8.0)

CW Sweep is further along than the surface impression suggests. The foundation
is legitimately strong:

**Solid:**
- Radio CAT control across 20+ radios, 5 protocols, serial / WiFi / network
- Spot pipeline: 8 sources, unified dedup, enrichment
- Band map, contest band scope, waterfall
- DX cluster with telnet
- POTA activator workflow (cold-start wizard, self-spot, rove planner)
- CW keyer + WinKeyer + voice keyer with F1–F12 macros
- ESM state machine (in `MacroEngine`)
- Vim mode, command palette, detachable panels, custom layouts
- DXCC tracking with needed-on-band
- iCloud sync with iOS
- ADIF import/export, basic Cabrillo export
- Super Check Partial (already in iOS, will be shared via `CarrierWaveData`)
- Contest definitions and 8 bundled templates (CQ WW CW/SSB, ARRL DX W/VE and
  DX, ARRL Sweepstakes CW, NAQP CW, Field Day, generic State QSO Party)

**Stubbed but broken:**
- `ContestEngine.calculatePoints` exists but doesn't actually evaluate the
  scoring conditions — every condition case falls through and the function
  returns the last rule's points regardless of the QSO. This branch
  (`claude/contest-scoring-engine-lkez4`) has the in-progress fix.
- Contest mode toggle exists in the Radio Palette but no live score window,
  no rate sheet, no off-time tracker.
- Bundled CQ WW templates use a flat `sameContinent=1, differentContinent=3`
  rule that ignores the actual CQ WW rule (NA on 40/80/160 m = 2 pts).

**Missing entirely:**
- Live score / claimed-score window
- Hourly rate sheet (the single most-used N1MM window)
- Off-time tracker
- Available Mults & Qs window
- Check window (previous QSOs with this station, expected exchange)
- Call History auto-fill from prior contest QSOs
- Contest audio recording
- WSJT-X UDP interop
- Multi-op LAN networking, band lockout, pass spots
- Rotator control
- Awards beyond DXCC (WAS / WAZ / VUCC / WPX / IOTA matrices)
- UBN log-checking parser

---

## The gap, ranked

The features below are roughly in the order that will move CW Sweep up the
"serious contester" credibility curve. Phasing comes after.

1. **Contest scoring engine** — make `calculatePoints` actually work, add
   `MyStationContext`, support per-band scoring rules, expose live score and
   claimed-score window.
2. **Super Check Partial integration** — wire the existing SCP from
   `CarrierWaveData` into the contest entry field as you type, sorted
   worked-before first.
3. **Available Mults & Qs window** — N1MM's strategic window: which mults are
   still needed on each band. The reason contesters change bands.
4. **Call History auto-fill** — load previous contests' QSOs from SwiftData,
   pre-populate exchanges for known stations. Massive error reduction in
   long-exchange contests like Sweepstakes.
5. **Hourly rate sheet** — running QSOs / hour, points / hour, mults / hour
   broken down by hour. Indispensable for pacing.
6. **Off-time tracker** — automatic detection of qualifying rest periods,
   running totals, violation warnings, Cabrillo annotations.
7. **WSJT-X UDP interop (listener-only)** — receive decode and QSO-logged
   messages on UDP 2237, auto-log into the contest engine with shared dupe
   state.
8. **Contest audio recording** — continuous AVAudioEngine recording with
   per-QSO markers, click-log-to-play.
9. **Multi-op networking** — LAN-discovered shared log via CRDT, band lockout,
   pass spots, station roles.
10. **Rotator control** — separate `RotatorService`, GS-232 / Green Heron /
    Hy-Gain protocols, beam heading on band map, auto-rotate to spotted
    bearing.
11. **Call Stacking** — `{StackAnother}` macro: queue the next callsign while
    finishing the current QSO. Power-user keyboard feature that differentiates
    Sweep's keyboard-first design.
12. **Polished Cabrillo export** — correct headers per contest, proper exchange
    formatting, DUPE marking, post-contest validation.
13. **Additional award matrices** — WAS / WAZ / VUCC / WPX / IOTA tracking
    with confirmation status (LoTW / QRZ / eQSL / paper).
14. **UBN parser & post-contest analysis** — parse log-checker UBN reports,
    score breakdown by hour / band / mult.

---

## Architectural decisions

These are baked in. They are not open for re-litigation when each phase starts;
they are the design contract for everything below.

### Super Check Partial lives in `CarrierWaveData`
SCP already exists in the iOS app. It moves into `CarrierWaveData` so both
iOS and CW Sweep consume the same matcher and the same MASTER.SCP loader, and
so it can hybridize with `worked-before` lookups against the SwiftData QSO
history (which already lives in that package).

### Multi-op transport: CRDT log + multicast control
Multi-op shared state is **not** a Raft problem. Raft is the wrong shape:
- Raft requires majority quorum. A 2-station Field Day op stops logging the
  moment one station drops to refill the generator. That is a real failure
  mode in the use case we care about most, not a corner case.
- Network partitions stop logging entirely. Unacceptable when "never miss a
  QSO" is the whole point.
- Strong consistency buys nothing for an append-only, immutable, naturally
  time-ordered log.

What N1MM actually does — and what we will do — is a CRDT-style append-only
log:

- Each station has a stable `stationID` (UUID). Each QSO gets a local
  monotonic serial. The composite `(stationID, serial)` is the QSO's
  identity.
- The replicated state is a G-Set (grow-only set) of these QSO records.
- Stations discover each other via Bonjour and exchange state over TCP.
- New QSOs are gossiped to all peers. Receivers insert if not already
  present, and run the same dupe / mult / scoring checks the originator did.
- Reconnecting after a partition is a one-shot G-Set merge: send your set,
  receive theirs, union. No coordinator, no quorum, no leader election.

Control traffic — band lockout, pass spots, run-frequency announcements — is
**not** replicated state. It is pub/sub fire-and-forget over UDP multicast on
the same Bonjour-discovered group, with last-write-wins per `(band,
stationID)`. Stale reads are acceptable for these messages; the cost of being
slightly behind is far lower than the cost of coordinator overhead.

### Audio: AVAudioEngine
Contest audio recording uses AVAudioEngine. High-level Swift API, clean device
routing, taps for per-QSO marker insertion, built-in file writing. We drop to
CoreAudio HAL only if we hit a specific routing limitation with USB radio
audio devices — and that is a Phase 2 problem, not a now problem.

### WSJT-X interop: listener only
We listen on UDP 2237 for decode and QSO-logged messages and auto-log received
QSOs into the contest engine. We do **not** broadcast in N1MM's UDP format in
Phase 2, and we do **not** send commands back to WSJT-X. Both expand
compatibility surface that we don't need to chase yet.

### Rotator control: separate `RotatorService`
Rotator control is its own service, distinct from radio CAT control. Concrete
protocol implementations: GS-232 (Yaesu), Green Heron, Hy-Gain DCU. Lives
beside the radio service in CW Sweep. We do not rely on hamlib / `rotctld`.

### Off-time and rate sheet are pure stateless calculators
Both are plain structs with one function each:

```swift
struct OffTimeCalculator {
    static func summary(
        qsoTimestamps: [Date],
        rules: OffTimeRules,
        now: Date
    ) -> OffTimeSummary
}

struct RateSheetCalculator {
    static func sheet(
        qsoLog: [QSOLogEntry],
        contestStart: Date,
        contestEnd: Date
    ) -> RateSheet
}
```

No actors, no state, no synchronization. `ContestEngine` calls them whenever
the score window asks for fresh data. Trivially unit-testable, reusable for
post-contest analysis of imported logs, fast enough for any contest size.

### Phase 1 ships with corrected templates
All 8 bundled contest templates get reviewed and corrected as part of Phase 1.
Specifically, the CQ WW templates need band-filtered scoring rules so that NA
intra-continent QSOs on 40 / 80 / 160 m get 2 points instead of 1. Shipping
the engine fix without fixing the templates would just produce a different
flavour of wrong Cabrillo.

---

## Phase plan

### Phase 1 — Contest Core
The unlock. Goal: a single-op operator at K1AR's station can run CQ WW CW
end-to-end on CW Sweep, see correct live scoring, take qualifying off-time
breaks, and submit a Cabrillo that the contest robot accepts on the first
try.

- Fix `ContestEngine.calculatePoints` (in progress on this branch — see
  WIP commit `e864a30`).
- Wire `MyStationContext` into the engine and into session start.
- `OffTimeCalculator` struct + UI display in the score window.
- `RateSheetCalculator` struct + hourly rate sheet view.
- Super Check Partial integration in the CW Sweep entry field, sourced
  from `CarrierWaveData`.
- Available Mults & Qs window.
- Call History auto-fill from prior contest QSOs already in SwiftData.
- Polished Cabrillo export: correct headers per contest category, exchange
  formatting per template, DUPE marking, basic header validation.
- Update all 8 bundled contest templates to use band-filtered scoring rules
  with verified point values.
- Check window: previous QSOs with the entered callsign, expected exchange
  based on Call History.

### Phase 2 — Audio & Digital
- AVAudioEngine continuous contest audio recording with per-QSO markers,
  per-contest folder layout, click-log-to-play in the score window.
- WSJT-X UDP listener (port 2237), auto-log received QSOs into the contest
  engine, share dupe / mult state.

### Phase 3 — Multi-op
- Bonjour peer discovery.
- CRDT G-Set replication of the QSO log over TCP between peers.
- Multicast control channel for band lockout, pass spots, run-frequency
  announcements.
- Station roles: Run / S&P / Mult, with role display on each peer.
- Pass-frequency one-click handoff between stations.
- `{StackAnother}` Call Stacking macro for the entry field.

### Phase 4 — Hardware & Polish
- `RotatorService` with GS-232 (Yaesu), Green Heron, Hy-Gain protocol
  implementations. Beam heading on band map, auto-rotate to spotted bearing.
- Stacked / multi-band band maps (multiple bands visible simultaneously).
- Multi-monitor named window arrangement presets per contest.
- UBN log-checking parser and post-contest analysis: breakdown by hour,
  band, mult.
- Dark / field mode (red-shifted palette for night ops).
- Additional award matrices: WAS, WAZ, VUCC, WPX, IOTA.

### Phase 5 — Ecosystem
- Contest calendar auto-download of rules / templates for upcoming contests.
- Cloud score reporting to live contest score aggregators.
- CW Skimmer / SkimmerServer integration as a local decode feed into the
  spot pipeline.
- Practice / training mode (simulated contest with adjustable CW speed,
  Morse Runner-style).

---

## Non-goals

Things we deliberately will not build, and why:

- **Windows / Linux ports.** The wedge is "native macOS." Cross-platform
  destroys the differentiation and the development velocity.
- **N1MM-format `.mdb` file compatibility.** The legacy on-disk format is a
  dead end. Cabrillo in / out is the interchange format that matters.
- **Outbound N1MM UDP broadcast.** We listen to WSJT-X but do not pretend to
  be N1MM for third-party tools. If a tool needs N1MM, it can use N1MM. If
  this becomes the #1 user request later, we revisit it as a discrete
  decision.
- **VFO command sending to WSJT-X.** Listener-only. WSJT-X's command set is
  undocumented and version-sensitive; the maintenance cost is not worth the
  benefit at our scale.
- **`rotctld` / hamlib bridge.** We implement rotator protocols natively so
  the user doesn't have to install and configure an external daemon.
- **Raft, Paxos, or any quorum-based replication for multi-op.** See the
  CRDT decision above.
- **Training-wheels "guided contest" mode.** N1MM doesn't have one and
  serious contesters don't want one. Practice mode in Phase 5 is a discrete
  feature, not a gating layer over the real entry experience.
- **A built-in DX cluster server.** We are a client, not infrastructure.
- **Cloud-hosted log storage as the primary store.** SwiftData on the device
  remains the source of truth. iCloud is sync, not authoritative.

---

## Open questions deferred to phase start

Architectural decisions baked in above are final. The questions below are
intentionally deferred — they don't affect Phase 1 and shouldn't be answered
until the relevant phase starts.

- **Phase 2:** how do we map WSJT-X's `Decode` messages onto the contest
  engine's notion of a QSO when many decodes never become QSOs? (Probably:
  decodes feed the band scope and Available Mults window, only `QSOLogged`
  messages hit the engine.)
- **Phase 2:** where do contest audio files live, and how do they sync? (They
  are far too large for iCloud. Probably: local-only, with optional manual
  export.)
- **Phase 3:** what is the exact wire format for the CRDT gossip protocol?
  Protobuf? JSON? A custom binary format? (Phase 3 design doc decides.)
- **Phase 3:** how does the CRDT log interact with the existing iCloud QSO
  sync? Does the multi-op network sync up to iCloud post-contest, or live?
  (Probably: post-contest only, to avoid CloudKit rate limits during a run.)
- **Phase 4:** which rotator protocol do we ship first, and which test
  hardware do we own?

---

## What to pick up next

This branch (`claude/contest-scoring-engine-lkez4`) already contains a WIP
commit (`e864a30`) with the `MyStationContext`, the rewritten
`calculatePoints`, the band-filtered `ScoringRule`, and the off-time data
types. Picking Phase 1 back up means continuing from there: finish the
engine fix, add the `OffTimeCalculator` and `RateSheetCalculator` structs,
write tests, then move outward to the views.
