# WebSDR Session Recording — Exploration

**Date:** 2026-02-13
**Status:** Exploration
**Type:** Feature Exploration

## Concept

Record audio from a nearby WebSDR during a logging session so the user has audio of their entire activation. The recording would be tied to the LoggingSession and available for playback later from the activation detail view.

**User value:** Activators (especially POTA/SOTA) could have an audio record of their session without any additional hardware. A WebSDR near them picks up their signal and the app records the stream.

## WebSDR Landscape

Three main platforms run publicly accessible WebSDRs:

| Platform | Count | Protocol | Best API | Audio Format |
|----------|-------|----------|----------|--------------|
| **KiwiSDR** | 500+ | WebSocket | Yes (binary + JSON commands) | PCM / Opus |
| **WebSDR** (websdr.org) | ~150 | WebSocket + HTTP | Limited (no official API) | Browser-dependent |
| **OpenWebRX / OpenWebRX+** | 200+ | WebSocket | Moderate | Compressed audio |

**Recommendation: Target KiwiSDR first.** It has the largest directory, the best-documented protocol (via kiwiclient reference implementation), and an existing SwiftUI iOS app (Echo) that demonstrates feasibility.

## KiwiSDR Protocol Details

### Connection
- WebSocket to `ws://[host]:8073/[session]/SND`
- Must send keep-alive every 60 seconds or server disconnects
- Operators configure inactivity timeouts (30m to 8h+) and 24-hour per-IP limits
- Password parameter (`pwd=`) can bypass timeouts if operator provides one

### Tuning
- JSON-like text commands over WebSocket to set frequency (kHz) and mode (am/lsb/usb/cw/nbfm/etc.)
- Bandwidth configurable
- Changes take effect immediately

### Audio Streaming
- Binary frames on the WebSocket carry audio samples
- Supports PCM and **Opus** compression
- Opus reduces bandwidth from ~2 Mbit/s to ~200 kbit/s per client
- Continuous stream as long as connection is alive

### Concurrent User Limits
- Typically 2–3 simultaneous users per KiwiSDR (FPGA-limited)
- "Camper" mode lets additional listeners piggyback on an existing user's audio
- Busy receivers may reject connections

### Reference Implementations
- **kiwiclient** (Python): `kiwirecorder.py` is the canonical recording client
- **Echo** (SwiftUI): Native iOS KiwiSDR/OpenWebRX client, 100% SwiftUI, low battery impact
- **kiwi_sdr** (Dart): Cross-platform package for KiwiSDR interaction

## Discovery: Finding Nearby WebSDRs

### KiwiSDR Directory
- `kiwisdr.com/public/` — sortable list of 500+ receivers with location data
- No official JSON API, but the page data can be scraped or reverse-engineered
- `map.kiwisdr.com` shows geographic distribution
- `rx-tx.info` provides a unified preview across KiwiSDR/WebSDR/OpenWebRX

### OpenWebRX Directory
- `receiverbook.de` — free directory with location data
- OpenWebRX instances register with ReceiverBook for peer discovery

### Discovery Strategy
1. Scrape/cache the KiwiSDR public directory (receivers + lat/lon + frequency coverage)
2. Convert user's Maidenhead grid to lat/lon (already have `MaidenheadConverter`)
3. Filter by distance and band coverage
4. Sort by proximity, present top 3–5 options
5. Cache directory locally, refresh daily (similar to `POTAParksCache` pattern)

## Architecture Proposal

### New Files

| File | Purpose |
|------|---------|
| `Services/WebSDR/KiwiSDRClient.swift` | Actor — WebSocket connection, tuning commands, audio stream |
| `Services/WebSDR/WebSDRRecorder.swift` | Actor — receives audio stream, writes to compressed file |
| `Services/WebSDR/WebSDRDirectory.swift` | Actor — fetches/caches KiwiSDR directory, proximity search |
| `Services/WebSDR/WebSDRSession.swift` | @MainActor @Observable — coordinates connection + recording lifecycle |
| `Models/WebSDRRecording.swift` | SwiftData model — recording metadata (file URL, duration, session ID) |
| `Views/Logger/WebSDRPanelView.swift` | Logger panel — connection status, recording controls, level meter |
| `Views/Logger/WebSDRPickerSheet.swift` | Nearby WebSDR selection with distance/status |
| `Views/POTAActivations/RecordingPlaybackView.swift` | Playback controls on activation detail |

### Model Changes

**LoggingSession** — add optional `webSDRRecordingId: UUID?` to link a recording.

**WebSDRRecording** (new SwiftData model):
```swift
@Model
final class WebSDRRecording {
    var id: UUID
    var loggingSessionId: UUID
    var kiwisdrHost: String
    var kiwisdrName: String
    var startedAt: Date
    var endedAt: Date?
    var frequencyKHz: Double
    var mode: String
    var fileURL: String  // relative path in app documents
    var fileSizeBytes: Int64
    var durationSeconds: Double
}
```

### Integration Points

**LoggingSessionManager** — start/stop/pause/resume recording alongside other session services:
```
startSession() → start WebSDR connection + recording
endSession() → stop recording, save metadata
pauseSession() → pause recording (keep connection alive)
resumeSession() → resume recording
updateFrequency() → retune WebSDR to new frequency
updateMode() → retune WebSDR to new mode
```

