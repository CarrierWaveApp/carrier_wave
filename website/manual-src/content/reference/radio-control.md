---
title: "Radio CAT Control"
description: "Connect to your amateur radio for automatic frequency, mode, and TX state sync via BLE, WiFi, or LAN"
weight: 6
showToc: true
---

{{< callout "warning" "Experimental Feature (Alpha)" >}}
Radio CAT Control is an experimental feature that requires compatible hardware and may have edge cases. Enable it under **Settings > Experiments** as **Radio CAT Control**. Once enabled, it remains available in the experiments list.
{{< /callout >}}

Radio Control lets Carrier Wave read frequency, mode, and TX state directly from a connected radio, keeping the logger in sync automatically. It uses industry-standard {{< term "CAT" >}} (Computer Aided Transceiver) protocols to communicate with your transceiver over BLE, WiFi, or LAN.

The feature is always available under **Settings > Experiments** as **Radio CAT Control**.

## Supported Radios

### Icom (CI-V Protocol)

| Radio | CI-V Address | Connection | Notes |
|-------|-------------|------------|-------|
| IC-705 | 0xA4 | WiFi (RS-BA1), Serial, BLE | 19,200 baud. WiFi is the most polished setup path. |
| IC-7300 | 0x94 | Serial, BLE | |
| IC-7610 | 0x98 | Serial, BLE, WiFi variant | |
| Xiegu X6100 | 0x70 | Serial, BLE | CI-V compatible |
| Xiegu G90 | 0x70 | Serial, BLE | CI-V compatible |

### Yaesu (Yaesu CAT Protocol)

| Radio | Connection | Notes |
|-------|------------|-------|
| FTDX10 | Serial, SCU-LAN10 | 38,400 baud |
| FT-991A | Serial | 38,400 baud |
| FT-710 | Serial, SCU-LAN10 | 38,400 baud |
| FTDX101D | Serial, SCU-LAN10 | 38,400 baud |
| FTDX101MP | SCU-LAN10 | 38,400 baud |

The SCU-LAN10 is Yaesu's UDP/IP network adapter for serial-based radios.

### Kenwood

| Radio | Baud Rate |
|-------|-----------|
| TS-890S | 115,200 |
| TS-590SG | 9,600 |

### Elecraft

| Radio | Baud Rate |
|-------|-----------|
| K3 / K3S | 38,400 |
| K4 | 115,200 |

### FlexRadio (SmartSDR Protocol)

FLEX-6400, FLEX-6400M, FLEX-6600, FLEX-6600M, FLEX-6700

FlexRadio uses the SmartSDR protocol over TCP/IP rather than a serial CAT protocol. Updates are push-based — no polling needed, so updates are instant.

## Connection Methods

Carrier Wave supports three transport types for connecting to your radio.

### BLE (Bluetooth Low Energy)

BLE connects through a Nordic UART BLE serial bridge device. It works with any serial-based radio via an external BLE-serial adapter.

- Tap **Scan** to discover nearby BLE devices, select yours, and tap **Connect**
- Fast polling (~200 ms) provides the best real-time responsiveness
- Works with all supported protocols (CI-V, Kenwood, Yaesu, Elecraft)

### WiFi (Icom RS-BA1)

{{< callout "note" "IC-705 and IC-7610 Only" >}}
WiFi connection is available only for the IC-705 and IC-7610, which have built-in WiFi via the RS-BA1 protocol.
{{< /callout >}}

Connects over UDP to the radio's built-in WiFi. Two modes are available:

- **Access Point mode** — The radio creates its own WiFi network. The default IP is `192.168.59.1`.
- **Station mode** — The radio joins your existing WiFi network. Enter the radio's IP address manually.

WiFi requires a username and password configured on the radio. Polling is slower (~1 second per parameter) due to radio firmware limitations — this is not an app limitation.

The app handles session keepalive and automatic re-authentication if suspended and resumed.

### FlexRadio (SmartSDR)

**Local (LAN):** Enter the radio's IP address and port (default TCP 4992). Carrier Wave uses VITA-49 discovery to find radios on your local network automatically.

