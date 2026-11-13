# CW Bridge Memory Keyer — CWBP Extension

**Status:** design sketch
**Context:** Extends the Carrier Wave Bridge Protocol (CWBP) with CW keyer commands. The bridge already handles handshake, radio auto-detection, framed CAT passthrough, and set-verify. This adds CW text sending, memory slots, speed control, and buffer tracking as new CWBP message types.

---

## 1. Current Architecture

```
┌─────────────────────────┐          ┌──────────────────┐          ┌────────────┐
│ Carrier Wave            │  BLE     │ CW Bridge        │  USB CDC │ Radio      │
│ (iOS / macOS / watchOS) │ ───────▶ │ (ESP32-S3, C)    │ ───────▶ │ (KX2/K3/   │
│                         │ CWBP     │ - CWBP dispatch   │ CAT      │  IC-705/   │
│ - RadioService          │ 0xCB     │ - auto-detect     │ bytes    │  FTX-1)    │
│ - BridgeProtocol        │ framing  │ - set-verify      │          │            │
│ - BridgeFrame           │          │ - radio_verify.c  │          │            │
└─────────────────────────┘          └──────────────────┘          └────────────┘
```

Today the bridge is a **framed relay with semantic set-verify**. The app sends raw CAT in `CAT_DATA` frames, and the bridge unwraps/rewraps them. For frequency/mode/PTT/RIT/XIT, the app sends `SET_VERIFY` commands and the firmware translates to Kenwood or CI-V, sends, reads back, and reports OK/FAIL/UNSUPPORTED.

CW keying follows the same pattern as set-verify: the app sends a semantic command ("send this text at this speed"), and the firmware translates to the detected radio's CW CAT commands, manages the buffer, and reports status back.

### Why firmware dispatch for CW (same argument as set-verify)

- **Timing lives next to the UART.** Buffer polling, refill pacing, and mid-message speed changes need sub-100ms response. BLE round-trip latency (20-80ms variable) makes app-side buffer management unreliable.
- **Protocol translation is already in firmware.** `radio_verify.c` already has Kenwood and CI-V encoding with the `usb_cat_set_detect_rx` intercept pattern. CW commands use the same mechanism.
- **One wire format.** The app sends `CW_SEND` regardless of radio. No `KY` vs `0x17` in Swift.

**Honest tradeoff:** the bridge becomes radio-aware for CW, meaning firmware updates gate new-radio CW support. The existing `CAT_DATA` passthrough still works for radios without firmware CW drivers — the app can always fall back to encoding `KY text;` itself and sending it as raw CAT.

---

## 2. New CWBP Message Types

Extends `bridge_protocol.h`. Existing types 0x01-0x09 unchanged.

### 2.1 App → Bridge

| Type | Name | Payload | Purpose |
|------|------|---------|---------|
| 0x0A | `CW_SEND` | `[text bytes]` | Send CW text, expanding prosigns |
| 0x0B | `CW_STOP` | (none) | Abort CW, flush radio buffer |
| 0x0C | `CW_SPEED` | `[u8 wpm]` | Set keyer speed |
| 0x0D | `CW_SLOT_PLAY` | `[u8 slot]` | Play stored memory slot (1-8) |
| 0x0E | `CW_SLOT_SET` | `[u8 slot][text bytes]` | Store text in memory slot |
| 0x0F | `CW_STATUS_REQ` | (none) | Query CW engine state |

### 2.2 Bridge → App

| Type | Name | Payload | Purpose |
|------|------|---------|---------|
| 0x10 | `CW_ACK` | `[u8 result][u8 buf_depth]` | Command accepted/rejected |
| 0x11 | `CW_PROGRESS` | `[u8 buf_depth][u8 flags]` | Async buffer/TX updates |
| 0x12 | `CW_STATUS_RSP` | `[u8 wpm][u8 buf_depth][u8 flags][u8 slot_count]` | Full state snapshot |

### 2.3 Result codes (CW_ACK byte 0)

| Code | Meaning |
|------|---------|
| 0x00 | OK — text accepted, sending |
| 0x01 | QUEUED — accepted but previous send still active |
| 0x02 | FAIL — radio offline, busy, or encoding error |
| 0x03 | UNSUPPORTED — radio has no CW keying support |
| 0x04 | BAD_SLOT — slot number out of range |
| 0x05 | EMPTY — slot has no stored text |

