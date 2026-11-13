# CLAUDE.md — CW Sat Bridge (ESP32-P4)

## Project Overview

Headless Rust firmware (ESP-IDF `std`) for the ESP32-P4: a satellite-pass
doppler executor. The app uploads a precomputed pass schedule over BLE
(protobuf/NUS, the shared CWBP protocol from `proto/cwbp.proto`); the bridge
executes it against a Quansheng UV-K1/K5 running the sugarfree90 CAT firmware
over USB serial — VFO A stays on the doppler-corrected downlink, VFO B on the
corrected uplink, on the bridge's own clock. The phone can disconnect
mid-pass.

Design doc: `docs/plans/2026-09-20-bridge-satellite-doppler.md`.

- **No display, no buttons** — VFO flips come from the app (`SatSetActiveVfo`).
- **BLE**: NimBLE **host-only** (the P4 has no radio); the controller is the
  Waveshare board's onboard ESP32-C6 behind **ESP-Hosted over SDIO**
  (ESP-Hosted default P4 wiring: CLK=18 CMD=19 D0–D3=14–17 C6-RST=54 — no
  external wires). The `espressif/esp_hosted` managed component (Cargo.toml
  `extra_components`) supplies the transport, the CP controller RPC, and the
  NimBLE HCI glue; `ble.rs` calls `esp_hosted_init` →
  `esp_hosted_connect_to_slave` → `esp_hosted_bt_host_stack_setup` before
  `nimble_port_init`. The C6 must run the ESP-Hosted slave firmware
  (Waveshare ships it; reflash via C6_U0RXD/TXD with C6_IO9 low if ever
  needed). Advertises as **"CW Sat Bridge"**. SM disabled (open peripheral,
  same posture as `firmware/`).
- **USB host**: P4 native OTG; same raw USB Host Library code as
  `firmware/` (FTDI/CP210x/CH340/CDC).
- **Detection**: standard CI-V + Kenwood `ID;` probes, plus an `IF;`
  fallback for the UV-K1 CAT fork (it ignores `ID;` silently). Synthetic id
  `UVK1CAT`.

## Build & Flash

RISC-V target — plain `cargo build` with the `esp` toolchain (pinned in
`rust-toolchain.toml`); no Xtensa tooling involved.

```bash
cargo build                # Debug
cargo build --release      # Release
espflash flash --port /dev/cu.usbmodem* target/riscv32imafc-esp-espidf/release/cw-bridge-sat
espflash monitor --port /dev/cu.usbmodem* --non-interactive
```

Host-side tests (pure logic, no ESP toolchain):

```bash
cd sat-core && cargo test
```

## Code Layout

