# CLAUDE.md — CW Bridge

## Project Overview

Rust firmware (ESP-IDF `std` approach) for the **CW Bridge rev 2 PCB** (`hardware/bridge/`, ESP32-S3-WROOM-1U-N16R8) that bridges BLE to USB serial, enabling wireless CAT control of amateur radios from Carrier Wave on iOS/macOS. The pin map lives in `src/board.rs` and must match the schematic; the Heltec WiFi Kit 32 dev-board era ended 2026-09-26.

- **ESP32-S3**: Runs the bridge application with built-in BLE 5 and USB OTG host
- **BLE service**: Nordic UART Service (NUS) — advertises as "CW Bridge"
- **BLE security**: LE Secure Connections + MITM passkey pairing. The bridge
  shows a 6-digit code on the OLED; iOS/macOS prompt for it. Bonds persist in
  NVS so paired devices reconnect silently. Unbonded peers cannot write CAT
  or receive notifications.
- **Protocol**: Protobuf over NUS — structured handshake, auto-detection, framed CAT passthrough
- **Supported USB chips**: FTDI FT-X/FT232, CP210x, CH340

## Build & Flash

Requires the `esp-rs` toolchain (`espup install`).

```bash
cargo build               # Debug build
cargo build --release     # Release build
espflash flash --monitor target/xtensa-esp32s3-espidf/debug/cw-bridge      # Flash debug + monitor
espflash flash --monitor target/xtensa-esp32s3-espidf/release/cw-bridge    # Flash release + monitor
```

## Architecture

```
Phone/Mac  <-BLE NUS (protobuf)->  ESP32-S3
                                     | USB Host (GPIO19/20)
                                   USB-serial cable
                                     |
                                   Amateur Radio
```

Data flow:
- Phone protobuf CatData -> `handle_ble_data()` -> `usb.send()` -> Radio
- Radio response -> `UsbData` event -> `protocol::encode_cat_data()` -> BLE NUS TX -> Phone

## Code Layout

| File | Purpose |
|------|---------|
| `src/main.rs` | Entry point, event loop, bridge state, dispatch |
| `src/protocol.rs` | Protobuf encode/decode helpers |
| `src/detect.rs` | Radio auto-detection: VID/PID hints, baud probing, Kenwood/CI-V ID |
| `src/verify.rs` | Set-and-verify: semantic commands, Kenwood/CI-V encoding, RIT/XIT emulation |
| `src/usb.rs` | USB host: multi-chip enumeration, baud control, FTDI vendor requests |
| `src/ble.rs` | BLE: NimBLE GATT server, NUS service, advertise/notify |
| `src/board.rs` | **Pin map** for the rev 2 PCB — the only place GPIO numbers live |
| `src/i2c_bus.rs` | `SharedI2c`: one `I2cDriver` behind an `Arc<Mutex>` for codec + expander + OLED |
| `src/expander.rs` | PCAL6416A driver: buttons/encoder-switch inputs, BT/USB status LEDs |
| `src/display.rs` | SSD1306 128x64 I²C OLED (header J3) via embedded-graphics |
| `src/encoder.rs` | Rotary encoder phases (GPIO1/2): quadrature decode → events |
| `src/buttons.rs` | BTN1–3 + encoder switch polled from the expander: debounce + short/long-press events |
| `src/audio.rs` | ES8388 codec (I²C) + I2S0 full duplex: FT8 audio out (J7) and capture (J8) |
| `src/ft8.rs` | FT8 encode/decode via CFT8 FFI |
| `src/ft8_shim.c` | Thin C helpers bridging CFT8's `monitor_t` to Rust |
| `src/generated/cwbp.rs` | Checked-in prost output from `proto/cwbp.proto` |
| `sdkconfig.defaults` | ESP32-S3 config: NimBLE, USB host, PSRAM, flash size |

## Protocol (Protobuf)

