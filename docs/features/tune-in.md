# Tune In — Listen to Activations via WebSDR

## Overview

"Tune In" lets users tap on any spot (POTA, SOTA, WWFF, RBN) and immediately start listening to the activation through a KiwiSDR receiver. The app auto-selects a receiver likely to hear the activator, streams audio, provides live CW transcription, and records everything for later playback.

### What Already Exists

The infrastructure is fully built — this feature is about **UX integration**, not plumbing:

| Component | Status | Location |
|-----------|--------|----------|
| KiwiSDR WebSocket client | Built | `Services/WebSDR/KiwiSDRClient.swift` |
| IMA ADPCM audio decoder | Built | `KiwiSDRADPCM.swift` |
| Live audio playback engine | Built | `KiwiSDRAudioEngine.swift` (ring buffer, adaptive rate) |
| KiwiSDR directory + search | Built | `WebSDRDirectory.swift` |
| Recording to file | Built | `WebSDRRecorder.swift` |
| Recording playback | Built | `RecordingPlaybackEngine.swift` |
| CW audio decoding | Built | `CWTranscriptionService+Decoder.swift` |
| Session coordination | Built | `WebSDRSession.swift` |
| Receiver picker | Built | `WebSDRPickerSheet.swift` |

### What's Missing

1. A "Tune In" entry point from spots (no connection between spots → WebSDR today)
2. A lightweight, non-modal listening player (today WebSDR is a logger panel command)
3. CW transcription routed from WebSDR audio (today it's microphone-only)
4. Standalone listening sessions outside the logger
5. Smart receiver selection based on activator location (today it's user-location sorted)

---

## UX Entry Points

### 1. Spot Row — Primary Entry

Add a "Tune In" action on spot rows. Three possible interaction patterns:

**Swipe action (recommended):**
Swipe left on any spot row → cyan "Tune In" button with `radio` SF Symbol. Consistent with iOS swipe-action conventions. Non-destructive, easily discoverable.

**Context menu:**
Long-press → "Tune In to K4SWL on 14.062" menu item. Good secondary entry for discoverability but slower.

**Tap-through detail sheet:**
Tap spot → detail sheet with station info, propagation data, and a primary "Tune In" button. Useful for showing receiver options before committing.

Apply to all spot row types:
- `POTASpotRow` (logger spots panel — activator monitoring)
- `ActivityLogSpotRow` (hunter/activity tab — primary discovery surface)
- Watch: `SpotsListView` (stretch goal — hand off to iPhone)

### 2. Map Integration

Add active spots as live annotations on the QSO map (or a dedicated spots layer). Tap annotation → callout with "Tune In" button. Visual connection between geography and listening.

### 3. SpotsMiniMapView Enhancement

The RBN mini-map already shows spotter arcs with SNR coloring. Add a "Listen" button that auto-selects the receiver closest to the highest-SNR spotter. Natural bridge — you're already looking at propagation paths.

---

## The Listening Experience

### Mini Player (Bottom Sheet)

The core innovation: a **persistent mini player** that lives at the bottom of the screen, like Apple Music. Non-modal — browse spots, check the map, view logs, all while audio plays.

#### Collapsed State (Mini Bar)

A slim bar above the tab bar:

```
┌─────────────────────────────────────────────────┐
│  ● LIVE   K4SWL  14.062 CW  ▶ KiwiSDR: AB1OC  │
│           ▓▓▓▓▓▓▓▓▓░░░░░    [▐▐]  [×]          │
└─────────────────────────────────────────────────┘
```

- Red "LIVE" dot (pulsing when audio is flowing)
- Callsign (monospaced), frequency, mode
- Audio level mini-meter
- Pause/Resume and Close buttons
- Tap anywhere else to expand

#### Expanded State (Pull Up or Tap)

```
┌─────────────────────────────────────────────────┐
│  Tune In                                  Done  │
│─────────────────────────────────────────────────│
│                                                 │
│  K4SWL                          ● LIVE 3:42     │
│  US-4557 Pisgah National Forest                 │
│  14.062 MHz  CW  20m                            │
│                                                 │
│  ┌─ Receiver ─────────────────────────────────┐ │
│  │  AB1OC — Stow, MA                         │ │
│  │  342 mi from activator  •  SNR 28 dB      │ │
│  │  ▓▓▓▓▓▓▓▓▓░░░░░░  Signal                 │ │
│  │                          [Change Receiver] │ │
│  └────────────────────────────────────────────┘ │
│                                                 │
│  🔊 ━━━━━━━━━━━━━━━━━━━━━━━●━━━━━━━━━━━━━  🔇 │
│                                                 │
│  ┌─ Live Transcript ─────────────────────────┐ │
│  │                                           │ │
│  │  ┌──────────────────────────────┐         │ │
│  │  │ CQ CQ CQ DE K4SWL K4SWL K  │         │ │
│  │  └──────────────────────────────┘         │ │
│  │                                           │ │
│  │         ┌──────────────────────────────┐  │ │
│  │         │ K4SWL DE W3ABC W3ABC AR     │  │ │
│  │         └──────────────────────────────┘  │ │
│  │                                           │ │
│  │  ┌──────────────────────────────┐         │ │
│  │  │ W3ABC 599 TU 73 DE K4SWL   │         │ │
│  │  └──────────────────────────────┘         │ │
│  │                                           │ │
│  │              [W3ABC detected — Log QSO?]  │ │
│  └───────────────────────────────────────────┘ │
│                                                 │
│  ┌──────┐  ┌──────────┐  ┌────────┐           │
│  │ Mute │  │ Clip 📎  │  │ Open ↗ │           │
│  └──────┘  └──────────┘  └────────┘           │
│                                                 │
└─────────────────────────────────────────────────┘
```

### Key UI Elements

**Receiver Card:**
- Receiver name, location, distance from *activator* (not user)
- Real-time SNR meter from `KiwiSDRStatusFetcher`
- "Change Receiver" → existing `WebSDRPickerSheet`, pre-sorted by activator proximity

**Volume + Level:**
- Volume slider
- Audio level meter (existing implementation in `WebSDRPanelView`)

**Live Transcript (CW mode):**
- Chat bubble layout (design language: `CWTextElement` + existing bubble pattern)
- Auto-scroll, newest at bottom
- Callsigns highlighted and tappable
- "Log QSO?" inline action when a callsign exchange is detected

**Action Buttons:**
- Mute / Unmute
- Clip — mark a moment for later (saves timestamp to recording timeline)
- Open in Browser — `webURL` from `WebSDRSession`

---

## Smart Receiver Selection

When the user taps "Tune In," the app should auto-select the best receiver **without requiring a picker** in the happy path.

### Algorithm

```
1. Get activator location:
   - From spot's park/summit coordinates (POTA parkRef → lookup, SOTA summit → lookup)
   - From spotter grid square (RBN spots have spotterGrid)
   - From callsign prefix → DXCC entity centroid (fallback)

2. Filter WebSDRDirectory receivers:
   - Must cover the spot's band
   - Must have available slots (users < maxUsers)
   - Must have antenna connected (if status fetched)

3. Score receivers:
   - Primary: distance to activator (closer = better propagation path)
   - Secondary: SNR (if recently fetched)
   - Tertiary: antenna directionality toward activator
   - Bonus: user has favorited this receiver

4. Select top receiver. Show in player with "Change Receiver" option.
```

### Proximity Heuristic

For HF propagation, "closer to activator" isn't always better (skip zone). But as a first-pass heuristic, receivers within 200-2000 miles of the activator tend to hear NVIS and skip-zone signals well. Receivers too close (< 50 mi) may be in the skip zone. Consider a scoring curve that penalizes both very close and very far receivers, peaking around 500-1500 miles.

---

## Live CW Transcription

### Architecture

Route WebSDR audio through the CW decoder pipeline:

```
KiwiSDRClient (WebSocket)
    → AudioFrame stream
    → KiwiSDRAudioEngine (playback)
    → CWTranscriptionService (decode)  ← NEW CONNECTION
        → CWTextElement stream
        → CallsignDetector
        → TuneInTranscriptView (display)
```

Today `CWTranscriptionService` takes audio from `CWAudioCapture` (microphone). Refactor to accept an `AsyncStream<AudioFrame>` source, making it input-agnostic.

### Transcript Display

Use the existing chat bubble pattern from the design language:

- **Left-aligned bubbles** for the activator (detected by the spot's callsign)
- **Right-aligned bubbles** for callers (other detected callsigns)
- **Gray bubbles** for unattributed CW
- Callsigns in **monospaced bold**, tappable to:
  - Show callsign lookup (QRZ)
  - Pre-fill "Log QSO" form
  - Check worked-before status

### QSO Detection

When the decoder identifies a complete exchange pattern:
```
[THEIR_CALL] DE [ACTIVATOR] [RST] [INFO] [73/TU]
```

Show an inline prompt:
```
┌─────────────────────────────────────┐
│  QSO detected: W3ABC               │
│  RST: 599  Band: 20m  Mode: CW     │
│                                     │
│  [Log QSO]         [Dismiss]        │
└─────────────────────────────────────┘
```

This pre-fills everything from the decoded exchange. One-tap logging.

### SSB / Phone Mode

No automatic transcription for SSB (too unreliable with QRM). Show:
- Audio level meter
- Recording indicator with duration
- Manual "Log QSO" button (no pre-fill)

Future: experimental Whisper-based transcription as an opt-in beta feature.

### Digital Modes (FT8/FT4)

If the existing FT8 decoder can accept WebSDR audio input:
- Show decoded messages in a waterfall-style list
- Highlight CQ calls and the spotted station
- No "Log QSO" pre-fill (FT8 logging is automated differently)

---

## Recordings

### Automatic Recording

Every "Tune In" session is automatically recorded (using existing `WebSDRRecorder`). No user action required.

### Session Linking

**During an active logging session:**
Recording attaches to the `LoggingSession` via existing `WebSDRRecording` model. Appears in session detail alongside QSOs and spots.

**Standalone listening (no active session):**
Create a lightweight `ListeningSession` concept — or reuse `WebSDRRecording` with enriched metadata:
- Source spot info (callsign, park/summit, frequency, mode)
- Receiver used
- Duration
- CW transcript (if generated)
- Any QSOs logged during listening
- Clip bookmarks

### Recordings List

Enhance existing `WebSDRRecordingsView` with:
- **Thumbnail header**: Callsign + park/summit badge + band/mode + date
- **Duration** and **receiver name**
- **Transcript preview**: First few decoded lines (CW mode)
- **Clip markers**: Visual timeline dots for bookmarked moments
- **Share**: Branded clip card via existing `RecordingShareCardView`

### Clip Creation

During playback of a recording, let users:
1. Set in/out points on the timeline
2. Add a caption
3. Export as a shareable audio clip with the branded share card
4. Share to Discord/social (amateur radio communities love QSO recordings)

---

## Smart Features (Post-MVP)

### Auto-Retune on QSY

Monitor incoming spots for the same callsign. If the activator gets re-spotted on a different frequency:

```
┌─────────────────────────────────────────┐
│  K4SWL spotted on 7.030 CW (40m)       │
│  Currently listening on 14.062 (20m)    │
│                                         │
│  [Retune to 40m]         [Stay on 20m]  │
└─────────────────────────────────────────┘
```

### Receiver Quality Monitoring

Track audio quality metrics during the session. If signal degrades significantly (SNR drops, noise floor rises), suggest switching:

```
Signal degraded on AB1OC. W1AW (Newington, CT) has better reception.
[Switch Receiver]
```

### Follow an Activator

Pin a callsign from any spot. Get a notification when they appear on a new band/park. Auto-offer "Tune In" from the notification.

### Listening Activity Feed

Show which activations other Carrier Wave users are tuned into. Social proof:
- "3 listeners" badge on a spot row
- Activity feed: "W1XYZ tuned in to K4SWL on 20m CW"

---

## Implementation Phases

### Phase 1: Core Tune-In Flow
- Swipe action "Tune In" on `POTASpotRow` and `ActivityLogSpotRow`
- Smart receiver auto-selection (activator-proximity sorted)
- Mini player bottom sheet (collapsed bar + expanded view)
- Audio streaming via existing `KiwiSDRAudioEngine`
- Automatic recording via existing `WebSDRRecorder`
- Basic receiver info display + "Change Receiver"

### Phase 2: Live CW Transcription
- Refactor `CWTranscriptionService` to accept WebSDR audio stream
- Chat bubble transcript view in expanded player
- Callsign detection + highlight
- One-tap "Log QSO" pre-fill from decoded exchanges

### Phase 3: Recordings & Clips
- Enhanced `WebSDRRecordingsView` with spot metadata
- Standalone listening sessions (not requiring active logger)
- Clip bookmarking during live listening
- Clip export with share card
- Recording playback with transcript sync

### Phase 4: Smart Features
- Auto-retune on QSY detection
- Receiver quality monitoring + switch suggestions
- Follow/pin activator callsign
- Listening activity feed (social)

---

## Design Decisions (Resolved)

1. **No dedicated tab.** Spot-row swipe action is sufficient as the entry point. No separate tab or section needed.

2. **No background audio.** Kill the WebSDR connection when the app is backgrounded. Don't continue streaming like a podcast app — this isn't a passive listening use case.

3. **Cellular data warning: yes.** Show a first-time warning on cellular (~5 MB/hour). Don't nag on every session, just the first time on cellular.

4. **Single tune-in only.** No concurrent streams in MVP or beyond unless demand emerges.

5. **Entry point: hunter log.** Tune In lives in the hunter log / activity tab as a standalone feature. Not tied to an active logging session.

6. **CW transcription from hunter log.** The hunter is the one listening and decoding — surface CW transcription in the hunter log context.

7. **All Phase 4 social features confirmed:** Auto-retune on QSY, receiver quality monitoring + switch suggestions, follow/pin activator, listening activity feed with listener counts on spots.

8. **Watch integration: deferred.** Not pursuing Watch hand-off or "now listening" complication right now.

9. **Mini player bar confirmed.** Persistent bottom bar (Apple Music-style) — collapsed bar above the tab bar, tap to expand. Browse the app while listening.
