# Radio Connection (CAT Control) — Research & Design

> Deep research into adding Computer Aided Transceiver (CAT) control to Carrier Wave on iPad, with a focus on practical connectivity and UX design.

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Technical Feasibility](#technical-feasibility)
3. [Supported Radios & Protocols](#supported-radios--protocols)
4. [Connectivity Architecture](#connectivity-architecture)
5. [UX Design](#ux-design)
6. [Implementation Plan](#implementation-plan)
7. [Sources](#sources)

---

## Executive Summary

**Can we do CAT control over USB on iPad?** No — not practically. Apple provides no high-level USB serial API for iPadOS. The DriverKit path (M1+ iPads, iPadOS 16+) requires Apple-granted entitlements, C++ driver code, and has minimal documentation for serial devices. USBSerialDriverKit is macOS-only. No shipping ham radio app uses direct USB serial on iPad.

**What works instead?** Three practical connectivity paths exist:

| Method | Radios | No Extra Hardware | Field-Ready |
|--------|--------|:-----------------:|:-----------:|
| **WiFi (Icom UDP)** | IC-705, IC-7610, IC-7760, IC-9700, IC-7300 mk2 | Yes | Yes |
| **WiFi (Yaesu SCU-LAN)** | FT-710, FTdx-10, FTdx-101 | No (SCU-LAN box) | Maybe |
| **WiFi bridge (SOTAcat)** | KX2, KX3, KH1 | No ($60 dongle) | Yes |
| **Network relay (hamlib/flrig)** | Any radio | No (computer) | No |
| **Bluetooth** | IC-705 (built-in), KX2/KX3 (DIY) | Varies | Yes |

**Recommendation:** Start with **Icom CI-V over WiFi** (the IC-705 is the #1 POTA portable radio and has built-in WiFi). Add **Bluetooth** for the IC-705 and potentially Elecraft radios second. Add **network relay (hamlib rigctld TCP)** third for maximum radio coverage. Skip direct USB serial entirely.

**Primary value for a logger:** Auto-populate frequency and mode into QSO entries. Eliminates the most tedious part of portable logging — manually typing frequency changes.

---

## Technical Feasibility

### USB Serial on iPadOS — Why Not

| Approach | Status | Blockers |
|----------|--------|----------|
| **Simple serial API** | Does not exist | Apple has never shipped one for iOS/iPadOS |
| **USBSerialDriverKit** | macOS only | Not available on iPadOS despite DriverKit being available |
| **DriverKit (USBDriverKit)** | Theoretically possible | Requires M1+ iPad, Apple entitlements, C++ DEXT, no serial samples exist |
| **ExternalAccessory** | Requires MFi | No ham radio has MFi certification |
| **IOKit** | Sandboxed on iPadOS | Serial port properties not accessible |

Apple's WWDC 2022 session "Bring your driver to iPad with DriverKit" brought USB/PCI/Audio driver support to M1 iPads, but SerialDriverKit was explicitly excluded. Developers report significant documentation gaps. No shipping App Store app does USB CDC ACM serial on iPadOS.

### WiFi/Network — The Proven Path

Multiple shipping iPad apps prove WiFi/network CAT control works:

- **SDR-Control for Icom** — Full rig control of IC-705/IC-7610/IC-9700 over WiFi/LAN (UDP). Ships on App Store. $39.99.
- **FT-Control for Yaesu** — Controls FT-710/FTdx-10/FTdx-101 via SCU-LAN. Ships on App Store.
- **TS-Control for Kenwood** — Controls TS-890 via LAN. Ships on App Store.
- **K3iNetwork** — Controls Elecraft K3/KX3/KX2 via WiFi relay through a computer.

All of these use standard iOS networking APIs (`NWConnection`, `Network.framework`) — no special entitlements needed.

### Bluetooth — Viable for Some Radios

- **IC-705** has built-in Bluetooth with CI-V support. RUMlogNG2Go for iPad uses this.
- **Elecraft KX2/KX3** can use a DIY Bluetooth module (Adafruit) for CAT over Bluetooth SPP/BLE.
- Standard iOS `CoreBluetooth` framework works for BLE. Classic Bluetooth SPP requires MFi or ExternalAccessory.

---

## Supported Radios & Protocols

### POTA Field Radio Landscape

The most common POTA portable radios and their connectivity options:

| Radio | CAT Protocol | WiFi | Bluetooth | USB Serial | iPad Viable? |
|-------|-------------|:----:|:---------:|:----------:|:------------:|
| **Icom IC-705** | CI-V | Built-in | Built-in | Yes (CP210x) | **Yes — WiFi or BT** |
| **Icom IC-7300** | CI-V | No | No | Yes (CP210x) | No (mk2 has WiFi) |
| **Icom IC-7610** | CI-V | Built-in | No | Yes | **Yes — WiFi** |
| **Yaesu FT-891** | Yaesu CAT | No | No | Yes (CP210x) | No |
| **Yaesu FT-818** | Yaesu CAT | No | No | Serial only | No |
| **Yaesu FT-710** | Yaesu CAT | SCU-LAN | No | Yes | **Yes — SCU-LAN** |
| **Elecraft KX2** | Kenwood-style | SOTAcat | DIY BT | Serial only | **Yes — SOTAcat** |
| **Elecraft KX3** | Kenwood-style | SOTAcat | DIY BT | Serial only | **Yes — SOTAcat** |
| **Xiegu G90** | Xiegu CAT | No | No | Yes | No |

### Protocol Details

#### Icom CI-V (Priority 1)

Binary protocol with framing:

```
[0xFE] [0xFE] [to_addr] [from_addr] [command] [sub_command] [data...] [0xFD]
```

- **Addresses:** IC-705 default = 0xA4, Controller = 0xE0
- **Key commands for logging:**
  - `0x03` — Read frequency (response: 5 bytes BCD, 1Hz resolution)
  - `0x04` — Read mode (response: mode byte + filter byte)
  - `0x05` — Set frequency
  - `0x06` — Set mode
  - `0x15 0x02` — Read S-meter
  - `0x1C 0x00` — Read TX state (for PTT status)
- **Over WiFi:** Same CI-V commands sent via UDP to port 50002 (serial port), wrapped in Icom's proprietary network framing
- **Baud rates (USB):** 9600, 19200 (typical)
- **Polling rate:** 5-10 Hz typical for frequency, 1 Hz for S-meter

#### Kenwood / Elecraft (Priority 2)

Text-based, semicolon-terminated ASCII protocol:

```
FA00014060000;    // Set VFO-A to 14.060 MHz
FA;               // Query VFO-A frequency → "FA00014060000;"
MD;               // Query mode → "MD1;" (LSB)
SM;               // Query S-meter → "SM0015;"
IF;               // Read transceiver info (frequency + mode + more)
```

- **Baud rates:** 4800–38400 (KX2/KX3 default 38400)
- **Polling:** Text-based, easy to parse
- **SOTAcat bridge:** Presents a WiFi access point, relays CAT commands

#### Yaesu CAT (Priority 3 — if SCU-LAN radios requested)

Two protocol generations:
- **Legacy (FT-817/818/891):** 5-byte binary commands, complex encoding
- **Modern (FT-710/FTdx-10/FTdx-101):** Text-based, similar to Kenwood

#### Network Relay — hamlib rigctld (Priority 3)

Text-based TCP protocol on default port 4532:

```
f           // Get frequency → "14060000"
m           // Get mode → "USB\n2400"
F 14060000  // Set frequency
M USB 2400  // Set mode
```

- Works with any radio hamlib supports (400+ models)
- Requires a computer running rigctld connected to the radio
- Standard TCP socket — trivial to implement in Swift with `NWConnection`

---

## Connectivity Architecture

### Phase 1: Icom WiFi (CI-V over UDP)

```
┌─────────────┐    WiFi/LAN    ┌──────────┐
│   iPad      │◄──────────────►│  IC-705   │
│  Carrier    │   UDP :50001   │  (WiFi)   │
│  Wave       │   UDP :50002   │           │
│             │   UDP :50003   │           │
└─────────────┘                └──────────┘
```

The IC-705's WiFi can operate in two modes:
- **Access Point mode** — Radio creates its own WiFi network (field use, no router needed)
- **Station mode** — Radio joins existing WiFi network (home use)

UDP ports:
- 50001: Control (connection management, authentication)
- 50002: Serial/CI-V (CAT commands)
- 50003: Audio (not needed for logging)

### Phase 2: Bluetooth (IC-705)

```
┌─────────────┐   Bluetooth    ┌──────────┐
│   iPad      │◄──────────────►│  IC-705   │
│  Carrier    │    BLE/SPP     │  (BT)    │
│  Wave       │                │           │
└─────────────┘                └──────────┘
```

IC-705 supports CI-V over Bluetooth. Same protocol, different transport.

### Phase 3: Network Relay

```
┌─────────────┐    WiFi/LAN    ┌──────────┐    USB/Serial    ┌──────────┐
│   iPad      │◄──────────────►│ Computer │◄───────────────►│  Any     │
│  Carrier    │  TCP :4532     │ (rigctld)│                  │  Radio   │
│  Wave       │                └──────────┘                  └──────────┘
```

---

## UX Design

### POTA Field Radio Landscape (2026 Survey, 1,181 votes)

The most popular POTA portable radios and their iPad connectivity:

| Rank | Radio | iPad CAT Path |
|:----:|-------|---------------|
| 1 | Yaesu FT-891 | Serial only — needs network relay |
| 2 | Xiegu G90 | Serial only — needs network relay |
| 3 | **Icom IC-705** | **WiFi built-in (AP mode for field)** |
| 4 | Elecraft KX2 | SOTAcat WiFi bridge ($60) |
| 5 | Elecraft KX3 | SOTAcat WiFi bridge ($60) |
| 6 | Yaesu FT-818ND | Serial only — needs network relay |
| 7 | Yaesu FT-710 | SCU-LAN interface |
| 8 | Elecraft KH1 | SOTAcat WiFi bridge |

The IC-705 is the clear first target: it's #3 overall, #1 among QRP portables, and the only popular radio with built-in WiFi for direct iPad connection with no extra hardware.

### Existing App UX Precedents

Key UX patterns from shipping apps, validated through the research:

| Pattern | Used By | Adopt? |
|---------|---------|:------:|
| **Test Connection button** (green/red feedback) | WSJT-X, Log4OM | Yes |
| **Green/red status LED** (persistent connection indicator) | N1MM+, Log4OM, RUMlogNG | Yes |
| **"Follow TRX" toggle** (disable auto-sync without disconnecting) | RUMlogNG | Yes |
| **Smart QSO clearing** (clear form when freq changes > threshold) | Log4OM | Consider |
| **Spot click-to-tune** (one tap QSY from spot list) | N1MM+, MacLoggerDX, POTACAT | Phase 5 |
| **AP mode for field** (radio creates WiFi hotspot, no internet) | SDR-Control + IC-705 | Yes |
| **Manual radio selection** (not auto-detect — too unreliable) | All apps | Yes |
| **CAT middleware** (connect to flrig/rigctld, not directly to radio) | N1MM+, MacLoggerDX | Phase 4 |

### The Logger Integration Spectrum

From the research, ham radio apps fall on a clear spectrum:

1. **No CAT** — User types frequency manually. Error-prone, tedious.
2. **Passive frequency reading** (read-only) — Logger polls radio, auto-fills frequency/mode/band. Logger never sends commands. **This is the sweet spot for a logging app.**
3. **Full rig control** (read/write) — Logger can tune radio, change modes, etc. Complex UI. Belongs in dedicated apps like SDR-Control.

**Carrier Wave should target level 2 (passive reading) as the MVP, with level 3 limited to spot-click-to-tune in a later phase.**

### Design Principles

1. **Logger-first, not rig-control** — We auto-populate frequency/mode, we don't try to be a full radio front panel
2. **Zero-config when possible** — Discover Icom radios on the network automatically
3. **Field-optimized** — Connection setup must work offline, in the field, with one hand
4. **Unobtrusive** — Radio data flows into QSO entries silently; connection status is visible but small
5. **Graceful degradation** — Everything works without a radio connection; it just adds convenience

### UX Flow

#### A. Connection Setup (Settings > Radio Connection)

```
┌─────────────────────────────────────────────┐
│ ← Radio Connection                          │
│                                             │
│ ┌─────────────────────────────────────────┐ │
│ │ 🟢 Connected · IC-705 · 14.060 MHz SSB │ │
│ └─────────────────────────────────────────┘ │
│                                             │
│ CONNECTION METHOD                           │
│ ┌─────────────────────────────────────────┐ │
│ │ ○ Icom WiFi                             │ │
│ │ ○ Bluetooth                             │ │
│ │ ○ Network (hamlib)                      │ │
│ └─────────────────────────────────────────┘ │
│                                             │
│ ICOM WIFI                                   │
│ ┌─────────────────────────────────────────┐ │
│ │ Radio        IC-705              ▼      │ │
│ │ Address      192.168.1.100               │ │
│ │ Username     ________                    │ │
│ │ Password     ••••••••                    │ │
│ │ CI-V Address 0xA4 (default)      ▼      │ │
│ └─────────────────────────────────────────┘ │
│                                             │
│ AUTO-SYNC                                   │
│ ┌─────────────────────────────────────────┐ │
│ │ Sync frequency to log    [=========]    │ │
│ │ Sync mode to log         [=========]    │ │
│ │ Poll interval            500ms     ▼    │ │
│ └─────────────────────────────────────────┘ │
│                                             │
│        [ Test Connection ]                  │
│        [ Disconnect ]                       │
│                                             │
└─────────────────────────────────────────────┘
```

**Key interactions:**
- Radio model picker: pre-populated list of supported radios with their default CI-V addresses
- Address field: manual entry, or "Scan" button to discover Icom radios via UDP broadcast
- Test Connection: sends a frequency query command, displays result
- Credentials stored in Keychain (per existing app pattern)

#### B. Session Start Integration

When starting a logging session, if a radio connection profile exists:

```
┌─────────────────────────────────────────────┐
│ Start Logging Session                       │
│                                             │
│ My Callsign    K5ABC                        │
│ Mode           SSB                          │
│ Frequency      14.260                       │
│                                             │
│ EQUIPMENT                                   │
│ Radio          IC-705                ▼      │
│ Antenna        EFHW                  ▼      │
│ Power          10W                          │
│                                             │
│ RADIO CONNECTION                            │
│ ┌─────────────────────────────────────────┐ │
│ │ ⊕ Connect to IC-705 via WiFi            │ │
│ │   Sync frequency and mode from radio    │ │
│ └─────────────────────────────────────────┘ │
│                                             │
│        [ Start Session ]                    │
│                                             │
└─────────────────────────────────────────────┘
```

When "Connect to IC-705 via WiFi" is tapped:
- Attempts connection using saved profile
- On success: frequency and mode fields auto-populate from radio
- On failure: shows inline error, session can still start without radio

#### C. Logger View — Connected State

The logger view gains a subtle but always-visible radio status indicator:

```
┌─────────────────────────────────────────────────────────────────┐
│ K5ABC · POTA K-1234                                    ⏸ ■    │
│                                                                 │
│ ┌─ Radio ──────────────────────────────────────────────────┐   │
│ │ 🟢 IC-705    14.062.30 MHz    CW    S7    5W            │   │
│ └──────────────────────────────────────────────────────────┘   │
│                                                                 │
│ ┌─ New QSO ───────────────────────────────────────────────┐   │
│ │ Callsign: [W1AW          ]                               │   │
│ │ Freq:     [14.062]  Mode: [CW]   RST: [599] [599]       │   │
│ │                                                           │   │
│ │                        [ Log QSO ]                        │   │
│ └──────────────────────────────────────────────────────────┘   │
│                                                                 │
│ ┌─ Recent QSOs ───────────────────────────────────────────┐   │
│ │ 14:32  W1AW      14.062  CW   599/599                   │   │
│ │ 14:28  K3ABC     14.260  SSB  59/59                      │   │
│ └──────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

**Radio status bar elements:**
- Connection indicator: 🟢 connected, 🟡 reconnecting, 🔴 disconnected
- Radio model name
- Live frequency (monospaced, updates at poll rate, kHz resolution)
- Current mode badge (capsule style, matches existing mode badges)
- S-meter reading (optional, compact text like "S7" or "S9+10")
- TX power

**Behavior:**
- Frequency/mode in the QSO form auto-update when radio changes band/mode
- "Follow TRX" toggle on the radio bar (inspired by RUMlogNG): tap to pause auto-sync without disconnecting — useful for digital modes or manual override
- When the user manually edits frequency in the form, auto-sync pauses for that field until next QSO
- Tapping the radio bar opens a popover with disconnect option and full details
- When radio is disconnected, the bar disappears — logger works exactly as before
- Smart QSO clearing (inspired by Log4OM): if frequency changes by more than a configurable threshold while a callsign is entered, consider clearing the form (the operator likely moved on)

#### D. Spot Clicking (Future Enhancement)

When a POTA/RBN spot is tapped, if radio is connected:

```
┌──────────────────────────────┐
│ W1AW/P on K-0001             │
│ 14.062 MHz · CW              │
│                               │
│  [ Tune Radio ]  [ Log QSO ] │
└──────────────────────────────┘
```

"Tune Radio" sends a frequency+mode command to the radio. This is a stretch goal.

### Connection State Machine

```
                    ┌──────────┐
         ┌─────────│  Idle    │
         │         └────┬─────┘
         │              │ connect()
         │              ▼
         │         ┌──────────┐
         │         │Connecting│──── timeout ───► Error
         │         └────┬─────┘
         │              │ authenticated
         │              ▼
         │         ┌──────────┐
    disconnect()   │Connected │◄─── reconnected
         │         └────┬─────┘
         │              │ connection lost
         │              ▼
         │         ┌──────────────┐
         │         │Reconnecting  │──── max retries ───► Disconnected
         │         └──────────────┘
         │              ▲
         └──────────────┘
```

Auto-reconnect on connection loss (exponential backoff, max 3 retries, then give up and show disconnected state).

---

## Implementation Plan

### Phase 1 — Icom IC-705 WiFi (MVP)

**Goal:** Connect to IC-705 over WiFi, read frequency/mode, auto-populate QSO entries.

| Component | File | Description |
|-----------|------|-------------|
| **RadioConnectionProfile** | `Models/RadioConnectionProfile.swift` | Connection config: radio model, address, port, credentials, CI-V address |
| **IcomCIVProtocol** | `Services/Radio/IcomCIVProtocol.swift` | CI-V command encoding/decoding, frequency/mode parsing |
| **IcomWiFiTransport** | `Services/Radio/IcomWiFiTransport.swift` | UDP connection, Icom network auth, send/receive CI-V frames |
| **RadioConnectionService** | `Services/Radio/RadioConnectionService.swift` | `@MainActor @Observable` — manages connection state, polls radio, publishes frequency/mode |
| **RadioConnectionActor** | `Services/Radio/RadioConnectionActor.swift` | Background actor for network I/O and protocol parsing |
| **RadioStatusBar** | `Views/Logger/RadioStatusBar.swift` | Live frequency/mode/status display in logger |
| **RadioConnectionSheet** | `Views/Settings/RadioConnectionSheet.swift` | Setup UI for connection profiles |
| **LoggingSessionManager integration** | Modified | Wire radio data into frequency/mode auto-update |

**Estimated scope:** ~8-10 new files, ~400-600 lines of protocol code, ~300 lines of UI.

### Phase 2 — Bluetooth

Add `CoreBluetooth` transport for IC-705 Bluetooth CI-V. Same protocol layer, different transport.

### Phase 3 — Kenwood/Elecraft (SOTAcat)

Add Kenwood text protocol parser. SOTAcat presents a WiFi HTTP interface — add HTTP transport variant.

### Phase 4 — Network Relay (hamlib rigctld)

Add TCP transport for hamlib rigctld protocol. Simple text-based protocol, broadens radio support to 400+ models for users who run a computer alongside their radio.

### Phase 5 — Tune from Spots

When connected, add "Tune Radio" action to spot rows. Sends frequency+mode commands to radio.

### Architecture Notes

- **Actor pattern**: `RadioConnectionActor` runs all network I/O on a background actor (matches existing `QRZClient`, `POTAClient` patterns)
- **MainActor service**: `RadioConnectionService` is `@MainActor @Observable` for UI binding (matches `LoggingSessionManager` pattern)
- **Credentials in Keychain**: Icom WiFi credentials use `KeychainHelper` (existing pattern)
- **No @Query**: Radio state is `@State` / `@Observable` — never persisted as SwiftData
- **Debounced updates**: Frequency changes from radio are debounced (500ms) before updating the QSO form to avoid UI thrashing during tuning
- **Sendable snapshots**: `RadioState` struct is `Sendable`, passed from actor to MainActor

### File Structure

```
CarrierWave/
├── Models/
│   └── RadioConnectionProfile.swift
├── Services/
│   └── Radio/
│       ├── RadioConnectionService.swift      // @MainActor, observable
│       ├── RadioConnectionActor.swift        // Background network I/O
│       ├── Protocols/
│       │   ├── RadioProtocol.swift           // Protocol abstraction
│       │   ├── IcomCIVProtocol.swift          // CI-V encode/decode
│       │   ├── KenwoodProtocol.swift          // Kenwood text protocol
│       │   └── HamlibProtocol.swift           // rigctld text protocol
│       └── Transports/
│           ├── RadioTransport.swift           // Transport abstraction
│           ├── UDPTransport.swift             // Icom WiFi UDP
│           ├── BluetoothTransport.swift       // CoreBluetooth
│           └── TCPTransport.swift             // hamlib rigctld
├── Views/
│   ├── Logger/
│   │   └── RadioStatusBar.swift
│   └── Settings/
│       └── RadioConnectionSheet.swift
```

---

## Open Questions

1. **Icom authentication protocol** — The UDP control port (50001) uses a proprietary auth handshake. kappanhang has reverse-engineered this. Should we port their Go implementation or clean-room from the CI-V reference guide?

2. **Bluetooth transport for IC-705** — Does the IC-705 expose CI-V over BLE (CoreBluetooth compatible) or only classic Bluetooth SPP (requires ExternalAccessory/MFi)? This needs hardware testing.

3. **SOTAcat API** — SOTAcat presents a WiFi hotspot with a web interface. Is there a documented HTTP API, or do we need to scrape/reverse-engineer? The GitHub repo may have protocol docs.

4. **Frequency update UX** — When the user is in the middle of typing a QSO, should radio frequency updates silently update the form, or should they be queued and applied on next QSO? (Recommendation: update silently unless the user has manually edited the frequency field.)

5. **Band change behavior** — When the radio switches bands, should the app start a new logging "segment" or just update the session frequency? (Recommendation: update session frequency, log each QSO with its own frequency.)

6. **Apple Watch** — The Watch app could display radio connection status and frequency. Low priority but worth noting.

---

## Sources

### Apple Documentation & WWDC
- [USBSerialDriverKit Documentation](https://developer.apple.com/documentation/usbserialdriverkit)
- [SerialDriverKit Documentation](https://developer.apple.com/documentation/serialdriverkit)
- [Bring your driver to iPad with DriverKit — WWDC22](https://developer.apple.com/videos/play/wwdc2022/110373/)
- [USBDriverKit Documentation](https://developer.apple.com/documentation/usbdriverkit)
- [DriverKit architecture for USB-C devices — Apple Developer Forums](https://developer.apple.com/forums/thread/747490)
- [iPadOS CDC device support? — Apple Developer Forums](https://developer.apple.com/forums/thread/701434)
- [DriverKit Support on USB-C iPhones — Apple Developer Forums](https://developer.apple.com/forums/thread/737447)

### Ham Radio Apps (iPad)
- [SDR-Control for Icom](https://ham-radio-apps.com/sdr-control-for-icom/)
- [FT-Control for Yaesu](https://ham-radio-apps.com/ft-control-for-yaesu/)
- [TS-Control for Kenwood](https://ham-radio-apps.com/the-ipad-version-of-ts-control-for-kenwood-now-available-on-the-app-store/)
- [K3iNetwork (Elecraft iOS control)](https://apps.apple.com/us/app/k3inetwork/id463639462)

### Icom CI-V Protocol
- [IC-705 CI-V Reference Guide (PDF)](https://www.icomeurope.com/wp-content/uploads/2020/08/IC-705_ENG_CI-V_1_20200721.pdf)
- [Controlling Icom Radios with LAN/WLAN — Spectrum Lab](https://www.qsl.net/dl4yhf/speclab/Icom_radios_with_LAN_or_WLAN.htm)
- [kappanhang — Open source Icom network client](https://github.com/nonoo/kappanhang)
- [wfview — Open source Icom/Kenwood control](https://wfview.org/)

### Elecraft / SOTAcat
- [SOTAcat — WiFi CAT for Elecraft KX radios](https://github.com/SOTAmat/SOTAcat)
- [SotaCAT — Commercial version (Inverted Labs)](https://store.invertedlabs.com/product/sotacat/)
- [Bluetooth CAT for KX2 — SM7IUN](https://sm7iun.se/station/kx2/)

### UX Research & Logging Apps
- [SDR-Control iPad Manual](https://documents.roskosch.de/sdr-control-ipad/)
- [RUMlogNG CAT Settings](https://dl2rum.de/RUMlogNG/docs/en/pages/CAT-Prefs.html)
- [RUMlogNG Transceiver Control](https://dl2rum.de/RUMlogNG/docs/en/pages/TRX-CAT.html)
- [WSJT-X User Guide — Radio Settings](https://wsjt.sourceforge.io/wsjtx-doc/wsjtx-main-2.6.1.html)
- [N1MM+ Interfacing Guide](https://n1mmwp.hamdocs.com/setup/interfacing/)
- [Log4OM User Manual (PDF)](https://www.log4om.com/l4ong/usermanual/Log4OMNG_ENU.pdf)
- [MacLoggerDX Radio Connection](https://www.dogparksoftware.com/MacLoggerDX%20Help/mldxfc_computer.html)
- [Ham Radio Deluxe Rig Control](https://www.hamradiodeluxe.com/features/rigcontrol/)
- [2026 POTA Field Radio Survey](https://qrper.com/2026/02/philips-2026-field-radio-survey-from-the-facebook-pota-group/)
- [POTACAT](https://potacat.com)

### Hamlib & Network CAT
- [Hamlib vs FLRig for CAT Control — VK Ham Radio](https://www.vkhamradio.com/hamlib-or-flrig-or-omnirig-for-transceiver-cat-control/)
- [CAT over TCP/IP — Apache Labs Forum](https://community.apache-labs.com/viewtopic.php?f=22&t=4249)

### DriverKit Community Resources
- [DriverKitUserClientSample (iPadOS)](https://github.com/DanBurkhardt/DriverKitUserClientSample)
