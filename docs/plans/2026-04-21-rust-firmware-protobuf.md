# CW Bridge: Rust Firmware + Protobuf Protocol

**Date:** 2026-04-21
**Status:** Plan (decisions finalized)

## Decisions

| Question | Answer |
|----------|--------|
| `std` vs `no_std` | `std` — ESP-IDF provides the runtime |
| Proto file location | `proto/cwbp.proto` at monorepo root |
| Codegen | Checked in (both Rust and Swift) |
| USB host module | Rewrite in Rust for consistency |
| Build tooling | Pure `cargo` (no Makefile wrapper) |
| Firmware directory | Replace `firmware/` in place |
| Backward compat | None — firmware isn't deployed yet |

## Current State

- ~4k lines of C (ESP-IDF), 7 modules
- CWBP: hand-rolled binary protocol (`[0xCB][TYPE][PAYLOAD...]`)
- Matching Swift parser/builder on iOS (`BridgeFrame.swift`, `BridgeProtocol.swift`)
- Raw USB host API for FTDI (bypasses CDC-ACM due to bulk OUT bug)
- NimBLE for BLE NUS
- SSD1306 OLED over I2C

---

## Rust Firmware

### Toolchain

```
esp-rs std approach (links against ESP-IDF):
├── esp-idf-svc     — high-level wrappers for ESP-IDF services
├── esp-idf-hal     — GPIO, I2C, SPI, peripherals
├── esp-idf-sys     — raw bindings (for USB host)
└── espflash        — flash tool (replaces esptool.py)
```

Build: `cargo build --release`. Target: `xtensa-esp32s3-espidf`.
Flash: `cargo espflash flash --monitor`.

### Project Structure

```
firmware/
├── Cargo.toml
├── sdkconfig.defaults          # ESP32-S3 config (NimBLE, USB host, flash)
├── src/
│   ├── main.rs                 # app_main, event loop, bridge state
│   ├── ble.rs                  # NimBLE NUS service (advertise, GATT, notify)
│   ├── usb.rs                  # USB host: enumeration, multi-chip, baud, TX/RX
│   ├── protocol.rs             # Protobuf encode/decode, BLE dispatch
│   ├── detect.rs               # Radio auto-detection state machine
│   ├── verify.rs               # Set-and-verify command translation
│   ├── display.rs              # SSD1306 via embedded-graphics
│   └── generated/
│       └── cwbp.rs             # Checked-in prost output
proto/                          # Monorepo root — shared by firmware + Swift
└── cwbp.proto
```

### Module Mapping (C → Rust)

| C Module | Rust Module | Key Changes |
|----------|-------------|-------------|
| `main.c` | `main.rs` | FreeRTOS tasks → `std::thread::spawn`, `mpsc` event loop |
| `bridge_protocol.c/h` | `protocol.rs` | Hand-rolled bytes → prost encode/decode |
| `radio_detect.c/h` | `detect.rs` | Switch/case → `enum` + `match` state machine |
| `radio_verify.c/h` | `verify.rs` | Same pattern, Rust enums for fields/modes |
| `usb_cat.c/h` | `usb.rs` | `unsafe` FFI into `usb_host_*`, wrapped in safe `UsbHost` struct |
| `ble_nus.c/h` | `ble.rs` | `esp_idf_svc::bt` NimBLE wrappers where possible |
| `display.c/h` | `display.rs` | `ssd1306` + `embedded-graphics` crates |

### What Rust Buys

1. **Protocol layer becomes trivial.** Prost-generated structs replace all manual byte packing.
2. **Detection/verify state machines are cleaner.** Enum variants carry data, `match` is exhaustive.
3. **Display is nicer.** `embedded-graphics` has real primitives (rectangles, text, fonts).
4. **No buffer overflows.** All the `memcpy` + `buf_len` checks disappear.
5. **One language.** No C/Rust boundary to maintain.

### What Rust Costs