### 2.4 Progress flags (CW_PROGRESS byte 1)

| Bit | Meaning |
|-----|---------|
| 0 | TX active (radio is transmitting) |
| 1 | Buffer draining (last chunk queued) |
| 2 | Send complete (buffer empty, TX done) |

### 2.5 Capability flag

Add `CWBP_CAP_CW_KEYER (1 << 3)` to handshake response. The app checks this before showing keyer UI over the bridge connection.

---

## 3. Firmware CW Engine

### 3.1 Module structure

New files: `cw_engine.c/h` (state machine + slot storage) and `cw_driver.c/h` (per-protocol encoding). Follows the same pattern as `radio_verify.c`: intercepts USB RX during CW operations, runs on a FreeRTOS task.

### 3.2 State machine

```
Idle ──CW_SEND/SLOT_PLAY──▶ Chunking ──USB TX──▶ Sending ──poll──▶ Draining ──▶ Idle
                                │                    │                 │
                                └────CW_STOP─────────┴─────────────────┘
```

- **Idle:** no CW activity. CW_SEND/CW_SLOT_PLAY transitions to Chunking.
- **Chunking:** split text into radio-sized pieces (`max_chunk` per protocol), send first chunk. Transition to Sending.
- **Sending:** radio is transmitting. Poll buffer depth (protocol-specific). Refill when space available. Push `CW_PROGRESS` at 25%/50%/75%/empty thresholds.
- **Draining:** last chunk sent. Wait for buffer-empty indication, then push `CW_PROGRESS` with "send complete" flag. Return to Idle.
- **CW_STOP from any state:** send radio-specific abort, flush state, push `CW_PROGRESS` with "send complete." Return to Idle.

### 3.3 Per-protocol CW encoding

Two implementations, selected by `s_detected_proto` (already cached in `main.c`):

**Kenwood/Elecraft:**
```
send_text(s)   → "KY <s>;"   up to 24 chars per call
stop()         → "RX;"
set_speed(w)   → "KS{:03};"
poll_buffer()  → "TB;" → parse TBtrrs; (t = TX state, r = chars remaining)
max_chunk      = 24
prosigns       = inline: ( KN  + AR  = BT  % AS  * SK
```

**CI-V (Icom):**
```
send_text(s)   → FE FE <addr> E0 17 <ASCII bytes> FD
stop()         → send 0xFF in 0x17 payload, OR FE FE <addr> E0 1C 00 00 FD
set_speed(w)   → FE FE <addr> E0 14 0C <BCD speed> FD
poll_buffer    → no direct command; software estimate from WPM × elapsed
max_chunk      = 30
prosigns       = "^" prefix suppresses inter-character space
```

The driver interface (C function pointers, not a trait):

```c
typedef struct {
    size_t (*encode_send)(const char *text, size_t text_len,
                          uint8_t *buf, size_t buf_len);
    size_t (*encode_stop)(uint8_t *buf, size_t buf_len);
    size_t (*encode_speed)(uint8_t wpm, uint8_t *buf, size_t buf_len);
    size_t (*encode_poll)(uint8_t *buf, size_t buf_len);
    int    (*parse_poll)(const uint8_t *rx, size_t rx_len);  /* returns chars remaining, -1 on error */
    size_t max_chunk;
    bool   has_native_poll;
} cw_driver_t;

const cw_driver_t *cw_driver_for_proto(uint8_t proto, uint8_t civ_addr);
```

### 3.4 Slot storage

Eight template slots in NVS, up to 120 chars each (matches tightest radio buffer — Elecraft 24 chars × 5 refills). Slots persist across power cycles.

```c
esp_err_t cw_slot_get(uint8_t slot, char *buf, size_t buf_len);
esp_err_t cw_slot_set(uint8_t slot, const char *text, size_t text_len);
```

The canonical storage is the bridge, not the radio. The radio's own memory slots are ignored. This gives consistent behavior across radios and template support that no radio's native memory system has.

### 3.5 Template expansion

Placeholders `{NAME}` are expanded at send time. The bridge does **not** store QSO context — the app sends fully expanded text via `CW_SEND`. Templates are stored in slots with placeholders unexpanded.

When the app triggers `CW_SLOT_PLAY`, it includes a context payload so the bridge can expand:

