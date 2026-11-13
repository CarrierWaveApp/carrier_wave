# IC-9700 full-duplex Doppler from CW Sweep

**Date:** 2026-10-21
**Status:** Implemented through bench-testable scope; live-pass items open (see Phasing)
**References:** [docs/icom-ic9700-civ-protocol.md](../icom-ic9700-civ-protocol.md),
[2026-10-04 bench](../investigations/2026-10-04-ic9700-sat-civ-lan-bench.md),
[2026-09-11 design](2026-09-11-satellite-ops-design.md)

## Decision

The September design had the CSN S.A.T. as the Doppler master and Sweep as a
read-only observer, because the bench station had a S.A.T. on the REMOTE
jack. Jay's own station has no S.A.T.: **Sweep is the sole Doppler master**,
controls the IC-9700 **over LAN** (RS-BA1, the existing `IcomWiFiTransport`),
and targets **linear transponders** from the start. The observe-only rules of
the earlier design still apply whenever a tracker is linked; nothing here runs
in that case.

## What the radio forces

- Full duplex (RX on Main while TX on Sub) only exists in satellite mode
  (`16 5A 01`). Main is the downlink, Sub the uplink.
- No band-addressed frequency command. Tuning Sub is `07 D1` → `05 f` →
  (`06 mode`) → `07 D0`. `25`/`26` return NG in satellite mode.
- Band selection is radio-global, so the poll loop's `03` must not run during
  that sequence or its reply belongs to whichever band is selected.
- No CI-V for NOR/REV; inverting transponders are our arithmetic.
- Satellite mode is a global setting: read it before changing it, restore it.

## Implementation

| Layer | Change |
|---|---|
| Rust `cw-net` / `cw-domain` / `cw-ffi` | SatNOGS `uplink_high`, `downlink_high`, `invert` parsed and carried to `FfiSatTransmitter` (`uplink_high_hz`, `downlink_high_hz`, `invert`). Cached transmitter JSON is the wire shape, so no migration. |
| `CarrierWaveCore/CIVDuplex.swift` | `07 D0/D1/D2`, `16 5A`, `1C 00` encoders; reply parsers; ack/nak checks. |
| `CarrierWaveData/RadioSession+Duplex.swift` | `readSatelliteMode`, `setSatelliteMode`, `readSelectedBand`, `tuneSubBand` (polling paused for the whole sequence, Main reselected even on failure, each step waits for `FB`). |
| `CarrierWaveData` protocol handler + session | `encodeReadPTT` (CI-V `1C 00`) in the poll rotation, so `isTransmitting` follows the rig, not just our own PTT sets. |
| `CWSweep/RadioManager+Duplex.swift` | `supportsSubBandDuplex` (IC-9700 model or address `A2`, CI-V/LAN), `enterSatelliteMode` (remembers the found state in `satelliteModeRestore`), `restoreSatelliteMode`, `tuneSubBand`. Both disconnect paths restore. |
| `SatelliteCATController` | `SatelliteUplinkTarget` = none / second radio / Sub band (legacy uplink-slot default migrates). Prepare once per satellite: satellite mode on, Main mode, Sub mode + first uplink tune. Each tick: downlink (deadband), dial-follower observe, uplink (deadband, during TX too). Disarm restores satellite mode. |
| `SatelliteDialFollower` | Pure rules for turning a Main readback into a passband offset: settle window after arming, echo tolerance against the last four commands (fast Doppler near TCA), passband plausibility (rejects a `03` reply that landed on Sub), clamp to the known passband. |
| `SatelliteDopplerReadout` | Takes `dialOffsetHz`; uplink gets `−offset` on inverting birds. `SatelliteModeKind.uplinkRadioMode` is LSB for SSB. |
| UI | Trackers settings picker + help text; Doppler card footer "Dial +x kHz into passband · inverting (REV) · uplink follows dial"; frame reads the downlink slot's frequency/TX state. |

## Operating notes

- LAN: Network Control ON, User1 set, one client session. The scope state
  restore already in place applies; satellite mode now restores the same way.
- USB instead of LAN works too: CI-V USB Port = Unlink, 115200, and the host
  must send before trusting reads (auto-baud).
- Hearing yourself: USB audio codec L = Main, R = Sub; `Sub Band Mute (TX)`
  must be off. Sweep does nothing with audio here.
- RS-BA1 (Icom's client) resets satellite mode on connect; Sweep's transport
  does not. Don't run both.

## Phasing / open items

1. **Bench, radio on the desk (next):** connect over LAN, arm CAT on a linear
   bird below the horizon, check in the command log: `16 5A` read → `16 5A 01`,
   `07 D1` / `05` / `06` / `07 D0` with `FB` after each, Main stays selected,
   disarm sends `16 5A 00` only if it was off.
2. **Does a Main `05` drag Sub in satellite mode?** Unknown [U] in the protocol
   doc. If it does, the per-tick Sub tune already re-corrects it, but check the
   log for Sub writes on every tick (expected only when the uplink moves past
   the deadband).
3. **Live pass:** PTT while the uplink keeps tuning (gpredict's known failure),
   dial following on RS-44 / FO-29 (inverting), S-meter.
4. **Real Main scope in the pass view**, pinned with `27 12` to the downlink,
   replacing `SatelliteWaterfallSynth`.
5. **Transceive-broadcast band tracking** as a second readback source, so the
   Sub frequency is visible without polling it.