1. **USB host is `unsafe` FFI.** The `usb_host_transfer_submit()` loop is the same complexity in any language — safety comes from the `UsbHost` wrapper API, not the internals.
2. **NimBLE setup may need raw FFI.** NUS GATT service registration might not be fully wrapped by `esp_idf_svc`.
3. **Build times.** Clean: ~3-5 min (vs ~30s C). Incremental: ~30-60s (vs ~5s).
4. **Ecosystem maturity.** ESP-IDF Rust bindings lag behind C. May need to pin `esp-idf-sys` version.

### Sketch: main.rs

```rust
use esp_idf_svc::hal::prelude::*;
use std::sync::mpsc;

mod ble;
mod detect;
mod display;
mod protocol;
mod usb;
mod verify;

/// Events flowing from peripherals to the main loop
enum BridgeEvent {
    BleConnected,
    BleDisconnected,
    BleData(Vec<u8>),
    UsbConnected { vid: u16, pid: u16 },
    UsbDisconnected,
    UsbData(Vec<u8>),
    RadioDetected(detect::DetectResult),
    RadioDetectFailed,
    VerifyComplete(protocol::SetResult),
}

fn main() {
    esp_idf_svc::sys::link_patches();
    esp_idf_svc::log::EspLogger::initialize_default();

    let (tx, rx) = mpsc::channel::<BridgeEvent>();

    let ble = ble::Ble::init(tx.clone());
    let usb = usb::UsbHost::init(tx.clone());
    let mut display = display::Display::init();
    let detector = detect::Detector::new(tx.clone());
    let verifier = verify::Verifier::new(tx.clone());

    let mut state = BridgeState::default();

    log::info!("CW Bridge running");

    loop {
        match rx.recv_timeout(std::time::Duration::from_millis(500)) {
            Ok(event) => {
                match event {
                    BridgeEvent::BleData(data) => {
                        let msg = protocol::decode(&data);
                        protocol::dispatch(msg, &ble, &usb, &detector, &verifier, &mut state);
                    }
                    BridgeEvent::UsbData(data) => {
                        let frame = protocol::encode_cat_data(&data);
                        ble.send(&frame);
                    }
                    BridgeEvent::UsbConnected { vid, pid } => {
                        state.usb_connected = true;
                        protocol::send_status(&ble, StatusCode::UsbConnected);
                        detector.start(vid, pid);
                    }
                    BridgeEvent::UsbDisconnected => {
                        state.usb_connected = false;
                        state.radio = None;
                        protocol::send_status(&ble, StatusCode::UsbDisconnected);
                    }
                    BridgeEvent::RadioDetected(result) => {
                        protocol::send_radio_info(&ble, &result);
                        protocol::send_status(&ble, StatusCode::Ready);
                        state.radio = Some(result);
                    }
                    BridgeEvent::RadioDetectFailed => {
                        protocol::send_status(&ble, StatusCode::DetectionFailed);
                    }
                    BridgeEvent::VerifyComplete(result) => {
                        protocol::send_set_result(&ble, result);
                    }
                    BridgeEvent::BleConnected => {
                        state.ble_connected = true;
                    }
                    BridgeEvent::BleDisconnected => {
                        state.ble_connected = false;
                    }
                }
            }
            Err(mpsc::RecvTimeoutError::Timeout) => {}
            Err(_) => break,
        }

        display.update(&state);
    }
}
```

### Sketch: detect.rs

