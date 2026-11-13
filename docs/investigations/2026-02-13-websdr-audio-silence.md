# Investigation: WebSDR Audio Silence

**Date:** 2026-02-13
**Status:** Resolved
**Outcome:** Audio ring buffer starved due to recorder file I/O blocking the audio write path

## Problem Statement

User reported no audio from WebSDR playback regardless of mute/unmute toggle state. The WebSDR panel shows connection and level meter activity, but no sound is produced through the device speaker or headphones.

## Hypotheses

### Hypothesis 1: Audio ring buffer starvation due to processing order
- **Evidence for:** `processAudioStream` wrote to the recorder (actor + file I/O) BEFORE writing to the audio ring buffer. Each frame iteration also had 3+ unnecessary suspension points (`await MainActor.run`, `await recorder?.peakLevel`). At 12kHz with ~256 samples/frame (~21ms per frame), even small delays per iteration cause the ring buffer to drain faster than it fills.
- **Evidence against:** None
- **Tested:** Yes
- **Result:** Root cause confirmed. Reordering to write audio engine first and removing unnecessary suspension points fixes the issue.

### Hypothesis 2: AVAudioSession configuration failure
- **Evidence for:** `configureAudioSession()` uses `try?` which silently swallows errors
- **Evidence against:** `.playback` with `.mixWithOthers` is standard and unlikely to fail
- **Tested:** No (not root cause)
- **Result:** Not the issue

### Hypothesis 3: Mute state bug
- **Evidence for:** User reported no audio with or without audio button
- **Evidence against:** `toggleMute()` correctly sets `outputVolume` to 0 or 1, and `isMuted` defaults to `false`
- **Tested:** Code review
- **Result:** Not the issue

## Investigation Log

### Step 1: Traced audio pipeline
Mapped the full data flow: KiwiSDRClient (WebSocket → ADPCM decode → AsyncStream) → WebSDRSession.processAudioStream (main actor loop) → KiwiSDRAudioEngine (ring buffer → AVAudioSourceNode render callback).

### Step 2: Identified processing bottleneck
In `processAudioStream`, each frame iteration had this sequence:
1. `try await recorder?.writeFrame(frame.samples)` — actor hop + file I/O (~5-10ms)
2. `audioEngine?.write(frame.samples)` — fast ring buffer write
3. `await MainActor.run { self.sMeter = ... }` — unnecessary suspension point
4. `await recorder?.peakLevel` — actor hop (~1-2ms)
5. `await MainActor.run { self.peakLevel = ... }` — unnecessary suspension point

The audio write at step 2 was blocked behind the recorder write at step 1. With frames arriving every ~21ms, the accumulated async overhead (~15-25ms per iteration) left almost no margin for the ring buffer to fill.

### Step 3: Verified ring buffer dynamics
Ring buffer: 36,000 samples = 3 seconds at 12kHz. Render callback consumes at 12kHz. Production delayed by recorder I/O meant the buffer started empty and never caught up. The adaptive rate adjustment (0.97x when low) only compensates 3%, not enough to overcome the deficit.

## Files Examined

| File | Relevance | Finding |
|------|-----------|---------|
| `WebSDRSession+Internals.swift` | Audio stream processing loop | Root cause: audio write after recorder write + unnecessary suspension points |
| `KiwiSDRAudioEngine.swift` | Audio playback engine | Correct implementation, ring buffer pull model works |
| `AudioRingBuffer.swift` | Thread-safe ring buffer | Correct, Sendable, real-time safe reads |
| `KiwiSDRClient.swift` | WebSocket client | Correct, ADPCM decode and AsyncStream yield work |
| `WebSDRRecorder.swift` | File recorder actor | Actor isolation + file I/O adds latency per frame |
| `WebSDRPanelView.swift` | UI panel | Mute toggle correctly wired |

## Root Cause

`processAudioStream` wrote audio frames to the recorder actor (involving an actor hop and disk I/O) BEFORE writing to the audio engine's ring buffer. Combined with redundant `await MainActor.run` calls (the method is already `@MainActor`) and an extra actor hop to read `recorder?.peakLevel`, each loop iteration had 4-5 suspension points that consumed most of the ~21ms frame budget. The ring buffer started empty on connection and could never accumulate enough samples for continuous playback.

## Resolution

1. Moved `audioEngine?.write(frame.samples)` to the top of the loop (before any async work)
2. Removed `await MainActor.run` wrappers for `sMeter` and `peakLevel` (already on `@MainActor`)
3. Compute peak level locally from samples instead of reading from the recorder actor (eliminates an actor hop per frame)

The recorder write is now the last operation in each iteration, after audio playback and UI updates are handled synchronously.