Defined in `proto/cwbp.proto` (monorepo root). One BLE notification = one serialized `BridgeMessage`.

Message types:
- `HandshakeReq/Rsp` — protocol version, firmware version, capabilities
- `CatData` — raw CAT bytes wrapped in protobuf
- `Status` — USB connect/disconnect, detecting, ready, error
- `RadioInfo` — detected protocol type, baud rate, raw ID string
- `RequestDetect` — re-run auto-detection
- `SetBaud` — manual baud rate override
- `SetVerify/SetResult` — semantic radio commands with verification
- `Ft8EncodeReq/Rsp` — text → 79-tone sequence (no audio over BLE)
- `Ft8Send` — encode text and transmit via mic TRS jack
- `Ft8CaptureStart/Stop` — control phone-jack decoder
- `Ft8Decode` — per-slot decoded message with SNR / freq / dt
- `Ft8Status` — IDLE / TRANSMITTING / CAPTURING / ERROR
- `JackStatus` — TRS jack plug insertion (not emitted by the rev 2 PCB: no detect switches)
- `BatteryStatus` — VBAT telemetry (not emitted by the rev 2 PCB: no VBAT sense)

## Radio Auto-Detection

On USB enumeration:
1. VID/PID lookup -> candidate baud rates (FTDI: 38400 first, CP210x: 19200 first)
2. At each baud: send Kenwood `ID;`, wait 500ms
3. If Kenwood `ID06xx` detected: mark as Yaesu (9-digit FA/FB frequency format)
4. If Kenwood `ID020` detected: query `OM;` — if `OMQC` returned, mark as QCX (QRP Labs QCX/QCX+/QCX-mini)
5. If no Kenwood response: send CI-V identify (`FE FE 00 E0 19 00 FD`), wait 500ms
6. Report RadioInfo with raw ID string (app maps to equipment catalog)

### Yaesu Radio Handling

Yaesu radios (ID `ID06xx`, e.g. FT-891 = `ID0650`) use Kenwood-compatible CAT commands but with **9-digit** frequency in FA/FB (vs 11-digit for Kenwood/Elecraft). Detected via `ID;` response prefix `ID06`. The `freq_digits` field in `DetectResult` controls the format width. Built-in USB is CP210x (VID `0x10C4`, PID `0xEA60`), already in `CABLE_HINTS`.

### QRP Labs Radio Handling

Both QCX and QMX use Kenwood TS-480 CAT subsets but have key differences from standard Kenwood:

**Shared (QCX + QMX):**
- **RIT offset**: `RU<5digits>;` for positive, `RD<5digits>;` for negative (no sign character)
- **No XIT**: Emulated via RIT + VFO offset (existing emulation)
- **Power set not supported**: QCX has no PC; QMX PC is read-only

**QCX-specific (detected via `OM;` → `OMQC;`):**
- **No RC;**: Clear RIT via `RU00000;` + `RT0;`
- **Mode always CW**: `MD;` is read-only, always returns 3
- **Has TB;**: Keyer can poll buffer depth

**QMX-specific (detected via `VN;` → `*QMX`):**
- **Has RC;**: Standard clear RIT works
- **Multi-mode**: CW (3), FSK (6), CWR (7), FSR (9)
- **No TB;**: Keyer uses time-based drain estimate
- **USB CDC-ACM**: STM32 virtual COM port (VID `0x0483`, PID `0x5740`)

## Key Constants

