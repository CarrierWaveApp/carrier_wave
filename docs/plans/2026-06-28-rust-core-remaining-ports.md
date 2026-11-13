# Rust core — what's left to port

_Snapshot: 2026-06-28. Updated after the **medium facade swaps** landed on `main`
(commit `cd993b20`) — CAT protocols, spot decoders, ADIF, band/mode, and
callsign/DXCC/CTY are now cut over (see Bucket B → Medium below). Prior snapshot
was after RBN / Super Check Partial / SKCC / Polo notes (commit `d8f8ca43`).
Companion to `docs/plans/2026-06-13-rust-core-migration.md`._

The remaining work splits into two buckets that should not be conflated:

- **Bucket A — no Rust port exists.** Write new Rust, parity-test it, expose via
  `cw-ffi`, cut both apps over.
- **Bucket B — ported to Rust, apps still run the Swift copy.** The logic is in
  the core and tested; the apps just haven't been switched onto it, so the Swift
  duplicate still ships. This is migration/adoption work, not porting.

---

## Bucket A — genuinely not yet in Rust

These have a live Swift implementation and **nothing** in `cw-domain` / `cw-net` /
`cw-ft8`. Ordered by value.

### 1. Contest engine — ✅ **DONE (2026-07-04)**
- Ported in full to `cw-domain::contest` (model/engine/condition/exchange/
  callsign/cabrillo/schedule/off-time/band-change/enrichment) + `cw-net::
  contests` + `contest_definition` cache (schema v9) + `cw-ffi::contest_api`
  (`ContestApi`, `ContestEngineApi`, stateless `contest_*` fns). Both apps
  swapped onto facades; Swift logic + models + `ContestDefinitionsStore`
  deleted; contest QSOs now ride `SessionApi.log_qso`. Cross-language
  Cabrillo golden + 12 live-definition wire fixtures are the parity bar.
  Plan: `docs/plans/2026-07-04-contest-engine-rust-port.md`.

### 2. Radio macros + intent / state planner
- **Swift:** `CarrierWaveCore` macro DSL, template expansion, `planner.compile`,
  state profiles; the dynamic "operate FT8/CW" intent macros (see
  `project_dynamic_radio_macros`, `project_intent_completeness_gap`).
- **Rust today:** `cw_store::radio_macro` is the **storage row only** — no DSL,
  no planner, no intent compiler.
- **Shape:** protocol-gated pure logic; CAT command builders it leans on
  (`kenwood`/`yaesu`/`civ`) are already in `cw-domain`. Android only needs a
  sink to execute the compiled steps.
- **Note:** also the natural place to close the intent-completeness gap (settings
  leaking between intents) rather than re-porting today's partial behavior.

### 3. FT8 QSO sequencing state machine
- **Swift:** `CarrierWaveCore` FT8 QSO state machine — CQ / Search-&-Pounce
  sequencing, auto-reply, DXCC enrichment ("what do I transmit next").
- **Rust today:** `cw-ft8` is **codec only** (encode / decode / WAV). The
  sequencer is not ported.
- **Shape:** pure state machine over decoded messages; depends on the codec
  (done) + `cty`/`location_prefix` (done).

### 4. Small remainders
- `CWTextElement` rendering surface — intentionally deferred (UI-side); port when
  that layer moves.
- ADIF US-state table in `adif_catalog` — deferred until a consumer needs it.

**Done in this pass (no longer pending):** RBN spots, Super Check Partial, SKCC
roster parsing, Polo callsign notes.

---

## Bucket B — in Rust, apps not cut over

The Rust implementation exists and is tested; the iOS app (and where noted,
Android) still runs the Swift path. Finishing these lets the duplicated Swift be
deleted.

### Large
- **SwiftData → `cw-store` consumer cutover.** All 13 synced entities are
  modeled in SQLCipher with bounded queries + write seams, but iOS is still on
  SwiftData for most read/write sites. This is the dominant remaining item. See
  `docs/plans/2026-06-18-rustification-finish-handoff.md` for the per-entity
  state (QSO + Logbook reads are furthest along; analytics read surface is
  complete in `cw-store` but not all consuming actors are routed).
- **`cw-sync` server transport.** Journal + conflict resolution are ported and
  tested; the transport is still `InMemoryTransport`. The HTTPS server transport
  (gated on the Phase 5 OAuth work, in flight) is the missing piece — CloudKit
  remains the live sync path until then.

### Medium — Swift copies still live despite a tested Rust port
Routing these through `cw-ffi` and deleting the Swift logic is mechanical
(the pattern the RBN/SCP/SKCC/Polo pass used). **This bucket is done except for
propagation** — landed in commit `cd993b20` (merged to `main`). New `cw-ffi`
modules: `cat`, `pota`, `sota`, `wwff`, `pskreporter`, `adif`, `band_mode`,
`callsign`, `cty`. Each Swift facade keeps its public API and the original Swift
test suites pass unchanged as the parity gate; Rust clippy + workspace tests,
`CarrierWaveCore` SPM build, the iOS app build, and Android `:app:assembleDebug`
are all green.