| File | Purpose |
|------|---------|
| `src/main.rs` | Slim event loop: BLE + USB + detect + SetVerify + sat dispatch |
| `src/sat.rs` | Schedule upload assembly (`SatManager`) + pass executor thread |
| `sat-core/` | **Shared crate**: wire step format + executor cursor. Also a path dependency of `rust/cw-core/cw-domain` (the app-side schedule builder) — the byte layout has one implementation |
| `src/verify.rs` | `CatSession` (exclusive CAT access to ONE radio + per-slot RX capture, shared by SetVerify and the executor) + set-and-verify, all threaded by `radio: usize` |
| `src/detect.rs` | Radio auto-detect (CI-V + Kenwood `ID;` + the `IF;` UV-K1 probe), per-radio via capture; `detect(usb, radio, vid, pid)` |
| `src/usb.rs` | **Multi-radio** USB host: up to `MAX_RADIOS` (2) CAT devices bound at once, addressed by radio index; per-slot RX capture, completion signals, is-FTDI/paused flags (each transfer carries `idx+1` in `context`); native USB-C CDC-ACM (UV-K1) via class-0xEF enum allow + data-interface claim. A hub with two K1s drives both independently |
| `src/selftest.rs` | Freq bring-up self-test (`--features freq-selftest`): background poller sweeps every connected radio — radio 0 up on 2 m, radio 1 down on 70 cm (opposite directions); one radio → VFO A up / VFO B down; `FA;`/`FB;` readback logged |
| `src/ble.rs`, `src/rtos.rs` | Platform-generic ESP-IDF FFI (ble.rs = NimBLE host over ESP-Hosted) |
| `src/protocol.rs` | Protobuf helpers incl. `SatScheduleAck`/`SatStatus` encoders |
| `src/generated/cwbp.rs` | prost output from `proto/cwbp.proto` (modern prost naming — variants keep proto prefixes, unlike `firmware/`'s legacy generated file) |
| `src/include/nimble_bindings.h` | Re-adds NimBLE host headers that esp-idf-sys skips on the P4 (see below) |

Known duplication with `firmware/` is deliberate for now; extracting a shared
crate is a future refactor.

## Executor behavior (`sat.rs`)

1. `SatScheduleBegin` + stop-and-wait `SatScheduleChunk`s (6-byte packed
   steps, ≤30/chunk) assemble into a committed schedule (`cw-sat-core`
   unpack validates).
2. `SatStart` configures the radio — flip to VFO B, set uplink mode + CTCSS
   (`CT`, tenths of Hz), flip to VFO A, set downlink mode, `OF;`, initial
   `FB`/`FA` — then counts down `aos_in_ms` on FreeRTOS ticks.
3. During the pass, each due step writes `FB`/`FA` for links whose value
   changed. **TX guard**: `IF;` position 30 == '1' → hold 500 ms and retry;
   missed steps coalesce to the latest values (`Cursor::due`).
4. `SatStatus` pushes on state change + each step; dropped silently with no
   BLE subscriber (bridge keeps flying the pass).
5. USB disconnect or write failure mid-pass → `SAT_ERROR`. `SatAbort` (or a
   new `SatScheduleBegin`) stops the run; the schedule survives abort.

## UV-K1 CAT fork facts (verified against `App/app/uart.c`)

- 38400 8N1, ASCII `;` commands, **no echo, unknown commands ignored, no
  `ID;`** — hence the `IF;` detection probe.
- `FA`/`FB` set both RX+TX freq of that VFO (11 digits, 10 Hz internal
  resolution); inactive-VFO writes don't disturb the active one.
- `MD` (4=FM/5=AM/2=USB — matches standard Kenwood digits), `CT`
  (4-digit tenths of Hz), `OF;` apply to the **active** VFO only.
- Every apply saves EEPROM — a linear pass is ~200–400 writes, fine against
  ~100k endurance.

## ESP32-P4 gotchas

- **esp-idf-sys skips all BT headers on the P4** (`#if !defined(...ESP32P4)`
  in its bindings.h). `src/include/nimble_bindings.h` +
  `[[package.metadata.esp-idf-sys.extra_components]]` re-adds the NimBLE
  host bindings (and the ESP-Hosted BT APIs) into the crate root. After
  touching that metadata, force a rebuild with `cargo clean -p esp-idf-sys`.
- ESP-IDF pinned to **v5.5** — the esp_hosted component requires ≥5.5.
- If the hosted link is down (C6 slave missing/stale), `esp_hosted` init or
  the BT controller bring-up fails at boot — the slave version is printed in
  the boot log; ESP-Hosted hosts can OTA the slave, or reflash the C6 over
  its UART (C6_IO9 low for download mode).
- espflash uses its own bootloader/partition table; the connected board is
  16 MB flash.

## Protocol

Sat messages are tags 29–35 in `proto/cwbp.proto` (see the file for field
docs). Handshake capability bit: `CAP_SAT_DOPPLER = 1 << 5`. Regenerate
Rust with `protoc-gen-prost` (or the prost-build runner) and Swift with
`protoc --swift_out=...` per the root workflow; `firmware/`'s generated file
is legacy-named — don't overwrite it with modern prost output.
