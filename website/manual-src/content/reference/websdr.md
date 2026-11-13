---
title: "WebSDR Integration"
description: "Remote receiver listening, recording, playback, and clip export"
weight: 13
showToc: true
---

Connect to {{< term "KiwiSDR" >}} public receivers worldwide to monitor your transmissions from a remote location. Record audio during logging sessions and play back recordings with QSO-synced navigation.

## Overview

The WebSDR integration allows you to:

- **Listen remotely** to your transmission by connecting to public {{< term "KiwiSDR" >}} receivers
- **Record audio** during {{< term "POTA" >}} activations and logging sessions
- **Play back recordings** with QSO markers and waveform visualization
- **Share clips** of individual QSOs or time ranges with embedded metadata
- **Integrate with CW transcription** for decoded Morse overlay

This is invaluable for:

- Checking your signal quality from a remote location
- Documenting activations with audio evidence
- Reviewing your operating technique
- Sharing memorable QSOs

## Finding Receivers

Carrier Wave queries the public {{< term "KiwiSDR" >}} directory to help you find receivers near your operating location.

### Receiver Browser

The receiver browser displays:

- **Distance** from your {{< term "grid square" >}} (sorted by proximity)
- **Live SNR** and user count
- **Antenna details** with visual badges:
  - Antenna type (e.g., "Longwire", "Loop", "Vertical")
  - Band coverage (e.g., "160m-10m")
  - Directionality (e.g., "Omnidirectional", "E-W")

### Band Match Highlighting

