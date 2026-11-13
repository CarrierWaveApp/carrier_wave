---
title: "CW Transcription"
description: "Morse code decoding, conversation tracking, and auto-fill"
weight: 11
showToc: true
---

CW Transcription decodes Morse code audio from your radio, helping you copy callsigns and exchange information. The decoder uses real-time audio processing with adaptive frequency and speed tracking.

## Enabling Transcription

The **CW** tab is always available. It ships hidden in the tab bar by default — add it from **More → Customize Tab Bar**. Once visible, tap the CW tab and grant microphone permission when prompted.

The transcription panel fills the CW tab view.

## How It Works

1. **Audio capture** - Microphone picks up your radio's audio
2. **Tone detection** - Goertzel algorithm identifies CW tones at the target frequency
3. **Frequency tracking** - Automatically locks onto the dominant tone and follows drift
4. **Speed estimation** - Adaptive WPM tracking adjusts to the sender's speed in real time
5. **Decoding** - Morse patterns converted to text using timing analysis
6. **Display** - Decoded text shown in real-time with conversation separation

## Audio Processing

### Goertzel Filter

The decoder uses the Goertzel algorithm for efficient single-frequency tone detection:

- **Targeted detection** - Computes signal energy at a specific frequency rather than performing a full FFT
- **Low CPU overhead** - Runs continuously in real time without significant battery impact
- **Configurable bandwidth** - Detection window can be narrowed to reject adjacent signals
- **Sample-by-sample processing** - Operates on the audio stream with minimal latency

The Goertzel filter is more efficient than FFT when monitoring a single tone, making it ideal for CW decoding on mobile devices.

### Adaptive Thresholds

Background noise is analyzed to set:
- Tone detection threshold (auto-adjusts to ambient noise floor)
- Noise gate level
- Signal-present confidence score

### Audio Input Sources

- **Device microphone** - Hold phone near speaker
- **Wired audio** - Connect via audio cable for cleaner signal
- **WebSDR audio** - When connected to a WebSDR receiver, CW transcription can decode the receiver's audio stream directly

## Frequency Tracking

### Automatic

The decoder automatically finds and tracks the CW tone:
- Detects dominant tone frequency in the audio passband
- **Adaptive tracking** follows the tone as it drifts (common with analog receivers or temperature changes)
- Works across typical CW pitch ranges (400-900 Hz)
- **Lock indicator** shows when the decoder has acquired a stable tone

### Manual

If automatic tracking struggles:
1. Tap the frequency indicator
2. Adjust the target frequency manually
3. Tap to lock

Manual lock is useful in high-QRM conditions where multiple tones compete for the decoder's attention.

## WPM Estimation

### Adaptive Speed Tracking

The decoder continuously estimates and adapts to the sender's speed:

- **Initial detection** - Analyzes the first few characters to estimate base speed
- **Running average** - Maintains a weighted moving average of dot and dash lengths
- **Speed display** - Current WPM shown in the transcription panel
- **Range** - Tracks speeds from approximately 5 WPM to 40 WPM
- **Speed changes** - Adapts within 2-3 characters when the sender's speed changes

### Farnsworth Timing

The decoder handles Farnsworth-spaced CW (where character speed is faster than word speed) by independently tracking:
- **Intra-character timing** (dots and dashes within a character)
- **Inter-character spacing** (gaps between characters)
- **Inter-word spacing** (gaps between words)

## Transcription Display

### Live Transcript

Characters appear as they're decoded. The display shows:

- Decoded text in a scrolling view
- Current character in progress (partial decode indicator)
- Timing indicators for element detection

### CW Conversation Tracker

The CW Conversation Tracker uses a state machine to separate and identify the two sides of a QSO:

**State Machine:**
1. **Listening** - Waiting for initial transmission
2. **Station A transmitting** - Receiving from the first station
3. **Pause detected** - Gap between transmissions
4. **Station B transmitting** - Receiving from the second station
5. **QSO in progress** - Alternating between stations

**Identification heuristics:**
- **Callsign detection** - When a callsign is decoded, the tracker associates it with the current transmission
- **Timing patterns** - Long pauses indicate station transitions
- **Frequency shift** - Slight frequency differences between stations (RIT offset) help distinguish them

### Chat-Style Conversation View

For extended QSOs, the conversation view presents decoded text in a chat-bubble layout:

- **Left bubbles** - Station A transmissions
- **Right bubbles** - Station B transmissions (or your own, if identified)
- **Timestamps** between exchanges
- **Callsign labels** when identified
- **Color coding** distinguishes the two stations

This view makes it easy to follow the flow of a QSO, especially at higher speeds where real-time copying is challenging.

## Callsign Detection

The decoder identifies likely callsigns in the transcript:

- Highlighted in the transcript with a distinct background color
- Common patterns recognized (W/K/N/A prefix for US, VE for Canada, international prefixes)
- **Confidence indicator** shows how likely the detected string is a valid callsign
- Tap to auto-fill the Logger callsign field

## Auto-Fill Integration

When a callsign is detected:

1. Callsign appears highlighted in the transcript
2. Tap to fill the Logger callsign field
3. QRZ lookup triggers automatically
4. Continue copying the QSO

## WebSDR Integration

When connected to a WebSDR receiver, CW transcription integrates with the tuning system:

- **Auto-retune** - If the CW tone drifts significantly, the decoder can request the WebSDR to retune for optimal reception
- **Frequency sync** - The decoder's target frequency stays in sync with the WebSDR's passband center
- **Transcript sync with playback** - During recording playback, the transcript scrolls in sync with the audio position

## Tips for Best Results

### Audio Setup

- Hold phone near speaker, or use audio cable
- Reduce background noise
- Moderate volume (not too loud, not too quiet)
- For best results, use the WebSDR audio path which bypasses the microphone entirely

### Tuning

- Center the signal in your passband
- Use narrow filter if available
- Reduce QRM by tuning away from interference

### Limitations

CW transcription works best with:
- Clean, well-spaced sending
- Single signal (no QRM)
- Standard timing

Challenging for:
- Very fast sending (35+ WPM)
- Poor sending (irregular timing)
- Heavy QRM/QRN
- Multiple overlapping signals

## Accuracy

Machine CW decoding isn't perfect. Use transcription as an aid, not a replacement for developing your own ear. When in doubt:
- Ask for repeats
- Verify callsigns via QRZ lookup
- Use your own ears for critical info

## See Also

- [Logger](/reference/logger/) - Log decoded contacts
- [WebSDR Integration](/reference/websdr/) - Remote receiver audio for decoding
- [Settings](/reference/settings/) - Audio preferences