| Type | Name | Payload |
|------|------|---------|
| 0x0D | `CW_SLOT_PLAY` | `[u8 slot][u8 ctx_count][key_len u8][key bytes][val_len u8][val bytes]...` |

If `ctx_count` is 0, the slot text is sent verbatim (no expansion).

Placeholder allowlist: `CALL`, `SN`, `RST`, `NAME`, `EXCH`, `MYCALL`.

Prosigns `{BT}`, `{AR}`, `{SK}`, `{KN}`, `{AS}` are expanded to the radio's native encoding (Kenwood inline characters, CI-V `^` prefix sequences).

Inline speed changes `{SPEED:40}` are split into separate chunks with interleaved speed-set commands.

### 3.6 RX intercept and concurrency

CW engine uses the same `usb_cat_set_detect_rx()` intercept as `radio_verify.c`. Only one subsystem can intercept at a time. If a `SET_VERIFY` is in progress when `CW_SEND` arrives, reject with `CW_ACK(FAIL)`. The CW engine holds the intercept for the duration of the send (Chunking → Sending → Draining → Idle).

During CW sends, normal CAT_DATA passthrough is **paused** — the bridge must own the USB RX path to poll buffer depth. The app should avoid sending raw CAT during active CW.

---

## 4. iOS Integration

### 4.1 BridgeFrame extensions

Add to `BridgeFrame.MessageType`:
```swift
case cwSend = 0x0A
case cwStop = 0x0B
case cwSpeed = 0x0C
case cwSlotPlay = 0x0D
case cwSlotSet = 0x0E
case cwStatusReq = 0x0F
case cwAck = 0x10
case cwProgress = 0x11
case cwStatusRsp = 0x12
```

Add frame builders:
```swift
static func buildCWSend(_ text: String) -> Data
static func buildCWStop() -> Data
static func buildCWSpeed(wpm: UInt8) -> Data
static func buildCWSlotPlay(slot: UInt8, context: [String: String]) -> Data
static func buildCWSlotSet(slot: UInt8, text: String) -> Data
static func buildCWStatusReq() -> Data
```

### 4.2 BridgeEvent extensions

```swift
case cwAck(result: CWAckResult, bufferDepth: UInt8)
case cwProgress(bufferDepth: UInt8, txActive: Bool, complete: Bool)
case cwStatus(wpm: UInt8, bufferDepth: UInt8, txActive: Bool, slotCount: UInt8)
```

### 4.3 Keyer UI service

A new `CWKeyerService` (actor, `@MainActor`-bound for UI state) manages keyer state. It talks to `BridgeProtocol` for bridge-connected radios, and falls back to direct CAT encoding via `RadioProtocolHandler.encodeSendCW()` for non-bridge connections (WiFi CAT, etc.).

The app UI (F1-F8 buttons, speed knob, abort button) binds to this service. The "dim the button while CQ is transmitting" behavior uses `cwProgress` events — buffer depth > 0 means the button stays lit.

---

## 5. State Synchronization

The bridge pushes `CW_PROGRESS` when:
- Buffer depth crosses a 25% / 50% / 75% / empty threshold (debounced to one notification per threshold crossing)
- TX/RX edge transitions
- Send completes

The app can also poll with `CW_STATUS_REQ` on foreground resume. The protocol tolerates missed notifications — the app re-syncs by polling.

**Background mode note:** on iOS, BLE notifications drop when backgrounded without `bluetooth-central` background mode. For POTA activations with screen off, the app needs this entitlement. Even with it, iOS may throttle. Design for eventual consistency, not real-time.

---

## 6. Error Handling

Every `CW_SEND`, `CW_SLOT_PLAY`, `CW_SPEED`, and `CW_SLOT_SET` gets a `CW_ACK` within 500ms. If the app gets nothing back, that's a firmware bug.

Transport errors (USB disconnect mid-send): CW engine transitions to Idle, pushes `CW_PROGRESS` with "send complete" flag. The app sees the USB disconnect via existing `STATUS(USB_DISCONNECTED)` and knows the send was interrupted.

If the radio rejects a CW command (Kenwood `?;`, CI-V `0xFA`): `CW_ACK(FAIL)`. The app can show "Radio rejected CW command" and the user can check radio settings.

---

## 7. Per-Radio Notes