```rust
use crate::protocol::{BaudIndex, RadioProtocol};
use crate::usb::UsbHost;
use std::time::Duration;

pub struct DetectResult {
    pub protocol: RadioProtocol,
    pub baud: BaudIndex,
    pub id_string: String,
    pub civ_address: Option<u8>,
}

fn candidate_bauds(vid: u16, pid: u16) -> &'static [u32] {
    match (vid, pid) {
        (0x0403, _) => &[38_400, 9_600, 19_200, 115_200], // FTDI
        (0x10C4, _) => &[19_200, 38_400, 9_600, 115_200], // CP210x
        _           => &[9_600, 38_400, 19_200, 115_200],
    }
}

pub fn detect(usb: &UsbHost, vid: u16, pid: u16) -> Option<DetectResult> {
    for &baud in candidate_bauds(vid, pid) {
        usb.set_baud(baud);
        usb.set_latency(1);

        // Try Kenwood
        usb.send(b"ID;");
        if let Some(resp) = usb.recv_timeout(Duration::from_millis(500)) {
            if let Some(id) = parse_kenwood_id(&resp) {
                usb.set_latency(16);
                return Some(DetectResult {
                    protocol: RadioProtocol::Kenwood,
                    baud: BaudIndex::from_rate(baud),
                    id_string: id,
                    civ_address: None,
                });
            }
        }

        // Try CI-V
        usb.send(&[0xFE, 0xFE, 0x00, 0xE0, 0x19, 0x00, 0xFD]);
        if let Some(resp) = usb.recv_timeout(Duration::from_millis(500)) {
            if let Some((addr, id)) = parse_civ_id(&resp) {
                usb.set_latency(16);
                return Some(DetectResult {
                    protocol: RadioProtocol::CIV,
                    baud: BaudIndex::from_rate(baud),
                    id_string: id,
                    civ_address: Some(addr),
                });
            }
        }
    }

    usb.set_latency(16);
    None
}
```

---

## Protobuf Protocol

### Proto Definition

```protobuf
syntax = "proto3";
package cwbp;

// One BLE notification = one serialized BridgeMessage.
message BridgeMessage {
  oneof msg {
    HandshakeReq   handshake_req   = 1;
    HandshakeRsp   handshake_rsp   = 2;
    CatData        cat_data        = 3;
    Status         status          = 4;
    RadioInfo      radio_info      = 5;
    RequestDetect  request_detect  = 6;
    SetBaud        set_baud        = 7;
    SetVerify      set_verify      = 8;
    SetResult      set_result      = 9;
  }
}

message HandshakeReq {
  uint32 protocol_version = 1;
}

message HandshakeRsp {
  uint32 protocol_version = 1;
  string firmware_version = 2;
  uint32 capabilities     = 3;
}

message CatData {
  bytes payload = 1;
}

message Status {
  StatusCode code   = 1;
  string     detail = 2;
}

enum StatusCode {
  STATUS_UNKNOWN           = 0;
  STATUS_USB_CONNECTED     = 1;
  STATUS_USB_DISCONNECTED  = 2;
  STATUS_DETECTING         = 3;
  STATUS_DETECTION_FAILED  = 4;
  STATUS_ERROR             = 5;
  STATUS_READY             = 6;
}

message RadioInfo {
  RadioProtocol protocol  = 1;
  uint32        baud_rate = 2;
  string        id_string = 3;
}

enum RadioProtocol {
  PROTO_UNKNOWN  = 0;
  PROTO_KENWOOD  = 1;
  PROTO_CIV      = 2;
}

message RequestDetect {}

message SetBaud {
  uint32 baud_rate = 1;
}

message SetVerify {
  SetVerifyField field = 1;
  bytes          value = 2;
}

enum SetVerifyField {
  FIELD_UNKNOWN        = 0;
  FIELD_FREQUENCY      = 1;
  FIELD_MODE           = 2;
  FIELD_PTT            = 3;
  FIELD_XIT            = 4;
  FIELD_RIT            = 5;
  FIELD_RIT_XIT_OFFSET = 6;
  FIELD_CLEAR_RIT_XIT  = 7;
}

message SetResult {
  SetResultCode result = 1;
}

enum SetResultCode {
  RESULT_OK          = 0;
  RESULT_FAIL        = 1;
  RESULT_UNSUPPORTED = 2;
}
```

### Wire Size Comparison

| Message | Old CWBP (bytes) | Protobuf (bytes) | Delta |
|---------|-----------------|-------------------|-------|
| Handshake RSP | 7 | ~15 | +8 (string FW version) |
| Status (ready) | 3 | 4 | +1 |
| RadioInfo (KX2) | ~10 | ~15 | +5 |
| CatData (10 bytes) | 12 | 14 | +2 |
| CatData (100 bytes) | 102 | 105 | +3 |
| SetVerify (freq) | 11 | 15 | +4 |

Overhead is 1-8 bytes per message. Negligible at 512-byte MTU.

### Rust Side (prost)

Codegen script (run manually when proto changes):