During {{< term "POTA" >}} activations, receivers that support your current band display a **"Good for 40m"** badge (or whichever band you're operating). This helps you quickly find receivers optimized for your frequency.

### Receiver Selection Strategies

Carrier Wave supports multiple receiver selection strategies:

- **Near spotter** - Select a receiver close to an RBN skimmer that heard you (confirms the propagation path)
- **Near activator** - Select a receiver close to a station you're trying to work (checks if you can be heard there)
- **Near QTH** - Select a receiver close to your home location (useful for monitoring your own signal)
- **Auto-select** - Carrier Wave picks the best available receiver based on your current band, available capacity, and signal quality

### Proximity Search

Receivers are sorted by distance from your {{< term "grid square" >}}. The closest receivers appear first, making it easy to find strong local reception.

### Cellular Warning

When connected via cellular data (not Wi-Fi), Carrier Wave displays a warning banner:

- **Data usage estimate** based on audio quality and recording duration
- **Wi-Fi recommended** for extended recording sessions
- **Continue anyway** option if you accept the data usage

## Favorites

Mark frequently-used receivers as favorites for quick access.

### Adding Favorites

Tap any receiver card to expand a detail sheet with full information. Tap the **star icon** to favorite. Favorites appear at the top of the receiver list.

### iCloud Sync

Favorites sync across all your devices via iCloud. Add a favorite on your iPhone, and it appears on your iPad.

### Favorites Management

Navigate to **Settings > WebSDR Favorites** to:

- Search favorites by name or location
- Sort by proximity to your current grid
- Remove favorites

### Manual Receiver Entry

To add a private or unlisted {{< term "KiwiSDR" >}}:

1. Go to **Settings > WebSDR**
2. Enable **Advanced Mode**
3. Tap **Add Manual Receiver**
4. Enter the receiver's **host:port** (e.g., `sdr.example.com:8073`)

Carrier Wave validates the connection before saving. Manual receivers appear alongside public ones and can be favorited.

## Connecting

### Starting a Connection

In the logger, enter the **WEBSDR** command to:

- Open the receiver picker (first time)
- Reconnect to the last-used receiver (subsequent times)

Alternatively, tap any receiver card in the picker to connect immediately.

### Connection Process

Carrier Wave establishes a {{< term "WebSocket" >}} connection to the receiver and:

1. Authenticates with the server
2. Tunes to your session frequency and mode
3. Starts receiving audio packets
4. Begins recording (if auto-record is enabled)

### Resilient Reconnects

If the connection drops (network interruption, receiver reboot), Carrier Wave:

- Retries up to **5 times** with exponential backoff
- Preserves your recording file and duration timer
- Resumes audio from where it left off
- Fills silence gaps in the recording to maintain accurate timeline

### Receiver Quality Monitoring and Fallback

Carrier Wave continuously monitors the connected receiver's quality:

- **Audio level tracking** - Detects if the receiver goes silent or produces only noise
- **Latency monitoring** - Tracks round-trip time to the receiver
- **User count** - Monitors receiver load
- **Automatic fallback** - If quality degrades below a threshold for more than 30 seconds, Carrier Wave can automatically switch to the next-best available receiver (if auto-select is enabled)
- **Manual override** - A quality indicator in the WebSDR panel lets you see current receiver health and switch manually

### Redirect Handling

Some {{< term "KiwiSDR" >}} servers redirect to alternate addresses. Carrier Wave follows up to **3 redirect hops** and caches the effective host/port for faster reconnects.

## Tuning

When connected, the receiver automatically:

- Tunes to your **session frequency**
- Switches to your **session mode** (e.g., {{< term "SSB" >}}, {{< term "CW" >}})
- Applies **filter bandwidth** appropriate for the mode:
  - {{< term "CW" >}}: 300-800 Hz
  - {{< term "SSB" >}}: 2.4 kHz
  - {{< term "AM" >}}: 6 kHz

### CW Pitch Offset

For {{< term "CW" >}}, Carrier Wave applies a **pitch offset** so the signal lands in the audio passband (typically 500-700 Hz). This ensures you hear the tone clearly.

### QSY Detection and Auto-Retune

When you change your operating frequency in the Logger (via frequency entry, the BAND command, or BLE radio sync), the WebSDR receiver automatically retunes:

- **Immediate retune** when you enter a new frequency
- **Mode change** detection triggers appropriate filter bandwidth adjustment
- **Band change** detection may trigger receiver switch if the current receiver doesn't cover the new band
- **Seamless** - Recording continues uninterrupted during retune

### Frequency Changes

Change your session frequency or mode in the logger, and the receiver re-tunes automatically. No need to disconnect and reconnect.

## Live Playback

Audio from the receiver plays through your device's speakers or headphones.

### Jitter Buffering

Carrier Wave uses a **ring buffer** (5-second capacity) to smooth out network jitter. Audio pre-buffers for **1 second** before playback begins, preventing stutter.

### Controls

- **Mute button** to silence audio without disconnecting
- **Buffer health indicator** shows how full the ring buffer is (green = healthy, yellow = low, red = underrun)

### Background Audio

Audio continues playing when you background the app or lock your device. The connection remains active, and recording continues.

## Instant Replay

During a live WebSDR session, tap the **Replay** button in the WebSDR panel to instantly re-hear the last 15 seconds of captured audio. This is useful when you miss part of a callsign or exchange.

### Triggering Replay

You can trigger a replay in three ways:

- **Replay button** in the WebSDR panel toolbar
- **Logger commands:** Type `REPLAY`, `AGN`, or `HUH` in the callsign entry field

The replay plays back the buffered audio without interrupting the live connection. New audio continues to be captured during playback.

## WebSDR Panel

The WebSDR panel (visible while connected) displays:

- **Connection status** (connected, reconnecting, disconnected)
- **Frequency** and **mode**
- **Filter bandwidth**
- **Level meter** showing received audio strength
- **Recording duration** (if recording is active)
- **Quality indicator** showing receiver health
- **Browser link** to open the receiver's web interface in Safari

## Recording

Carrier Wave can record audio from the receiver to document your session.

### Auto-Record

Enable **Auto-record during sessions** in Settings > WebSDR. When enabled, recording starts automatically when you connect to a receiver during an active logging session.

### Manual Recording

Tap the **Record button** in the WebSDR panel to start/stop recording manually. You can record outside of sessions (e.g., listening to a contest).

### Recording File

Audio is compressed and saved to a file on your device. Recordings include:

- **Timestamp** (start time)
- **Session ID** (if part of a session)
- **Frequency and mode changes** with timestamps
- **QSO markers** synced to timestamps

### Gap Filling

If the connection drops during recording:

- Carrier Wave fills the gap with **silence** to maintain an accurate timeline
- The recording duration continues incrementing
- When reconnected, audio resumes at the correct position

### Recording Continuity

Recording persists across:

- **Pause/resume** (tap the pause button)
- **Disconnect/reconnect** (network interruption)
- **Frequency/mode changes**

### Dormant State

If you disconnect intentionally (e.g., moving to a new location), the recording enters a **dormant state** for up to **30 minutes**. Reconnect within that window, and recording continues seamlessly.

### Recording Badge

While recording is active, a **persistent badge** appears in the logger header. Tap the badge to view recording duration and controls. The badge remains visible even when the WebSDR panel is collapsed.

## Recording Playback

Tap a session's recording in the session detail view or compact player card to open the full-screen playback interface.

### Waveform Visualization

The waveform shows:

- **Amplitude envelope** (visual representation of audio level)
- **QSO markers** (vertical lines at each QSO timestamp)
- **Active QSO highlight** (the QSO corresponding to the current playback position)

### Playback Controls

- **Play/Pause** button
- **Drag-to-seek scrubber** to jump to any position
- **Speed control** (0.5x, 0.75x, 1x, 1.25x, 1.5x, 2x)

### Speed Control

Adjust playback speed for review:

- **0.5x** - Half speed for detailed CW analysis
- **0.75x** - Slightly slower for catching details
- **1x** - Normal speed
- **1.25x-2x** - Faster for scanning through long recordings

Speed changes are smooth (no audio artifacts) and maintain correct pitch.

### QSO-Synced Navigation

- **Tap a QSO** in the list to seek to that QSO's timestamp
- **Scrub the waveform** to highlight the active QSO
- **Auto-scroll** to keep the active QSO visible in the list

### Transcript Sync with Playback

When CW transcription data is available for the recording, the transcript scrolls in sync with audio playback:

- **Highlighted text** shows the portion of the transcript corresponding to the current playback position
- **Tap transcript text** to seek to that point in the recording
- **Conversation view** updates to show the active exchange

## Compact Player

Recordings appear as **inline cards** in:

- {{< term "POTA" >}} activation detail view
- Sessions list

The card displays:

- **Mini waveform** (simplified amplitude envelope)
- **Recording duration**
- **Tap to expand** to full-screen player

## Clip Export with Metadata

Export a time range from a recording as a standalone audio file with embedded metadata.

### Creating a Clip

1. Open the recording playback interface
2. Tap the **Share** button
3. Adjust the **range handles** to select the desired time window (default: active QSO start/end)
4. Tap **Export Clip**

### M4A Export

The clip is exported as an **M4A** file (compressed audio) with metadata tags:

- **Title** - Callsign and QSO date
- **Artist** - Your callsign
- **Album** - Session name
- **Comment** - Frequency, mode, park reference
- **Artwork** - Session thumbnail

### Sharing

Share via the iOS share sheet:

- AirDrop
- Messages
- Email
- Save to Files

## Recordings Management

View and manage all recordings in **Settings > WebSDR Recordings**.

### Recording List

The list shows:

- **Recording thumbnail** (mini waveform)
- **Date and duration**
- **Session name** (if part of a session)

### Actions

- **Share** a recording (full file or clip)
- **Delete** a recording to free space

Deleted recordings cannot be recovered.

---

## See Also

- [Logger](/reference/logger/) -- Commands and logging flow
- [CW Transcription](/reference/cw-transcription/) -- Morse decoding with WebSDR audio
- [POTA](/reference/pota/) -- Activation workflow
- [Export & Sharing](/reference/export/) -- Clip export and share cards
- [Settings](/reference/settings/) -- WebSDR preferences