### Elecraft (K3, K3S, KX2, KX3, K4)
- `KY <text>;` — 24 chars max per call. `KYW` gates follow-on commands.
- `TB;` reports `TBtrrs;` — `t` is TX chars remaining. Clean polling.
- `KS{:03};` for speed. Mid-message speed interleave works (KS/KYW).
- Prosigns: `( KN  + AR  = BT  % AS  * SK  ! VE`
- K4 same driver with version sniff.
- **Stop:** `RX;` during `KY` loop.

### Icom (IC-7300, IC-7610, IC-705, IC-9700)
- `0x17` command — 30 chars max. `^` prefix for prosigns (no inter-char space).
- No buffer polling command. Software estimate from WPM × elapsed time.
- `0xFF` in payload to abort, or `1C 00 00` to force RX.
- Speed: `14 0C <BCD>` subcommand.
- **This is why bridge-side CW matters:** the bridge is effectively being the keyer memory system for Icom, because the radio doesn't have one via CI-V.

### Yaesu (FTDX10, FT-991A, FT-710, FTX-1)
- Not yet implemented in bridge firmware. When added: `KY0<text>;` (50-char buffer), `KY;` polls 0/1/2/3 status, `KS{:03};` for speed.
- Would require adding `CWBP_PROTO_YAESU` (0x03) to bridge_protocol.h and a third driver.
- Lower priority — the existing `CAT_DATA` passthrough lets the app send Yaesu CW commands directly.

### Kenwood (TS-590SG, TS-890S)
- Same as Elecraft driver (`KY`, `TB;`, `KS`). Add if a user complains.

### FlexRadio
- Skip in firmware. Flex speaks TCP — the app connects directly without the bridge. CW keyer logic for Flex lives in Swift using the same `CWKeyerService` interface.

---

## 8. Open Design Questions

- **QSK / break-in interaction.** Full QSK on an Elecraft means the radio returns to RX between dits. If the bridge sends `RX;` (stop) while QSK-ing, the command may race with a dit. Needs bench testing with KX2.
- **Paddle interleaving.** If the operator hits the paddle mid-`CW_SEND`, behavior is radio-specific: Elecraft aborts the buffer and switches to paddle; Icom ignores paddle until buffer drains. Document per-radio behavior, don't try to normalize.
- **Speed change semantics.** `CW_SPEED` applies immediately (mid-message if sending). Some radios handle this cleanly (Elecraft), some don't (Icom speed changes may only take effect at next `0x17` command). The bridge does best-effort.
- **Template scope.** The initial placeholder set (`CALL`, `SN`, `RST`, `NAME`, `EXCH`, `MYCALL`) covers contests and casual operating. Contesters may want custom placeholders — consider making the set extensible via a future `CW_SLOT_SET_VARS` command rather than hardcoding.
- **Slot sync with radio.** The radio's own M1-M4 are ignored. For users who also operate standalone (no app), syncing bridge slots to radio slots could be nice but is a lot of work for narrow use. Defer.

---

## 9. Implementation Order

1. **CWBP message types + CW_ACK/PROGRESS framing.** No radio yet — loopback to validate iOS parsing.
2. **Kenwood/Elecraft CW driver** with KX2 on bench. `KY`, `TB;`, `KS`, `RX;`. End-to-end BLE → CW audio.
3. **Slot storage in NVS.** CW_SLOT_SET, CW_SLOT_PLAY without templates (verbatim text only).
4. **Template expansion.** Add context to CW_SLOT_PLAY, prosign mapping.
5. **iOS keyer UI.** F1-F8 buttons, speed control, abort, progress dimming.
6. **CI-V/Icom CW driver.** Hardest — no native poll, software timing estimate.
7. **Yaesu driver.** When hardware is available for testing.

Ship 1-3 with the KX2, use it at a POTA activation, then iterate.

---

## 10. Testing Strategy

Three layers:

1. **Driver unit tests (host-side).** Given a CW_SEND payload, assert the exact Kenwood/CI-V bytes emitted. Fuzz template expansion. Golden-file CAT traces.
2. **HIL with radio.** Physical KX2 on the bench. Run the full command set over BLE: send, stop, speed, slots. Record audio output and decode with fldigi/MRP40 to verify character accuracy.
3. **Soak test.** Replay a contest log's CW F-key timing at the bridge for an hour. Assert no dropped characters, no stuck TX, no BLE disconnects. Use CW decoder to verify end-to-end.