```bash
# From monorepo root
protoc --prost_out=firmware/src/generated proto/cwbp.proto
```

```rust
// protocol.rs
mod generated {
    pub mod cwbp;
}

use generated::cwbp::{self, bridge_message::Msg, BridgeMessage};
use prost::Message;

pub fn decode(data: &[u8]) -> Option<BridgeMessage> {
    BridgeMessage::decode(data).ok()
}

pub fn encode_cat_data(cat_bytes: &[u8]) -> Vec<u8> {
    BridgeMessage {
        msg: Some(Msg::CatData(cwbp::CatData {
            payload: cat_bytes.to_vec(),
        })),
    }
    .encode_to_vec()
}

pub fn encode_status(code: cwbp::StatusCode, detail: Option<&str>) -> Vec<u8> {
    BridgeMessage {
        msg: Some(Msg::Status(cwbp::Status {
            code: code.into(),
            detail: detail.unwrap_or_default().into(),
        })),
    }
    .encode_to_vec()
}
```

### Swift Side (SwiftProtobuf)

Codegen script:

```bash
protoc --swift_out=swift/packages/CarrierWaveCore/Sources/CarrierWaveCore/Generated proto/cwbp.proto
```

Replaces `BridgeFrame.swift` manual parsing with generated types:

```swift
import SwiftProtobuf

// BridgeProtocol.swift — decode incoming
func handleIncomingData(_ data: Data) {
    guard let msg = try? Cwbp_BridgeMessage(serializedBytes: data) else {
        catContinuation?.yield(data)
        return
    }

    switch msg.msg {
    case .handshakeRsp(let rsp):
        mode = .framed
        firmwareVersion = rsp.firmwareVersion
        capabilities = UInt8(rsp.capabilities)
        eventContinuation?.yield(.handshakeComplete(
            fwVersion: rsp.firmwareVersion,
            capabilities: UInt8(rsp.capabilities)
        ))

    case .catData(let cat):
        catContinuation?.yield(cat.payload)

    case .status(let status):
        eventContinuation?.yield(mapStatus(status))

    case .radioInfo(let info):
        eventContinuation?.yield(.radioDetected(
            protocolType: mapProto(info.protocol),
            baudRate: info.baudRate,
            rawID: info.idString
        ))

    case .setResult(let result):
        eventContinuation?.yield(.setVerifyResult(
            result: mapResultCode(result.result)
        ))

    default:
        break
    }
}

// Encode outgoing
func sendCatData(_ catBytes: Data) async throws {
    var msg = Cwbp_BridgeMessage()
    msg.msg = .catData(.with { $0.payload = catBytes })
    try await rawTransport.send(try msg.serializedData())
}
```

---

## Implementation Order

No phasing needed — firmware isn't deployed, do it all at once:

1. **Create `proto/cwbp.proto`** and generate both Rust and Swift code
2. **Scaffold `firmware/`** — `Cargo.toml`, `sdkconfig.defaults`, module stubs
3. **Port `display.rs`** — standalone, good first test that the toolchain works
4. **Port `detect.rs` + `verify.rs`** — pure logic with USB abstraction
5. **Port `usb.rs`** — `unsafe` FFI wrapper around `usb_host_*` APIs
6. **Port `ble.rs`** — NimBLE NUS service
7. **Wire up `protocol.rs` + `main.rs`** — protobuf dispatch, event loop
8. **Update Swift side** — replace `BridgeFrame.swift` with SwiftProtobuf generated code, update `BridgeProtocol.swift`
9. **Delete old C source** — `main/` directory, old `Makefile`, `CMakeLists.txt`

## Risks

| Risk | Likelihood | Mitigation |
|------|-----------|------------|
| NimBLE NUS needs raw FFI | High | Budget extra time for GATT service setup |
| USB host `unsafe` is tedious | High | Port line-by-line from C, keep same structure |
| `esp-idf-sys` version mismatch | Medium | Pin to known-good ESP-IDF version |
| `prost` binary size on ESP32 | Low | 8MB flash, plenty of room |
| `xtensa` toolchain instability | Low | `esp-rs` ships stable nightly builds |