- Supported VID/PIDs: FTDI FT-X `0x0403:0x6015`, FT232 `0x0403:0x6001`, CP210x `0x10C4:0xEA60`, CH340 `0x1A86:0x7523`
- Default baud: `38400` (auto-detection tries others)
- BLE device name: `"CW Bridge"`
- NUS Service UUID: `6E400001-B5A3-F393-E0A9-E50E24DCCA9E`
- Pin map (`src/board.rs`, mirrors `hardware/bridge/CLAUDE.md`):
  - USB host (native OTG): D-=GPIO19, D+=GPIO20 → J1 USB-A (RUN) or J9 USB-C (FLASH) via slide switch SW3
  - Shared I²C bus: SDA=GPIO5, SCL=GPIO6 @ 400 kHz — ES8388 codec `0x10`, PCAL6416A expander `0x20`, SSD1306 OLED `0x3C` (4-pin module on header J3, no reset line)
  - ES8388 I²S (ESP is master): MCLK=GPIO43, BCLK=GPIO39, LRCK=GPIO40, DOUT=GPIO42 (→ codec DAC → J7 AUDIO OUT), DIN=GPIO3 (codec ADC ← J8 AUDIO IN). 12 kHz, 16-bit stereo, MCLK = 256·fs
  - Rotary encoder (Bourns PEC12R, SW1): CLK=GPIO1, DT=GPIO2 (internal pull-ups); its push switch is expander P0_3
  - PCAL6416A: P0_0/1/2 = BTN1/2/3 (headers J4/J5/J6), P0_3 = ENC_SW, P0_6 = `LED_BT`, P0_7 = `LED_USB` (sink, active low; on-board D9/D10 plus panel header J12 through R27/R28). ~RESET = GPIO44 (driven high at boot), INT = GPIO8 (unused, we poll every 5 ms)
  - Console: UART0 TX on GPIO41 → J11 pin 1 (`CONFIG_ESP_CONSOLE_UART_CUSTOM` in `sdkconfig.defaults`; RX parked on the no-connect GPIO4). USB-Serial-JTAG vanishes once USB host claims the PHY
  - Strapping: BOOT = GPIO0 (header J14), RESET = EN (header J13). GPIO35/36/37 are the module's octal PSRAM — never bind them
- Buttons: `< 1 s` press emits `ButtonPress(idx)`. `≥ 1 s` hold emits
  `ButtonLongPress(idx)` once at the threshold and suppresses the
  short-press on release. **BTN3 long-press toggles the OLED Health
  overlay** from any view; short-press while the overlay is up dismisses
  it. Other buttons are wired but currently unbound.
- Status LEDs (`update_status_leds` in `main.rs`): BT blinking = advertising,
  solid = phone/Mac connected. USB blinking = device attached but not yet
  identified, solid = radio detected, off = nothing on the host port. D6 PWR,
  D7 VBUS and D8 BOOST are hardware-only.
- Not on this board: VBAT sense (no `BatteryStatus` is sent), TRS jack
  plug-detect switches (no `JackStatus` is sent), OLED reset/Vext lines.

## Hardware Wiring

Everything is on the rev 2 PCB (`hardware/bridge/`, see its `CLAUDE.md` for
the schematic-level detail). Off-board parts on 2.54 mm headers:

```
J3  OLED I2C     GND / VCC(3V3) / SCL / SDA   → 128×64 SSD1306 module
J12 PANEL LEDS   3V3 / PWR / BT / USB          → LED anodes to pin 1, cathodes to their pin
                                                  (series resistors are on the board)
J4/J5/J6         BTN1/2/3 + GND                → momentary switches
J13 RESET, J14 BOOT  signal + GND              → momentary switches (hold BOOT, pulse RESET = bootloader)
J11 DEBUG UART   TX / GND                      → 3.3 V serial adapter, 115200 8N1
J7 / J8          3.5 mm TRS                    → radio mic in / radio phones out (FT8)
U4 U.FL socket   (on top of the module)        → U.FL-to-SMA bulkhead pigtail through the case, 2.4 GHz antenna
```

Flashing: slide SW3 to **FLASH**, plug a PC into the USB-C port J9, hold BOOT
while pulsing RESET, then `espflash`. Slide back to **RUN** so the USB-A host
port J1 owns the data lines again. Note that USB-Serial-JTAG disappears once
the app boots into host mode — the bootloader must be entered via BOOT/RESET.

## Dependencies

