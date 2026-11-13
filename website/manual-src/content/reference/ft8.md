---
title: "FT8 Operating Suite"
description: "Waterfall display, auto-decoding, conversation tracking, and TX control"
weight: 5
showToc: true
---

The FT8 Operating Suite provides a complete digital mode operating environment within Carrier Wave, including waterfall display, automatic decoding, enriched decode information, conversation tracking, and transmit control.

## Overview

FT8 is a weak-signal digital mode designed for marginal propagation conditions. Carrier Wave's FT8 suite brings the full FT8 experience to iOS:

- **Waterfall display** showing signals in the audio passband
- **Auto-decoding** of received FT8 transmissions
- **Enriched decodes** with DXCC, distance, and worked-before information
- **Conversation tracking** state machine for managing QSO flow
- **TX control** for transmitting FT8 via BLE radio connection
- **Auto QSO logging** when exchanges complete

## Audio Setup Wizard

Before using FT8, the audio setup wizard configures your signal path:

1. **Audio source selection** - Device microphone, wired audio input, or BLE radio audio
2. **Level calibration** - Adjusts input gain for optimal decoding
3. **Noise floor measurement** - Establishes baseline for signal detection
4. **Test decode** - Verifies the setup by attempting to decode live signals

The wizard runs once and saves your configuration. Re-run it from Settings -> FT8 if you change your audio setup.

## Waterfall Display

The waterfall shows a scrolling spectrogram of the audio passband:

- **Frequency axis** (horizontal) - 0 to 3000 Hz audio frequency
- **Time axis** (vertical) - Scrolling downward, one line per time slice
- **Color intensity** - Signal strength (blue = weak, green = moderate, yellow/red = strong)
- **Decode markers** - Horizontal lines at frequencies where signals were decoded

### Waterfall Controls

- **Pinch to zoom** the frequency axis
- **Tap a signal** to select it for TX response
- **Brightness control** adjusts the color mapping for different noise conditions

## Auto-Decoding

Carrier Wave decodes FT8 signals automatically during each 15-second cycle:

### Decode Process

1. Audio is captured during the receive window (even-numbered seconds for TX1, odd for TX2)
2. The WSJT-X decoding algorithm processes the audio
3. Decoded messages appear in the decode list

### Decode List

Each decoded message shows:

- **UTC time** of the decode
- **SNR** (signal-to-noise ratio in dB)
- **Frequency offset** (audio frequency in Hz)
- **Message content** (callsigns, grid, signal report, etc.)

### Enriched Decodes

Carrier Wave enriches each decode with additional information:

- **DXCC entity** flag and name for the calling station
- **Distance** from your grid square to the station's grid
- **Worked-before badge** (DUPE, TODAY, PREV) from your QSO history
- **Need badge** if the station matches your [Smart Spot Needs](/reference/smart-needs/) configuration
- **Friend badge** if the station is on your friends list

These badges appear inline with the decode, helping you quickly identify high-value contacts.

## Conversation Tracking

The FT8 conversation tracker uses a state machine to manage the flow of a QSO:

### State Machine

| State | Description | Next States |
|-------|-------------|-------------|
| **Idle** | Not in a QSO | Calling, Responding |
| **Calling** | Sending CQ, waiting for response | In QSO, Idle (timeout) |
| **Responding** | Answering another station's CQ | In QSO, Idle (timeout) |
| **In QSO** | Exchanging reports | Confirming, Idle (timeout) |
| **Confirming** | Sending 73/RR73 | Complete, Idle (timeout) |
| **Complete** | QSO finished | Idle (auto-log) |

### Visual Indicators

- **Color-coded state bar** at the top of the FT8 panel shows the current state
- **Partner callsign** prominently displayed during active QSO
- **Exchange progress** shows which messages have been sent/received (CQ -> grid -> report -> RR73)
- **Timeout warning** flashes when the QSO is at risk of timing out

### Automatic Sequencing

The conversation tracker automatically selects the next message to send based on the current state and received messages:

- Received a CQ? Respond with your callsign and grid
- Received a signal report? Send your report
- Received RR73? Send 73 and log the QSO

