# Icom WiFi CAT Control & Shared RadioSession

**Date:** 2026-03-27
**Status:** Approved

## Summary

Add Icom WiFi CAT control to Carrier Wave (iOS) via the IC-705's built-in WiFi, and refactor the radio connectivity stack so iOS and macOS share a common `RadioSession` and protocol handler layer from CarrierWaveData.

## Goals

- Connect to IC-705 (and other WiFi-capable Icom radios) over WiFi for CAT control (read/set frequency, read/set mode)
- Refactor the radio stack: move `RadioSession`, `RadioProtocolHandler`, `FrameAssembler`, and CI-V/Kenwood protocol handlers into the shared CarrierWaveData package
- Rename "BLE Radio" UI to "Radio" with a transport picker (BLE / WiFi)
- Store WiFi credentials (username/password) in Keychain

## Non-Goals (V1)

- Audio streaming (port 50003)
- PTT control UI
- S-meter reading
- CW keying over WiFi
- BLE GATT for IC-705 (Icom-proprietary BLE service)
- Network/Bonjour discovery for Station mode
- Yaesu WiFi support

## Architecture

### What moves to CarrierWaveData

| Component | Currently | Destination |
|-----------|-----------|-------------|
| `RadioTransport` protocol | CarrierWaveData | stays |
| `RadioSession` actor | CWSweep | CarrierWaveData |
| `RadioProtocolHandler` protocol | CWSweep | CarrierWaveData |
| `CIVProtocolHandler` struct | CWSweep | CarrierWaveData |
| `KenwoodProtocolHandler` struct | CWSweep | CarrierWaveData |
| `FrameAssembler` actor | CWSweep | CarrierWaveData |
| `IcomWiFiTransport` actor (new) | — | CarrierWaveData |

### What stays platform-specific

**iOS (CarrierWave):**
- `BLERadioTransport` — extracted from `BLERadioClient`, CoreBluetooth NUS transport conforming to `RadioTransport`
- `RadioService` (renamed from `BLERadioService`) — `@MainActor @Observable`, owns a `RadioSession` with either BLE or WiFi transport
- Settings UI — transport picker, BLE scan, WiFi config

**macOS (CWSweep):**
- `YaesuProtocolHandler`, `ElecraftProtocolHandler`, `FlexProtocolHandler` — extended protocol handlers, conform to shared `RadioProtocolHandler`
- `SCULAN10Transport`, `FlexRadioTransport`, `SerialRadioTransport` — macOS-only transports
- `RadioManager` — multi-radio session management, SO2R, waterfall

### Deleted

- `BLERadioClient` — replaced by `BLERadioTransport` + shared `RadioSession`
- `RigProtocolHandler` (iOS) — replaced by shared `RadioProtocolHandler` protocol + `CIVProtocolHandler`/`KenwoodProtocolHandler`
- `RigProtocol` enum (iOS) — replaced by shared protocol handler selection
- `RigResponse` enum (iOS) — replaced by `FrameAssembler` output
- CWSweep's local copies of `RadioSession`, `RadioProtocolHandler`, `CIVProtocolHandler`, `KenwoodProtocolHandler`, `FrameAssembler`

## IcomWiFiTransport

New actor in CarrierWaveData conforming to `RadioTransport`. Implements the Icom RS-BA1 UDP session protocol.

### Configuration

```swift
struct IcomWiFiConfig {
    enum Mode { case accessPoint, station }
    var mode: Mode
    var ipAddress: String  // "192.168.59.1" for AP, user-entered for station
    var username: String
    var password: String
}
```

### UDP Ports

| Port | Purpose |
|------|---------|
| 50001 | Control — session management, login handshake, keepalive |
| 50002 | CI-V — radio command data |

Port 50003 (audio) is out of scope for V1.

### Connection Flow

1. Open UDP sockets to `<ip>:50001` (control) and `<ip>:50002` (CI-V)
2. Send connect request on control port
3. Authenticate with username/password handshake on control port
4. On success, mark connected — CI-V frames flow on CI-V port