> **CW Sweep straggler fixed (2026-06-28).** `cd993b20` could not build CW Sweep
> (see the "deadlock" note below — it was actually slow package resolution, not a
> deadlock), so the RBN cutover's macOS half slipped through: Sweep's
> `Services/Spots/RBNClient.swift` still decoded the now-deleted
> `RBNCallsignSpotsResponse` / `RBNSpotsResponse` wrappers and `JSONDecoder`-decoded
> `RBNSpot` (no longer `Decodable`). Routed it through `RBNSpot.decodeResponse(_:)`
> (the shared `cw_net::rbn` core), mirroring the iOS `RBNClient`. **CW Sweep now
> builds clean (33s incremental).** A green Sweep build confirms every *other*
> facade swap (CAT / ADIF / band-mode / callsign / POTA / SOTA / WWFF / PSK) was
> already correct for the macOS target — RBN was the lone straggler.

Status inline:
- ✅ ADIF parse/validate (`cw_domain::adif*`) — cut over. (US state/province +
  country catalog tables stay Swift-side: no `adif_catalog.rs` source yet.)
- ✅ Callsign / DXCC / CTY (`cw_domain::cty`, `callsign_detector`) — cut over.
  CTY is a UniFFI object (like SCP). **Still deferred:** `parseElements` →
  `[CWTextElement]` (UI-side, with the rest of the `CWTextElement` surface);
  `location_prefix` has no Swift duplicate in this subsystem.
- ✅ CAT protocols (`cw_domain::kenwood` / `yaesu` / `civ`) — cut over.
- ✅ Band / mode (`cw_domain::band`, `band_plan`, `mode`) — cut over
  (`maidenhead` was already done). `BandPlan`'s activity-scheduling types
  (`TimeWindow`/`FrequencyActivity`/`CWTRange`) stay Swift — no Rust source.
- ⏳ Propagation (`cw_domain::propagation`), antenna/azimuthal — **NOT done, and
  not a clean facade swap.** `AzimuthalProjection` is a *stateful instance* used
  per-coordinate in `Canvas` render hot paths and `AntennaPattern.gain` likewise;
  routing those per-point through FFI would violate the mandatory performance
  rules (multi-second hangs). `PropagationEstimator` is pure + portable but has
  no dedicated Swift parity test. Needs a perf-aware design (batch the projection
  across a path in one FFI call, or expose a `uniffi::Object` projector) before
  cutting over — do this deliberately, not mechanically.
- ✅ Dashboard analytics (`cw_store::analytics`) — already cut over (dual-path,
  Rust when `CwStoreQSOMode == .on`); nothing to do.
- ✅ Spot models POTA / SOTA / WWFF / PSKReporter (`cw_net::*`) — cut over,
  joining RBN. POTA/SOTA gained `parse_response` JSON decoders in `cw-net`.

---

## Explicitly **not** porting (platform-bound)
- CloudKit sync engine plumbing (the *logic* is in `cw-sync`; the engine is iOS).
- Remote Op (MultipeerConnectivity).
- Network transports / credential storage that must use platform keychain/OS
  APIs (the wire + parse layers are already in `cw-net`).

---

## Recommended order
1. ~~**Contest engine**~~ — ✅ done 2026-07-04 (see above).
2. **Radio macros / intent planner** (Bucket A #2) — unlocks Android parity for a
   marquee feature and closes the intent-completeness gap.
3. Continue the **SwiftData → cw-store cutover** (Bucket B) — the long pole; do it
   incrementally per the existing handoff doc.
4. **FT8 sequencer** (Bucket A #3) once the codec consumers are settled.
5. ~~Sweep the **medium Bucket B** items~~ — **done** (commit `cd993b20`), except
   **propagation/antenna/azimuthal**, which is not a mechanical swap: it needs a
   perf-aware design (batch the projection across a path in one FFI call, or a
   `uniffi::Object` projector) before cutting over. Treat it as a small Bucket-A-
   style design task, not an opportunistic sweep.

---

## ~~Known environmental blocker~~ — RESOLVED (2026-06-28): not a deadlock
- **The CW Sweep `xcodebuild` "deadlock at Resolve Package Graph" was a
  misdiagnosis.** It is **slow cold SwiftPM package resolution**, not a hang. A
  stack sample of the "stuck" process showed it parked in
  `-[Xcode3CommandLineBuildTool waitForRemoteSourcePackagesToFinishLoading]` with a
  live `NSURLConnectionLoader`/`CFSocket` thread — i.e. xcodebuild was doing real
  network work checking package remotes for updates, which takes several minutes on
  a cold DerivedData. Left alone it **completes** and proceeds to compile; once the
  graph is resolved, incremental builds are ~33s. `-disableAutomaticPackage
  Resolution`/`-onlyUsePackageVersionsFromResolvedFile` "didn't help" because the
  wait isn't a re-resolution — it's the initial remote load. **Takeaway:** give the
  first Sweep build after a cold checkout / DerivedData wipe several minutes before
  assuming it is wedged. The `cw-sweep-build` skill (`cw-sweep build`) builds fine.
- The first successful build after this correction immediately surfaced the real
  fallout `cd993b20` had hidden: the RBN macOS straggler (fixed; see the Medium
  section above).