- `esp-idf-svc` / `esp-idf-hal` / `esp-idf-sys` — ESP-IDF Rust wrappers
- `prost` — protobuf encode/decode
- `ssd1306` + `embedded-graphics` — OLED display; `embedded-hal` 1.0 for the shared-bus `I2c` trait impl
- `cc` (build-dep) — compiles the shared CFT8 C library into `libcft8.a`
- CFT8 C sources (`swift/packages/CarrierWaveCore/Sources/CFT8/`) — linked
  directly from the firmware build so encode/decode stays bit-identical with
  the iOS/macOS app. Do not fork these files; edits belong on both sides.
- ESP-IDF v5.4+ (linked by `esp-idf-sys`)

## Known Issues & Notes

- **Do NOT use `espressif/usb_host_cdc_acm` for FTDI devices.** Bulk OUT silently fails. This firmware uses the raw USB Host Library directly. See `docs/usb-host-investigation.md`.
- Only one BLE connection supported at a time (NimBLE configured for single peripheral).
- **First-time pairing requires the OLED.** The bridge is IO capability `DisplayOnly` — the passkey has to be read off the screen and typed into iOS/macOS. To reset bonds (e.g. after swapping phones), erase the NVS partition: `espflash erase-flash`. A four-bond NVS cap (`CONFIG_BT_NIMBLE_MAX_BONDS=4`) is enough for a personal radio bridge; older bonds are evicted automatically.
- The KX2 defaults to 9600 baud — change to 38400 via `MENU -> RS232 -> 38400`.
- Detection temporarily intercepts USB RX — normal bridge RX is paused during the ~1-2s probe window.
- Build times: ~3-5 min clean, ~30-60s incremental.
- **FT8 decoder needs PSRAM.** The waterfall (~120 kB for 90 blocks × 2 OSR × 2 OSR × ~100 bins) lives on the heap; without `CONFIG_SPIRAM=y` the decoder will fail to allocate. Output-only FT8 (encode + I2S TX) fits comfortably in internal RAM.
- FT8 slot boundaries are not wall-clock aligned on the firmware; the app is expected to start capture a few seconds before its own slot boundary and use `delta_time_s` from decodes for alignment.

## Adding a New Radio

1. Determine the USB-serial chip (VID/PID) used by the radio's cable
2. Add to `SUPPORTED_CHIPS` in `usb.rs` if not already there
3. Add baud rate hints to `CABLE_HINTS` in `detect.rs`
4. Add Kenwood ID or CI-V address mapping to `RigProtocolDetector.swift` (iOS side)
5. Test: `cargo espflash flash --monitor`

### Hamlib Reference

When researching CAT command sets, supported models, or protocol quirks for a
new radio, consult **Hamlib** as the canonical open-source reference:

- rigctld(1): https://hamlib.sourceforge.net/html/rigctld.1.html
- Top-level docs: https://hamlib.sourceforge.net/html/
- Source (per-rig backends): https://github.com/Hamlib/Hamlib/tree/master/rigs

Hamlib has backends for nearly every CAT-capable radio ever made — Yaesu
(`newcat.c` + per-model files like `ftx1.c`, `ft891.c`), Kenwood (`kenwood.c`
+ per-model), Icom (`icom.c` + per-model), Elecraft, QRP Labs, Xiegu, etc.
Use the per-rig source files to confirm Kenwood ID strings, CI-V addresses,
baud rates, command quirks (e.g. Yaesu 9- vs 11-digit FA/FB), and which
features a given radio supports before adding it to the bridge.

## Regenerating Protobuf Code

When `proto/cwbp.proto` changes:

```bash
# Rust (requires protoc + prost-build, or hand-edit src/generated/cwbp.rs)
protoc -I proto --prost_out=firmware/src/generated proto/cwbp.proto

# Swift
protoc -I proto --swift_out=swift/packages/CarrierWaveCore/Sources/CarrierWaveCore/Generated proto/cwbp.proto
```
