# Bridge Satellite Doppler Mode (P0)

**Date:** 2026-09-20
**Target hardware:** ESP32-P4 (new board, headless — no display/encoder/buttons), companion ESP32-C6 for BLE via ESP-Hosted
**Target radio:** Quansheng UV-K1 (or K5v3) running the sugarfree90 `uv-k1-k5v3-firmware-CAT` fork, connected through a K-plug programming cable (CH340/CP210x)

## Goal

The app precomputes a full doppler schedule for a satellite pass (timestamped
frequency steps for uplink + downlink, U/V vs V/U direction, mode, CTCSS tone)
and uploads it to a new satellite-bridge firmware over BLE. The bridge then
executes the pass on its own clock against the radio via CAT — the phone can
disconnect mid-pass. The operator works the pass on the HT: VFO A always holds
the doppler-corrected downlink, VFO B the corrected uplink; they key the
radio's own PTT and flip A/B (from the app, via a protocol message — the P4
board has no buttons).

Decisions locked in during brainstorming:

- **TX model:** bridge-managed VFOs (no bridge PTT, no split emulation).
- **Scope:** FM sats fully (SO-50/ISS/AO-91 class, stepped doppler + uplink
  CTCSS) plus **linear-transponder downlink RX** in USB at 100 Hz granularity.
  No linear TX (the K5 can't SSB TX), no contests with this thing.
- **Pass UX:** phone-optional. Upload + arm before AOS; the bridge runs the
  pass standalone. Status pushes flow whenever a client is subscribed.
- **Schedule format:** fully-expanded step table computed by the shared Rust
  `SatelliteApi` math. Firmware is a dumb clock-driven executor.

## Radio facts (verified against the CAT fork source, `App/app/uart.c`)

- Extended Kenwood ASCII at **38400 8N1**; commands end with `;`. No echo, and
  **unknown commands are silently ignored — there is no `ID;` response**, so
  the stock bridge Kenwood probe can never detect this radio.
- `FAxxxxxxxxxxx;` / `FBxxxxxxxxxxx;` (11 digits, Hz) set both RX and TX
  frequency of that VFO. Setting the *inactive* VFO saves without disturbing
  the active one. Internal resolution is 10 Hz. No reply on set.
- `FR0;` / `FR1;` selects the active VFO (both RX_VFO and TX_VFO).
- `MDx;` (4=FM, 5=AM, 2=USB), `CTdddd;` (CTCSS in tenths of Hz, e.g.
  `CT0670;` = 67.0 Hz), and `OF;` (tone off) apply **only to the active VFO**
  — pass setup must flip VFOs while configuring, then flip back.
- `IF;` returns `IF<11-digit freq>00000<spaces><mod><tx>;` — position 30 is
  `1` while transmitting. This is the executor's TX guard.
- `TX;`/`RX;` force PTT (unused in P0).

Detection therefore adds a third probe: after CI-V and Kenwood `ID;` both
fail at a baud, send `IF;` and accept an `IF...` response ≥ 28 chars as
Kenwood with synthetic id `UVK1CAT`, 11 freq digits. Standard Kenwood `MD`
digits for FM/AM/USB happen to match this fork, so the existing `SetVerify`
path needs no mode quirk.

## Architecture

```
Phone (SatelliteApi math) --BLE NUS protobuf--> ESP32-P4 sat bridge --USB host--> CH340/CP210x cable --> UV-K1 CAT
                                                     ^ BLE controller on companion ESP32-C6 via ESP-Hosted (SDIO)
```

### New directory: `firmware-sat/`

A **separate crate** from `firmware/` (per direction; not a branch). BLE
(`ble.rs`), USB host (`usb.rs`), detection (`detect.rs`), set-and-verify
(`verify.rs`), protobuf helpers (`protocol.rs`), and `rtos.rs` are copied
from the S3 firmware (they are platform-generic ESP-IDF FFI); display,
encoder, buttons, battery, audio, FT8 and the CW keyer are dropped. New:
`sat.rs` (executor) and the pure-logic subcrate `firmware-sat/sat-core/`.
Known duplication with `firmware/` — extracting a shared crate is a later
refactor, not P0.

Build config differences from the S3 firmware:

- target `riscv32imafc-esp-espidf`, plain nightly toolchain (P4 is RISC-V —
  no Xtensa fork needed), `ESP_IDF_VERSION = v5.5`, `MCU = esp32p4`.
- BLE: NimBLE **host** runs on the P4; the controller lives on the C6 behind
  ESP-Hosted. The Rust code is unchanged (raw NimBLE host API); the wiring is
  sdkconfig + `esp-idf-sys` extra components (`espressif/esp_hosted`,
  `espressif/esp_wifi_remote`). This matches the ESP32-P4-Function-EV-Board
  arrangement. **Compile-verified only until hardware arrives.**
- BLE security: same open-peripheral posture as the current S3 firmware
  (SM disabled); a headless board cannot display a passkey anyway.
- USB host: P4 native OTG PHY, no GPIO muxing. Same `usb_host` API.
- Advertises as **"CW Sat Bridge"** so the apps can distinguish it.

### `firmware-sat/sat-core/` (pure Rust, host-testable)

Single source of truth for the wire step format and executor timing, used by
the firmware **and** by `cw-domain`'s schedule builder (path dependency), so
pack/unpack can never drift.

- `Step { t_ms: u64, downlink_hz: u64, uplink_hz: u64 }` (absolute).
- Packed wire format, 6 bytes/step little-endian:
  `dt_ms: u16` (offset from previous step; builder inserts keepalive steps so
  a gap never exceeds 60 000 ms), `down_delta_dhz: i16`, `up_delta_dhz: i16`
  (deltas from the previous step in 10 Hz units — the radio's resolution).
  First step is relative to the `SatScheduleBegin` absolute start values.
- `MAX_STEPS = 2048` (12 KB), `STEPS_PER_CHUNK = 30` (fits one 240-byte BLE
  notification with protobuf overhead).
- `pack_steps` / `unpack_steps` + `ExecutorCursor` (which step is due at a
  given elapsed-ms; coalesces missed steps to the latest values).

### Protocol additions (`proto/cwbp.proto`, tags 29–35)

- `SatScheduleBegin` (C→B): `schedule_id`, `sat_name`, `direction`
  (`U_V`/`V_U`/`DOWNLINK_ONLY`), `total_steps`, `duration_ms`,
  `downlink_start_hz`, `uplink_start_hz` (0 = downlink-only),
  `downlink_mode`/`uplink_mode` (UniversalMode digits, same encoding as
  `FIELD_MODE`), `uplink_tone_dhz`.
- `SatScheduleChunk` (C→B): `schedule_id`, `seq`, packed step bytes.
  Stop-and-wait: client sends the next chunk after each ack.
- `SatScheduleAck` (B→C): `schedule_id`, `seq`, result
  (`OK/BAD_SEQ/OVERFLOW/UNKNOWN_ID/BUSY`), `steps_loaded`.
- `SatStart` (C→B): `schedule_id`, `aos_in_ms`, `elapsed_ms` (for arming
  mid-pass). Bridge configures the radio immediately (see below), then
  counts down on `esp_timer`/FreeRTOS ticks.
- `SatAbort` (C→B).
- `SatSetActiveVfo` (C→B): 0 = downlink (VFO A), 1 = uplink (VFO B) — the
  app-driven replacement for the missing hardware button.
- `SatStatus` (B→C, on change + in the `StatusReq` dump): state
  (`IDLE/LOADING/ARMED/RUNNING/DONE/ERROR`), `schedule_id`, `step_index`,
  current `downlink_hz`/`uplink_hz`, `t_ms` (sint64; negative = countdown to
  AOS), `detail`.
- New handshake capability bit `CAP_SAT_DOPPLER = 1 << 5`.

### Executor behavior (`firmware-sat/src/sat.rs`)

1. **Arm** (on `SatStart`): radio setup sequence over CAT —
   `FR1; MD<up>; CT<tone>;` (or `OF;`), `FR0; MD<down>; OF;`, then initial
   `FB`/`FA`. Leaves VFO A (downlink) active.
2. **Run**: dedicated thread wakes for each due step; writes `FB` then `FA`
   (only the links whose value changed). Missed steps coalesce to latest.
3. **TX guard**: before each retune, poll `IF;` (via the shared verify-style
   RX intercept, serialized with `SetVerify` on one CAT lock). If position 30
   is `1`, skip this retune and retry in 500 ms — never yank the frequency
   mid-transmission.
4. **Status**: pushed on state change and each executed step; silently
   dropped when no BLE subscriber (bridge keeps running).
5. `DONE` at last step + `duration_ms`; `SatAbort` or USB disconnect →
   back to `IDLE` (abort) / `ERROR` (radio lost).

EEPROM wear note: each retune writes the K1's settings EEPROM (the CAT fork
saves on every FA/FB). Worst case ~400 writes per linear pass against ~100k
endurance — acceptable.

### App side

- **`cw-domain`** `satellite/doppler_schedule.rs`: `build(propagator,
  observer, aos, los, params) -> Vec<sat_core::Step>` — samples range-rate at
  1 s cadence (finite difference, same method as `tracker.rs`), applies
  doppler factor −ṙ/c (downlink ×(1+f), uplink ×(1−f)), emits a step whenever
  either link drifts ≥ half its granularity (2.5 kHz FM / 100 Hz linear
  downlink), rounds to 10 Hz, inserts ≤ 60 s keepalives.
- **`cw-ffi`** `SatelliteApi.build_doppler_schedule(...) ->
  FfiDopplerSchedule` — header fields + packed chunk byte arrays ready for
  the BLE transport.
- **iOS**: pass detail view gains a "Send to Bridge" action when a CW Bridge
  is connected; new encode/decode in `BridgeProtocol.swift` (regenerated
  `cwbp.pb.swift`), upload/arm flow, live `SatStatus`, and a downlink/uplink
  VFO flip control during the pass. Android later — the protocol and math are
  already shared.

## Testing

- `sat-core`: pack/unpack round-trip, delta overflow, keepalive spacing,
  cursor coalescing (plain `cargo test`).
- `cw-domain`: schedule for a canned TLE pass matches direct doppler math
  within one granularity step; FM vs linear granularity; U/V vs V/U signs.
- Firmware: compile for `riscv32imafc-esp-espidf`.
- Hardware (owed, needs the P4 board + K1): detection via `IF;` probe, pass
  execution against the CAT fork, TX-guard while keyed, BLE-drop mid-pass.

## Out of scope (P0)

Multi-pass NVS storage, bridge-managed PTT, linear TX, K5v3 native USB-C
(CDC-ACM device class on the bridge's host stack), Android UI, shared-crate
refactor of the duplicated firmware modules.