**SmartLink (WAN/Remote):** Sign in with your FlexRadio SmartLink account (Auth0). The app discovers your radio through the SmartLink cloud broker and establishes a direct TLS tunnel, allowing remote operation from anywhere.

- Push-based updates — no polling needed, changes are instant
- Configurable slice index for multi-slice radios

## What Syncs from the Radio

| Data | Description |
|------|-------------|
| **Frequency** | Current VFO frequency in MHz, updated continuously |
| **Mode** | Operating mode (SSB, CW, AM, FM, RTTY, etc.) |
| **TX State** | Whether the radio is currently transmitting |
| **RIT/XIT** | Receive/Transmit Incremental Tuning offset (where supported by the radio) |

These values automatically populate the logging fields so the user doesn't need to manually enter frequency or mode for each {{< term "QSO" >}}.

## Setup: IC-705 WiFi (Step by Step)

{{< callout "tip" "Recommended Starting Point" >}}
The IC-705 WiFi experience is the most polished connection path. If you have an IC-705, start here.
{{< /callout >}}

1. **On the IC-705:** Enable WiFi in **Access Point** mode (or **Station** mode on your local network).
2. **On the IC-705:** Set a username and password under **SET > Network > Remote Settings**.
3. **On your iPhone/iPad:** Connect to the IC-705's WiFi network (if using AP mode).
4. **In Carrier Wave:** Go to **Settings > Radio Control**.
5. Select the **WiFi** tab.
6. Choose **Access Point** mode (IP auto-fills to `192.168.59.1`) or **Station** mode (enter the radio's IP).
7. Enter the username and password you set on the radio.
8. Tap **Connect**.
9. The connection status indicator shows when connected. Frequency and mode will begin syncing automatically.

{{< callout "tip" "WiFi Update Rate" >}}
WiFi polling is about 1 update per second. This is a radio firmware limitation, not an app limitation.
{{< /callout >}}

## Setup: BLE (General)

1. Ensure your BLE serial adapter is powered on and paired with your radio.
2. In Carrier Wave, go to **Settings > Radio Control**.
3. Select the **BLE** tab.
4. Tap **Scan** — nearby BLE devices appear with signal strength indicators.
5. Select your adapter and tap **Connect**.
6. Under **Advanced**, verify the protocol matches your radio (CI-V for Icom, Kenwood, Yaesu, or Elecraft).
7. For Icom radios, confirm the CI-V address matches your radio's setting (e.g., `0xA4` for IC-705).

## Setup: FlexRadio

### Local (LAN)

1. Ensure your FlexRadio and iOS device are on the same network.
2. Go to **Settings > Radio Control**, select the **Flex** tab.
3. Discovered radios appear automatically via VITA-49 broadcast. Or enter the IP and port manually.
4. Select the desired slice index.
5. Tap **Connect**.

### SmartLink (Remote)

1. Select the **Flex** tab.
2. Sign in with your FlexRadio SmartLink credentials.
3. Your registered radios appear — select one.
4. The app establishes a secure tunnel through the SmartLink cloud broker.
5. Once connected, operation is identical to local.

## Advanced Settings

- **Protocol:** Auto-detected for WiFi (always CI-V). For BLE/serial, select CI-V, Kenwood, Yaesu, or Elecraft to match your radio.
- **CI-V Address:** Hexadecimal address of your Icom radio. Defaults to `0xA4` (IC-705). Change if you've customized the address on your radio or use a different model.
- **Baud Rate:** Must match the radio's serial port setting. Common defaults: IC-705 = 19,200; TS-890S = 115,200; K4 = 115,200.

## Troubleshooting

**WiFi won't connect:**
Verify you're on the radio's WiFi network (AP mode) or same LAN (Station mode). Check the username and password. The IC-705 only allows one remote connection at a time — close RS-BA1 on any other device first.

**Frequency not updating:**
Check that the CI-V address matches your radio's setting. For WiFi, expect ~1 second update rate. For BLE, ensure the serial adapter is powered on.

**Connection drops after phone sleeps:**
The app automatically re-authenticates on resume for WiFi connections. If it fails, tap **Disconnect** then **Connect** again.

**FlexRadio not discovered:**
Ensure the radio and device are on the same subnet. Try entering the IP address manually.

## CW Memory Keyer

When a CW Bridge is connected and the radio is in CW mode, a **keyer button row** appears above the command row in the Logger. This provides one-tap CW message sending through the bridge.

### Message Slots

Eight configurable message slots are available, each holding a CW message template. Configure messages at **Settings > Radio > CW Messages**.

### Template Variables

Messages support template variables that are expanded at send time:

| Variable | Expands To |
|----------|-----------|
| `{MYCALL}` | Your operating callsign |
| `{MYNAME}` | Your first name (from your operator profile) |
| `{CALL}` | The callsign currently entered in the Logger |
| `{HISCALL}` | Same as `{CALL}` (alias) |
| `{HISSTATE}` | Other station's state/province (from QRZ lookup) |
| `{NR}` | Current serial number |
| `{RST}` | Signal report to send |
| `{NAME}` | Operator name (from QRZ lookup) |
| `{EXCH}` | Contest exchange |
| `{FREQ}` | Current radio frequency |

Messages also support prosign notation (e.g., `<BT>`, `<SK>`, `<AR>`).

### Editing Messages

- **Settings page:** Full editor at **Settings > Radio > CW Messages** with tappable macro pills and live preview
- **Inline editing:** Long-press any keyer button in the Logger for quick in-place editing

### Speed Control

WPM (words per minute) is adjustable from the keyer row. The bridge firmware handles CW text chunking, buffer polling, and per-radio CAT speed commands.

### Supported Radios

The keyer works with all bridge-connected radios. Per-radio CAT encoding is handled automatically:

- **Kenwood:** KY, TB, KS commands
- **Icom (CI-V):** 0x17, 0x1C, 0x14 0C commands

## BLE Bridge Protocol

The BLE bridge now uses **protobuf serialization** (CWBP v2) instead of the previous custom binary framing. This provides more reliable communication and easier extensibility. The protocol version is negotiated automatically on connection.

## CW Sweep (macOS Companion)

CW Sweep, the macOS companion app, has its own radio control implementation with serial port support and a command log for debugging CAT protocol communication.

## Remote (iOS as Sweep's Control Surface)

When CW Sweep is running on the same LAN, the iOS Remote tab turns the phone into a control surface for the Mac-connected radio. The pane is laid out as a dashboard rather than a settings form:

- **Hero VFO display** — tabular monospaced digits, MHz.kHz at 56pt with a smaller Hz triplet
- **TX/RX dot LED** next to the connected Sweep name
- **Audio strip** — chunky speaker button + thick volume slider that controls Sweep's RX audio over the LAN
- **Inline tune entry** — type a frequency to retune the radio
- **Capsule chip strip** under the nav title selects between Radio, Scope, Waterfall, Spots, and CW (replaces the old nested tabs)

### Remote Audio

The new "Use Opus for remote audio" toggle in CW Sweep's Remote Settings forwards the radio's RX audio to the iOS device. When the speaker on the iOS Radio pane is turned on:

- **Default (off)** — Sweep streams raw PCM16 LE @ 16 kHz mono (~256 kbps)
- **Opus on** — Sweep encodes to Opus before sending (~24 kbps), useful on cell uplinks

Sweep skips encoding when no client is listening, so leaving the toggle off has no cost.

### Tap Straight Key

The Radio sub-tab includes a **straight-key pad**: tap for a dit, hold past 180 ms for a dah. Each gesture fires a single CW element through the keyer. The remote keyer path is transport-agnostic — it routes through CW Bridge → WinKeyer → the radio's CAT keyer (Icom CI-V, Kenwood/Elecraft/Yaesu KY) automatically.

True press-and-hold straight keying needs raw key-line firmware on the CW Bridge and is tracked separately.

## See Also

- [Logger](/reference/logger/) — Session management and frequency entry
- [FT8 Operating Suite](/reference/ft8/) — FT8 with radio control
- [Settings & Services](/reference/settings/) — Radio control configuration
