# SCU-LAN10 Integration in CW Sweep

**Date**: 2026-03-26
**Goal**: Add SCU-LAN10 support to CW Sweep with live waterfall display and full CAT radio control in the hunter logger window.

## Context

The SCU-LAN10 protocol has been fully reverse-engineered (see `docs/scu-lan10-protocol.md`). A working Python proof-of-concept (`tools/scu_lan10_test.py`) successfully connects, authenticates, and receives decrypted scope data at 25 lines/sec.

CW Sweep already has:
- `RadioTransport` protocol with serial and Flex (TCP) implementations
- `RadioProtocolHandler` for CAT command encoding/decoding (including Yaesu)
- `RadioManager`/`RadioSession` for session lifecycle
- `FT8WaterfallView` in the iOS app as a Canvas-based waterfall reference
- `BandMapView` with Canvas zoom/pan patterns

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    RadioManager                          │
│  createTransportAndHandler(for:) adds .scuLan10 case    │
└──────────┬──────────────────────────────────┬────────────┘
           │                                  │
    ┌──────▼──────┐                   ┌───────▼───────┐
    │ RadioSession │                   │ RadioSession  │
    │ (serial CAT) │                   │ (SCU-LAN10)   │
    └─────────────┘                   └───────┬───────┘
                                              │
                              ┌───────────────▼───────────────┐
                              │     SCULAN10Transport          │
                              │     (actor, RadioTransport)    │
                              │                               │
                              │  ┌─────────┐  ┌──────────┐   │
                              │  │ Control  │  │   CAT    │   │
                              │  │ UDP sock │  │ UDP sock │   │
                              │  └─────────┘  └──────────┘   │
                              │  ┌─────────┐  ┌──────────┐   │
                              │  │  Audio   │  │  Scope   │   │
                              │  │ UDP sock │  │ UDP sock │   │
                              │  └─────────┘  └──────────┘   │
                              └───────────────┬───────────────┘
                                              │
                                    ┌─────────▼─────────┐
                                    │ ScopeDataStream    │
                                    │ AsyncStream<[UInt8]│
                                    │ 4096 bins, 25/sec  │
                                    └─────────┬─────────┘
                                              │
                                    ┌─────────▼─────────┐
                                    │ WaterfallData      │
                                    │ @Observable        │
                                    │ magnitudes: [[F]]  │
                                    └─────────┬─────────┘
                                              │
                                    ┌─────────▼─────────┐
                                    │ WaterfallView      │
                                    │ Canvas + gestures  │
                                    └───────────────────┘
