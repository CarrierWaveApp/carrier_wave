# Satellite Operations: IC-9700 + CSN S.A.T. in CW Sweep

**Date:** 2026-09-11
**Status:** Draft (research complete; hardware spike mostly done 2026-10-04, see [bench results](../investigations/2026-10-04-ic9700-sat-civ-lan-bench.md); awaiting owner sign-off). Lives in `docs/plans/` because `docs/superpowers/` is gitignored.
**Branch:** `feat/satellites`
**References:** [docs/icom-ic9700-civ-protocol.md](../icom-ic9700-civ-protocol.md), [docs/csn-sat-api.md](../csn-sat-api.md), [docs/features/icom-wifi-protocol.md](../features/icom-wifi-protocol.md)

## Summary

Add a satellite feature set to CW Sweep (macOS first, shared model in CarrierWaveData so Field inherits it): satellite QSO logging with correct ADIF, live pass awareness, IC-9700 spectrum waterfall over LAN, and integration with the CSN S.A.T. tracker. The S.A.T. remains the Doppler and rotator authority; CW Sweep observes it and the radio, never writes VFOs during a pass.

## Decision: who owns the radio

Research outcome (see the two reference docs):

- The S.A.T. is built to be the exclusive CI-V master. It rewrites both bands while tracking (bench: ~0.57 s per band on a duplex bird), uses dual-band VFO mode (not the 9700's satellite mode; `16 5A` = `00` on the bench), and has no CI-V passthrough. On the bench it kept **Sub selected as the 2 m uplink** and used the other band (Main) as the 70 cm downlink. Do not assume Main = uplink or Main = downlink; derive it from frequency.
- The IC-9700 has four independent CI-V paths (REMOTE, USB, DATA, LAN). The S.A.T. lives on REMOTE. CW Sweep can use LAN via the existing `IcomWiFiTransport` with no wiring changes. Scope waveform data flows over LAN and is impossible over REMOTE, so the waterfall does not compete with the tracker for a port.
- Setting the Sub band frequency on a 9700 requires selecting Sub (`07 D1`), which is shared radio state that flips the scope and confuses a tracker mid-write. There is no band-addressed frequency command on this radio.
- Building our own Doppler engine would duplicate the S.A.T., fight it for the VFOs, and inherit every gpredict/Hamlib 9700 bug (VFO flicker, PTT stalls).

**Recommendation: S.A.T. drives, CW Sweep observes.** CW Sweep gets satellite name, transponder, az/el, AOS/LOS, and Doppler-corrected uplink/downlink from the S.A.T. HTTP and UDP interfaces, and reads the radio over LAN in read-only mode for confirmation and the waterfall. Read-only confirmation of **both** bands comes from CI-V transceive broadcasts (`00` freq / `01` mode, `to=00`), assigned to a band by frequency range because they carry no band tag. `25`/`26` can't do it (they address VFO A/B of one band, not Main/Sub), and polling `03` is racy because the S.A.T. toggles `07 D2`. CW Sweep never issues `07 D0/D1`, `05`, `06`, or `16 5A` while the S.A.T. reports `mode == 1`. Any tuning we want to offer goes through the S.A.T. (`/?a=F|<hz>`, transponder select, `?a=d`).

A CW-Sweep-native tracker (TLE + SGP4 + rotator) is explicitly out of scope for V1 and only reconsidered after V1 ships. Pass *prediction* for all satellites (not just the one the S.A.T. is tracking) does need our own SGP4 and is planned as Phase 4.

## Hardware spike (Phase 0, before any feature code)

Five unknowns change the design. Each is a 15-minute bench test with the 9700, the S.A.T., and `Tools/ic705_diag.swift` extended for the 9700 (it already builds RS-BA1 packets and CI-V frames).

| # | Question | Why it matters | Test |
|---|---|---|---|
| 1 | Is `CI-V Transceive` global or per-port when USB is Unlinked? Does the S.A.T. still track correctly with Transceive ON? | wfview says the scope push needs Transceive ON; the S.A.T. manual says OFF. If both are true and it is global, the waterfall and the tracker are mutually exclusive. | Transceive ON, S.A.T. tracking a pass, watch S.A.T. uplink/downlink stay sane for 2 min. Then Transceive OFF, send `27 11 01` over LAN, see whether `27 00` frames still arrive. |
| 2 | Does the S.A.T.'s `07 D1`/`05` Sub write flip the LAN scope stream to Sub, and does it stay there? | Determines whether we render "whatever band arrives" or must pin `27 12`. The S.A.T. changelog says it sets the scope to Sub itself. | Log the MS byte of every `27 00` frame during a pass. |
| 3 | Can the LAN session coexist with the S.A.T. on REMOTE with no NAK/`FA` on either side? | Confirms the coexistence claim on this firmware. | Poll `03` at 1 Hz over LAN during a pass; count `FA` replies and S.A.T. error popups. |
| 4 | `/track` key casing (`satName` vs `satname`), `/cmd?a=` vs `/?a=`, `A\|uid` vs `uid` for transponder select. | Client correctness. | `curl http://rotator.local/track`; try both command paths. |
| 5 | Does the S.A.T. MacLogger push (UDP 2237, WSJT-X logged-ADIF) contain `SAT_NAME`, `FREQ_RX`, `SAT_MODE`? | Cheapest way to ingest QSOs logged on the S.A.T. itself. | Set QSO LOG TYPE = MacLogger, IP = the Mac, `nc -ul 2237`, log one QSO on the S.A.T. |

Output: [docs/investigations/2026-10-04-ic9700-sat-civ-lan-bench.md](../investigations/2026-10-04-ic9700-sat-civ-lan-bench.md).

**Results (2026-10-04, birds below the horizon):**

| # | Answer |
|---|---|
| 1 | Transceive ON is fine: the S.A.T. tracked normally with it ON all session. `00`/`01` broadcasts reach every port; scope waveform frames go only to the client that requested them (LAN scope never showed on the Unlinked USB port). Waterfall and tracker are **not** mutually exclusive. |
| 2 | Not tested. Relevant twist: the S.A.T. keeps **Sub** selected and Sub is the 2 m **uplink**, so if the scope follows the selected band the waterfall shows the uplink, not the downlink. |
| 3 | Yes for wfview 2.22 over LAN + S.A.T. on REMOTE + a USB poller: no effect on control, USB audio, or an ISS recording; 0 NG in >1100 USB polls. Sweep's own LAN client not yet tried. |
| 4 | Not tested. |
| 5 | Not tested. |

Still open: a real above-horizon duplex pass with PTT, the LAN client slot limit, and Main/Sub scope buffer separation with real frames. Phases 1–3 assume the likely answers (Transceive can be ON with the S.A.T.; scope follows Sub; coexistence works) and each notes its fallback.

## Goals (V1)

1. IC-9700 appears in the Sweep radio catalog with the right address, and connects over LAN with the existing RS-BA1 transport.
2. IC-9700 spectrum scope renders in Sweep's existing waterfall, tagged Main/Sub, with center/span read from the frame. Works with or without the S.A.T.
3. A "Satellite" activation type on `LoggingSession`, and QSO fields for satellite name, satellite mode, propagation mode, and RX band/frequency/mode. All ADIF builders emit them. 23cm exists as a band.
4. A `SATTrackerManager` that connects to the S.A.T., exposes current satellite, transponder, az/el, AOS/LOS countdown, and Doppler-corrected uplink/downlink, and listens for UDP 9932 events.
5. A Satellite panel in Sweep (new `OperatingRole` or a panel in the Hunter/Activator layouts) showing the tracker state, prefilling the logger's uplink/downlink/mode/sat name, and drawing footprint + ground track on the activation map.

## Non-Goals (V1)

- Our own Doppler correction or rotator control.
- Writing VFOs on the 9700 while the S.A.T. is tracking.
- USB serial to the 9700 (LAN only in V1; serial 0x27 framing with 11 divisions is a later addition). When it's added: with CI-V USB Baud = Auto the port emits garbage until the host sends a command, so send first and trust reads after.
- Audio over LAN.
- 9700 satellite mode (`16 5A`) control. We read it to warn the user if it is on while the S.A.T. is connected.
- Field (iOS) UI. Field gets the model and ADIF changes for free through CarrierWaveData; a Field UI rides the existing Remote Sweep relay later.
- Transponder database editing.

## Architecture

### Phase 1: IC-9700 waterfall over LAN (Sweep)

Independent of the satellite work and the first thing that produces a visible result.

| Change | Where |
|---|---|
| Add IC-9700 (`0xA2`, LAN + serial) to the model catalog; fix `BridgeRigDetector.swift`, which has the IC-7300/IC-705 addresses swapped relative to the (correct) catalog in `RadioProfile.swift` | `swift/macos/CWSweep/Models/RadioProfile.swift`, `swift/macos/CWSweep/Services/Radio/BridgeRigDetector.swift` |
| `CIVScopeFrame` parser for `27 00`: MS byte, division/max, mode, center or edges (BCD), out-of-range flag, 0–160 data; accumulator that emits a full 475-bin line per band (single LAN frame now, 11 USB divisions later). Pure Swift in Core with unit tests using captured frames | `swift/packages/CarrierWaveCore/Sources/CarrierWaveCore/CIVScope.swift` (+ tests) |
| Scope control helpers: `27 10`, `27 11`, `27 12`, `27 14`, `27 15`, `27 19` encoders | same file |
| `IcomWiFiTransport` demultiplexes `27 00` frames out of `receivedData` into a new `scopeFrames: AsyncStream<CIVScopeFrame>` so the CAT poller never sees 490-byte frames | `swift/packages/CarrierWaveData/Sources/CarrierWaveData/Radio/IcomWiFiTransport.swift` |
| `WaterfallStore.Source` gains `.icom(band: MainSub)`; an `IcomWaterfallData` consumer (mirroring `SCULAN10WaterfallData`) maps 0–160 to 0…1 with a user-adjustable floor/ceiling and calls `append(line:centerMHz:spanKHz:source:)` | `swift/macos/CWSweep/Services/Radio/WaterfallStore.swift`, new `IcomWaterfallData.swift` |
| `RadioManager+Transport.createIcomWiFiTransport` wires the consumer; on connect reads `27 10` / `27 11`, turns on whatever is off, and on disconnect restores exactly what it read (`CIVScopeRestorePlan`). Never touches `16 5A`, Sub, or DR, unlike RS-BA1. Bench: wfview left the scope on after disconnect; we must not | `swift/macos/CWSweep/Services/Radio/RadioManager+Transport.swift` |
| Waterfall panel shows a Main/Sub badge and a "pin scope to Main/Sub" toggle that sends `27 12` (off by default). Open: with the S.A.T. holding Sub = uplink selected, "follow selected band" may show the uplink; the pin may need to target the downlink band by frequency, and `27 12` is a write to shared state while the S.A.T. tracks | `swift/macos/CWSweep/Views/Spots/WaterfallPanel.swift` |
| Protocol write-up | `docs/icom-ic9700-civ-protocol.md` (done) |

Fallback if test #1 shows Transceive must be ON and the S.A.T. cannot tolerate it: the waterfall becomes a "no tracker connected" feature, and the Satellite panel shows a one-line warning explaining why. (Bench 2026-10-04: not needed so far; recheck on an above-horizon pass.)

### Phase 2: Data model and ADIF (shared package)

| Change | Where |
|---|---|
| `ActivationType.satellite` with display name "Satellite" and icon | `swift/packages/CarrierWaveData/.../Models/LoggingSession+Types.swift` |
| QSO fields: `satName: String?`, `satMode: String?`, `propMode: String?`, `frequencyRX: Double?` (MHz), `bandRX: String?`, `modeRX: String?`. SwiftData lightweight migration; add to `QSOFields+FieldStore.swift` and `CKRecordMapper+Fields.swift` so iCloud and Carrier Wave Sync carry them | `Models/QSO.swift`, `CloudSync/…` |
| Add `23cm` (1240–1300 MHz) to `BAND_ORDER`, `STANDARD_BANDS`, and `band_derive` | `rust/cw-core/cw-domain/src/band.rs` (+ tests) |
| ADIF: emit `SAT_NAME`, `SAT_MODE`, `PROP_MODE`, `BAND_RX`, `FREQ_RX`, `MODE_RX` when present. Touch points: `QSOLedger.ADIFRecordBuilder`, `FullADIFExportActor`, `QRZClient+ADIF`, `ClubLogClient+Helpers`, `EQSLClient+Helpers`, `ADIFExportService`, `PendingUploadExporter`, `POTAClient+ADIF`. Prerequisite step: extract one `ADIFFieldEmitter` in CarrierWaveData that all eight call for the common fields, so this is the last time a new field means eight edits | `swift/packages/CarrierWaveData/...`, `swift/ios/CarrierWave/Services/...` |
| ADIF import: parse the same six fields | `CarrierWaveCore` ADIF parser |
| Sat name normalization table (ISS→ARISS, HADES-R→SO-124, …) matching the S.A.T. and LoTW | `CarrierWaveCore/SatelliteNames.swift` |

### Phase 3: S.A.T. integration and Satellite panel (Sweep)

| Change | Where |
|---|---|
| `actor SATClient` (pattern: `DXHeatClient` with its own `URLSessionConfiguration`, 1.5 s timeout): `track()`, `status()`, `groundTrack()`, `selectSatellite(name:)`, `selectTransponder(uid:)`, `setFrequency(hz:)`, `resetToCenter()`, `toggleRadio()`. Decodes `/track` with case-insensitive keys and computes corrected uplink/downlink from `afreq` | `swift/macos/CWSweep/Services/Satellite/SATClient.swift` |
| `actor SATEventListener`: UDP 9932 via `NWListener`, parses `SAT,…` lines into `SATEvent` | `Services/Satellite/SATEventListener.swift` |
| `@MainActor @Observable SATTrackerManager`: polls `/track` every 3 s (vendor limit), applies UDP events immediately, exposes `currentSatellite`, `transponder`, `azEl`, `aos/los`, `uplinkHz/downlinkHz`, `isTracking`, `connectionState`. Host/port in Settings, stored in UserDefaults (no secret) | `Services/Satellite/SATTrackerManager.swift` |
| Optional `SATQSOListener`: UDP 2237 WSJT-X logged-ADIF → creates a QSO in the active satellite session (gated behind a setting) | `Services/Satellite/SATQSOListener.swift` |
| Radio guard: when `SATTrackerManager.isTracking`, `RadioManager` refuses frequency/mode/VFO writes with a user-visible log line, and reads `16 5A` once on connect to warn if satellite mode is on | `RadioManager.swift` |
| Logger: `ParsedEntryView` and `QSOEntryPopupView` get a downlink freq/mode pair; when the session is `.satellite` they are prefilled from `SATTrackerManager` (uplink → `frequency`, downlink → `frequencyRX`, `satName`, `satMode` from transponder modes, `propMode = "SAT"`) | `Views/Logger/ParsedEntryView.swift`, `QSOEntryPopupView+Sections.swift` |
| Satellite panel: satellite name, transponder picker, az/el dial, AOS/LOS countdown, corrected uplink/downlink, S.A.T. status, buttons that go through the S.A.T. (select transponder, center, park) | `Views/Satellite/SatellitePanelView.swift` |
| Map: footprint `MapCircle` from `satFootprint / 2` and ground-track `MapPolyline` from `/gtrack` in `ActivationMapPane+Overlays.swift` | `Views/Map/ActivationMapPane+Overlays.swift` |
| Settings tab "Satellite": S.A.T. host, enable UDP listeners, QSO push | `Views/Settings/` |
| Command palette entries: "Track satellite…", "Next transponder", "Park antennas" | `Views/CommandPalette/` |
| Experimental gating: Sweep is entirely experimental, so no `ExperimentalFeature` case; the panel is a role/layout toggle | |

### Phase 4: Pass prediction without the S.A.T. (later)

TLE fetch (CelesTrak amateur group + the S.A.T.'s own `csnbare.txt`) and SGP4 in `rust/cw-core` (`sgp4` crate), so Sweep shows the next 24 h of passes for favourite satellites even when the S.A.T. is off, and can send `/?a=U|<name>` to the S.A.T. when the user picks one. Also unlocks Field-side pass alerts. Not needed for V1.

### Phase 5: Field (iOS)

The Remote Sweep relay already carries waterfall lines; extend `RemoteOpPublishers` with tracker state so Field's Remote tab shows the Satellite panel. Native Field support for the S.A.T. over WiFi is straightforward later since `SATClient` lives in Sweep for V1 only because of the UDP listener; moving it to CarrierWaveData is a file move.

## Data flow during a pass

```
S.A.T. ──CI-V REMOTE 19200──▶ IC-9700 ◀──RS-BA1 UDP LAN── CW Sweep (read-only CAT + 27 00 scope)
  │  HTTP /track (3 s), /gtrack                              ▲
  │  UDP 9932 events (AOS/LOS/TRANSPONDER/QSO)               │
  └──────────────────────────────────────────────────────────┘
                     SATTrackerManager → Satellite panel, logger prefill, map overlays
```

Logging source of truth for frequencies: the S.A.T.'s corrected uplink/downlink at the moment the QSO is saved. The cross-check is the latest transceive broadcast per band (by frequency range), not a `03` read: `03` follows whichever band the S.A.T. last selected, and `25`/`26` never reach the other band. This avoids selecting Sub over CI-V.

## Risks

- **Transceive conflict** (test #1). Below the horizon the S.A.T. tolerated Transceive ON; recheck on a real pass. Mitigation above.
- **Band role assumptions.** The S.A.T. uses Sub (selected) = 2 m uplink, Main = 70 cm downlink, and no satellite mode. Anything that assumes satellite mode's Main = downlink / Sub = uplink, or that `25`/`26` read Main vs Sub, is wrong for this tracker.
- **One LAN client at a time.** If the user also runs wfview or RS-BA1, Sweep cannot connect. Surface the "Busy" state clearly.
- **S.A.T. API drift.** Vendor page is "work in progress"; pin behaviour to firmware 9.188 and record the `fw` field in logs.
- **ADIF builder sprawl.** Eight builders today. The extraction step in Phase 2 is the cost of doing this once.
- **CloudKit mirrors triplicate records.** New QSO columns must go through the existing dedup path; nothing new here but easy to forget.

## Open questions for the owner

1. Branch and PR policy for this repo (root `CLAUDE.md` has an empty "Git Workflow" section): PR per phase into `main`, or one long-lived `feat/satellites` branch?
2. Linear: create a "Satellites" project under team CAR, or file under the existing "CW Sweep" project?
3. Is consolidating the eight ADIF builders acceptable as a prerequisite PR, or should satellite fields be added to each in place for V1?
4. Should the Satellite panel be a new `OperatingRole` ("Satellite") or a panel available inside Hunter/Activator?
5. Preferred logging source when both exist: S.A.T.-pushed QSOs (UDP 2237) or Sweep's own logger with prefill? Default in this spec is Sweep's logger, with the push listener off.