You can override automatic sequencing at any time by selecting a different message.

### Adaptive Sequencing

Carrier Wave adapts the sequencing based on QSO conditions:

- **Weak signals** - Automatically retransmits if no response within expected window
- **Partial decodes** - Flags when a decode is incomplete and may need manual intervention
- **Multi-path** - Handles cases where multiple stations respond to your CQ

## TX Control

### Armed / Transmitting / Halted States

TX control uses a three-state system:

- **Halted** (red) - TX is disabled; receive only
- **Armed** (yellow) - TX is enabled but waiting for the correct time slot
- **Transmitting** (green) - Actively transmitting during the current cycle

### Enabling TX

1. Tap the **TX** button to arm transmit
2. Carrier Wave waits for the next appropriate time slot
3. The selected message is transmitted
4. After transmission, the system returns to Armed (waiting for the next cycle)

### Halting TX

Tap the **TX** button while Armed or Transmitting to immediately halt transmission. The current cycle completes but no further transmissions are sent.

### CQ Modifier Menu

When calling CQ, a modifier menu lets you customize your CQ message:

- **Standard CQ** - `CQ [your call] [your grid]`
- **CQ DX** - Targets DX stations only
- **CQ POTA** - Includes POTA reference
- **CQ [direction]** - CQ NA, CQ EU, CQ AS, etc.
- **CQ [contest]** - Contest-specific CQ messages

Tap and hold the CQ button to access the modifier menu.

## Band & Segment Defaults

FT8 has standard frequencies on each band. Carrier Wave pre-selects the correct audio segment:

| Band | Dial Frequency | Audio Range |
|------|---------------|-------------|
| 160m | 1.840 MHz | 0-3000 Hz |
| 80m | 3.573 MHz | 0-3000 Hz |
| 40m | 7.074 MHz | 0-3000 Hz |
| 30m | 10.136 MHz | 0-3000 Hz |
| 20m | 14.074 MHz | 0-3000 Hz |
| 17m | 18.100 MHz | 0-3000 Hz |
| 15m | 21.074 MHz | 0-3000 Hz |
| 12m | 24.915 MHz | 0-3000 Hz |
| 10m | 28.074 MHz | 0-3000 Hz |
| 6m | 50.313 MHz | 0-3000 Hz |

When you change bands, the dial frequency updates automatically.

## Cycle Progress Indicator

A progress bar at the top of the FT8 panel shows the current position within the 15-second FT8 cycle:

- **Blue fill** during receive windows
- **Green fill** during your transmit window
- **Time remaining** displayed in seconds
- **Cycle number** (even/odd) indicator

This helps you anticipate when decodes will appear and when your next transmission will start.

## Auto QSO Logging

When a QSO completes (both sides have exchanged reports and confirmations):

1. Carrier Wave auto-populates a QSO record with:
   - Partner callsign
   - Frequency and mode (FT8)
   - Signal reports (sent and received)
   - Grid square (from exchange)
   - UTC time
2. The QSO is **logged automatically** to your session
3. A toast notification confirms the log
4. The conversation tracker resets to Idle

If auto-logging is disabled in Settings -> FT8, a confirmation prompt appears instead.

## Tips for FT8 Operation

### Audio Level

- Keep audio levels moderate; FT8 decoding is sensitive to clipping
- Use the level meter in the audio setup wizard to verify
- Too loud causes decode failures; too quiet reduces decode range

### Timing

- FT8 requires accurate time synchronization (within +/-1 second)
- Carrier Wave uses the device's NTP-synced clock
- If decodes are failing, check that your device time is correct

### Signal Selection

- Tap signals on the waterfall to respond to them
- Stronger signals (brighter colors) are more likely to complete QSOs
- Avoid responding to signals that already have multiple callers

## See Also

- [Logger](/reference/logger/) - Session management and QSO entry
- [BLE Radio Control](/reference/radio-control/) - Frequency sync with your radio
- [Smart Spot Needs](/reference/smart-needs/) - Need badges on FT8 decodes
- [Export & Sharing](/reference/export/) - Export FT8 QSOs