### Keepalive

Background task sends idle/ping packets on control port every ~3 seconds. If no response after 3 missed keepalives (~9 seconds), mark disconnected and close sockets.

### UDP Implementation

Raw POSIX UDP sockets (same approach as existing `SCULAN10PortChannel` in CWSweep). NWConnection has known NAT/routing issues encountered with SCU-LAN10.

### Protocol Reference

The RS-BA1 handshake is documented in open-source implementations:
- [kappanhang](https://github.com/nonoo/kappanhang) — Go implementation
- [wfview](https://gitlab.com/eliggett/wfview) — C++ implementation

## iOS Refactor

### BLERadioClient → BLERadioTransport

Extract transport-only responsibilities into `BLERadioTransport` conforming to `RadioTransport`:
- CoreBluetooth scanning/discovery (NUS service UUIDs)
- `BLEDelegate` for CBCentralManager/CBPeripheral callbacks
- `connect()`, `disconnect()`, `send(_:)`, `receivedData: AsyncStream<Data>`
- Device discovery stream (for settings UI scanning)
- Auto-reconnect on unexpected disconnect

Removed from BLE layer (now handled by `RadioSession`):
- Protocol handling (`RigProtocolHandler`)
- Request/response matching (`sendAndWaitForResponse`)
- Receive buffer parsing
- Polling loop

### BLERadioService → RadioService

Renamed `@MainActor @Observable` service. Owns a `RadioSession` with either `BLERadioTransport` or `IcomWiFiTransport` based on user configuration.

Published state (`frequency`, `mode`, `connectionStatus`) comes from observing `RadioSession.state` via a polling or observation task.

Feedback loop prevention (suppress echoed frequency/mode changes within 500ms of app-initiated changes) moves into `RadioService` since `RadioSession` is transport-agnostic and shouldn't know about app-vs-radio change sources.

### Credential Storage

- Transport type, BLE device UUID/name, WiFi IP/mode: UserDefaults
- WiFi username/password: Keychain via existing `KeychainHelper` with service key `icomWifi`

## Settings UI

### Navigation Title

"BLE Radio" → "Radio"

### Transport Picker

Segmented control at top: **BLE** | **WiFi**

### BLE Section (shown when BLE selected)

Unchanged from current `BLERadioSettingsView`:
- Saved device with connect/disconnect/forget
- Scan for devices list

### WiFi Section (shown when WiFi selected)

- **Mode picker:** "Access Point" / "Station"
- **IP Address:**
  - AP mode: pre-filled `192.168.59.1`, not editable
  - Station mode: editable text field
- **Username:** text field
- **Password:** secure text field
- **Connect / Disconnect** button
- **Connection status** indicator

### Shared Sections (always shown)

- Protocol picker (CI-V / Kenwood)
- CI-V address field (when CI-V selected)

## macOS Migration

CWSweep adopts shared types from CarrierWaveData:
- Import `RadioSession`, `RadioProtocolHandler`, `CIVProtocolHandler`, `KenwoodProtocolHandler`, `FrameAssembler` from CarrierWaveData
- Delete local copies from CWSweep
- `YaesuProtocolHandler`, `ElecraftProtocolHandler`, `FlexProtocolHandler` stay in CWSweep, conform to shared `RadioProtocolHandler` protocol from CarrierWaveData
- `RadioManager` unchanged — just uses shared types

## V2 Roadmap

- **BLE GATT for IC-705** — Icom's proprietary BLE service with `FEF1` framing and custom pairing commands (`0061`/`0062`/`0063`)
- **Audio streaming** — port 50003 Rx/Tx audio over WiFi
- **PTT control** — already in `RadioProtocolHandler`, needs UI wiring
- **S-meter reading** — CI-V command `0x15 0x02`
- **CW keying over WiFi** — CI-V command `0x17`
- **Network discovery** — Bonjour/mDNS scanning for Station mode
- **Yaesu WiFi** — extend pattern for Yaesu radios (different protocol, similar UDP architecture)