```

## Implementation Steps

### Step 1: SCU-LAN10 Transport (new file)

**File**: `CWSweep/CWSweep/Services/Radio/SCULAN10Transport.swift`

New actor conforming to `RadioTransport`. Manages all 4 UDP sockets (NWConnection with UDP). Handles:
- Connection establishment (auth sequence from protocol doc)
- Session ID extraction from server response
- Port initialization handshake
- Scope data decryption via precomputed `gTable`
- Keepalive loop (1/sec on all ports)
- CAT command send/receive bridged to `receivedData: AsyncStream<Data>`
- Separate `scopeData: AsyncStream<Data>` for spectrum data (not mixed into CAT stream)

Uses `NWConnection` UDP (following `FlexRadioTransport` patterns) — not raw POSIX sockets.

Connection parameters stored in `RadioProfile`: host, port, username, password.

### Step 2: Protocol Handler (new file)

**File**: `CWSweep/CWSweep/Services/Radio/SCULAN10ProtocolHandler.swift`

Conforms to `RadioProtocolHandler`. Since SCU-LAN10 tunnels standard Yaesu CAT commands through its encryption layer, this is thin:
- Delegates to the existing `YaesuProtocolHandler` for CAT command encoding/decoding
- Strips/adds the `[session_id, 0, 0, 0, flags...]` prefix before passing to the Yaesu handler
- Reports `radioId` based on `ID;` response (0670=FTDX10, 0681=FTDX101D, 0682=FTDX101MP)

### Step 3: Radio Profile Updates

**File**: `CWSweep/CWSweep/Models/RadioProfile.swift`

- Add `.scuLan10` to `RadioProtocolType` enum
- Add `isNetworkRadio` handling (returns true)
- Add `host`, `port`, `username`, `password` fields (or a nested `NetworkConfig` struct)
- Add FTDX101MP, FTDX101D, FTDX10, FT-710 entries to `RadioModel.knownModels` with `.scuLan10` protocol type
- UI: Connection settings view needs host/port/user/pass fields for SCU-LAN10 radios

### Step 4: RadioManager Integration

**File**: `CWSweep/CWSweep/Services/Radio/RadioManager.swift`

- Add `.scuLan10` case to `createTransportAndHandler(for:)` factory method
- Create `SCULAN10Transport` with network config from the profile
- Wire `scopeData` stream to a new published property for waterfall consumers

### Step 5: Waterfall Data Model (new file)

**File**: `CWSweep/CWSweep/Services/Radio/SCULAN10WaterfallData.swift`

`@MainActor @Observable` class. Adapts the raw 4096-bin scope data into a renderable format:
- Receives `AsyncStream<Data>` of decrypted spectrum lines from the transport
- Maintains a rolling buffer of N lines (e.g., 200 for visible waterfall height)
- Normalizes amplitude values to 0.0-1.0 Float (inverted: low byte value = strong signal = 1.0)
- Trims inactive bins (trailing zeros) to the active span
- Publishes `magnitudes: [[Float]]` and `activeBinCount: Int`
- Tracks center frequency and span from CAT `FA;` and `SS;` responses

No FFT needed — the SCU-LAN10 delivers pre-computed spectrum data.

### Step 6: Waterfall View (new file)

**File**: `CWSweep/CWSweep/Views/Spots/WaterfallView.swift`

SwiftUI `Canvas` view following the `FT8WaterfallView` pattern:
- Renders `magnitudes` as a color-mapped spectrogram
- Color palette: match the radio's scope colors (configurable, default blue/red/white gradient)
- Frequency axis with tick labels (derived from center frequency + span)
- Current frequency marker (green line) from `RadioManager.frequency`
- Click-to-tune: clicking a point on the waterfall tunes the radio via CAT `FA` command
- Horizontal zoom/pan with `MagnifyGesture` / `DragGesture` (reuse `BandMapView` patterns)
- Signal strength indicator on hover

### Step 7: Hunter Layout Integration

**File**: `CWSweep/CWSweep/Views/Roles/HunterLayout.swift`

Add waterfall pane to the hunter layout. Two options:

**Option A**: Replace/augment the BandMapView area
```swift
VSplitView {
    // Top: entry + log/bandmap
    ParsedEntryView()
    HSplitView {
        QSOLogTableView()
        VSplitView {
            BandMapView()     // existing
            WaterfallView()   // new - below band map
        }
    }
    // Bottom: spots
    SpotListView()
}
```

**Option B**: Tabbed band map / waterfall
```swift
HSplitView {
    QSOLogTableView()
    TabView {
        BandMapView().tabItem { Text("Band Map") }
        WaterfallView().tabItem { Text("Waterfall") }
    }
}
```

Recommend **Option A** — waterfall and band map are complementary, not alternatives. The waterfall shows signal activity, the band map shows spotted callsigns. Both visible simultaneously is most useful.

The waterfall only appears when `RadioManager` has an active SCU-LAN10 connection with scope data.

### Step 8: Connection Settings UI

**File**: `CWSweep/CWSweep/Views/Settings/RadioSettingsView.swift` (or similar)

Add SCU-LAN10 configuration fields when the selected radio model uses `.scuLan10` protocol:
- Host (text field, supports hostname or IP)
- Control Port (default 50000, range 49990-50009)
- Username (text field)
- Password (secure field)
- Connection test button
- Audio quality picker (PCM 16kHz default)

Credentials stored in Keychain (following project conventions — never SwiftData).

## File Summary

| File | Action | Est. Lines |
|------|--------|------------|
| `Services/Radio/SCULAN10Transport.swift` | New | ~350 |
| `Services/Radio/SCULAN10ProtocolHandler.swift` | New | ~80 |
| `Services/Radio/SCULAN10WaterfallData.swift` | New | ~120 |
| `Views/Spots/WaterfallView.swift` | New | ~200 |
| `Models/RadioProfile.swift` | Edit | +30 |
| `Services/Radio/RadioManager.swift` | Edit | +20 |
| `Views/Roles/HunterLayout.swift` | Edit | +15 |
| `Views/Settings/RadioSettingsView.swift` | Edit | +60 |

## Dependencies

- `Network.framework` (already used by CW Sweep)
- `CarrierWaveCore` (for any shared CAT parsing)
- No new SPM packages required

## Testing Strategy

1. **Unit tests**: `gTable` precomputation, packet decryption, auth packet construction
2. **Integration test**: Use the Python test script as a reference for expected behavior
3. **Manual test**: Connect to live SCU-LAN10, verify waterfall renders, click-to-tune works

## Open Questions

1. **Header generation**: The 8-byte payload header (bytes 0-4, 7) is partially understood. Init keepalives and auth use captured headers. A full formula for generating headers dynamically would eliminate the need for captured header constants. Not blocking — captured headers work reliably.

2. **Audio streaming**: The audio port is initialized but not consumed. Future work could add remote audio monitoring. Not in scope for this plan.

3. **Multiple radio support**: The SCU-LAN10 supports FTDX101MP/D, FTDX10, and FT-710. Scope data format appears identical across all; CAT commands vary slightly. The `ID;` response auto-detects the radio model.

4. **Scope settings**: The `SS` CAT command controls span (1kHz-1MHz), speed (SLOW1-FAST3), display mode (CENTER/CURSOR/FIX), colors, etc. These should be exposed in the waterfall UI eventually but aren't required for the initial implementation.