**SessionStartSheet** — add optional "Record from WebSDR" toggle with nearby SDR picker.

**LoggerView** — add `WEBSDR` command (like existing SPOT, RBN, SOLAR, WEATHER, MAP commands) to show the WebSDR panel with connection status and recording indicator.

**POTAActivationDetailView** — show recording playback if `webSDRRecordingId` exists.

### Audio Pipeline

```
KiwiSDR WebSocket → Opus frames → Decode → Write to .m4a/.caf file
                                        ↗
                              (optional) Level meter for UI
```

- Use `AVAudioFile` to write compressed audio (AAC in .m4a container)
- Keep file size manageable: ~3.5 MB/hour at 64kbps mono
- A 2-hour POTA activation ≈ 7 MB — very reasonable
- Store in app's Documents directory, manage cleanup for old recordings

### Background Considerations

- **Audio background mode** — app already uses `.playAndRecord` for CW transcription
- **Network background** — URLSession background tasks or WebSocket keep-alive
- **Battery** — Opus decoding is lightweight; Echo app demonstrates low battery impact
- **Screen lock** — need to maintain WebSocket during screen lock (background task or audio session keeps app alive)

## Logger Command Integration

Add `WEBSDR` to the existing `LoggerCommand` enum alongside SPOT, RBN, SOLAR, WEATHER, MAP:

```swift
case websdr  // "WEBSDR" — show WebSDR recording panel
```

The panel would show:
- Connection status (disconnected / connecting / connected / recording)
- Current WebSDR name and location
- Signal level meter (from decoded audio)
- Recording duration
- Button to change WebSDR or disconnect

## UX Flow

### Starting a Session with WebSDR Recording
1. User opens Session Start Sheet
2. Toggle "Record from WebSDR" (off by default)
3. If enabled, app shows nearby KiwiSDRs based on user's grid
4. User picks one (or app auto-selects closest available)
5. Session starts → WebSDR connects, tunes to session frequency/mode, begins recording

### During Session
- Recording indicator in session header (red dot + duration)
- `WEBSDR` command shows panel with status and level meter
- Frequency/mode changes automatically retune the WebSDR
- If WebSDR disconnects, auto-reconnect with exponential backoff
- If reconnection fails after N attempts, notify user via toast

### After Session
- Recording appears in activation detail view
- Playback with scrubber, showing QSO timestamps as markers on the timeline
- Option to share/export the audio file
- Option to delete recording to free space

## Storage & Cleanup

- Store recordings in `Documents/WebSDRRecordings/[sessionId].m4a`
- Show total recording storage in Settings → External Data (like POTA parks cache)
- Auto-cleanup: delete recordings older than N days (configurable, default 90)
- Manual delete from activation detail

## Open Questions

1. **Latency** — WebSDR audio has 1–3 second latency. QSO timestamp markers on playback need to account for this offset. Should we estimate and store the offset, or let the user calibrate?

2. **Availability** — What happens in remote POTA locations with poor cell service? The feature should degrade gracefully (show "No connection" and continue logging normally).

3. **Operator etiquette** — Should we limit session duration or add a disclaimer about being a good citizen of shared KiwiSDR resources? Some operators set strict time limits.

4. **Multi-band** — If the user QSYs to a band the selected KiwiSDR doesn't cover, should we auto-switch to a different SDR, or just stop recording that segment?

5. **Privacy** — Recording other operators' transmissions. This is publicly received RF and legal, but worth considering user-facing language.

6. **Existing Echo app** — The Echo SwiftUI app is open source. Can we use it as reference for the KiwiSDR WebSocket protocol implementation, or would it be better to port from kiwiclient (Python)?

## Complexity Estimate

| Component | Effort | Notes |
|-----------|--------|-------|
| KiwiSDRClient (WebSocket + commands) | Medium | Port from kiwiclient, straightforward WebSocket |
| WebSDRRecorder (audio → file) | Medium | AVAudioFile + Opus decoding |
| WebSDRDirectory (discovery + cache) | Low | Similar pattern to POTAParksCache |
| WebSDRSession (coordinator) | Medium | Lifecycle management, follows existing patterns |
| Model + migrations | Low | One new SwiftData model, one field on LoggingSession |
| Logger panel UI | Low-Medium | Similar to existing RBN/Solar/Weather panels |
| Picker sheet | Low | Similar to ParkPickerSheet |
| Playback UI | Medium | AVAudioPlayer + timeline with QSO markers |
| Integration with session lifecycle | Medium | 6 integration points in LoggingSessionManager |

**Overall: Medium-Large feature.** The core WebSocket + audio pipeline is the main technical risk. The rest follows well-established patterns in the codebase.

## Suggested Implementation Order

1. **Phase 1 — KiwiSDRClient**: WebSocket connection, tuning, audio stream (standalone, testable)
2. **Phase 2 — WebSDRDirectory**: Discovery, caching, proximity search
3. **Phase 3 — WebSDRRecorder**: Audio stream → compressed file
4. **Phase 4 — WebSDRSession**: Coordinate client + recorder, integrate with LoggingSessionManager
5. **Phase 5 — UI**: Logger command, panel, picker sheet, recording indicator
6. **Phase 6 — Playback**: Post-session playback with QSO timeline markers
