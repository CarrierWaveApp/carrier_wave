# CW Transcription

Real-time CW (Morse code) audio decoding from device microphone.

## Architecture

### Pipeline Overview

```
Microphone → Audio Capture → Signal Processor → Morse Decoder → UI
                                    ↓
                           ┌───────┴───────┐
                           ↓               ↓
                    Goertzel Filter   Level Meter
                    Bank (adaptive)
                           ↓
                    Frequency Tracking
                           ↓
                    Adaptive Threshold
                           ↓
                      Key Events
```

### Components

| Component | File | Purpose |
|-----------|------|---------|
| CWAudioCapture | `Services/CWAudioCapture.swift` | AVAudioEngine microphone capture, outputs `AsyncStream<AudioBuffer>` |
| GoertzelSignalProcessor | `Services/GoertzelSignalProcessor.swift` | Goertzel filter bank with adaptive frequency detection → key events |
| MorseDecoder | `Services/MorseDecoder.swift` | Timing state machine, classifies dits/dahs, outputs characters |
| MorseCode | `Services/MorseCode.swift` | Lookup tables, timing constants, abbreviations |
| CallsignDetector | `Services/CallsignDetector.swift` | Regex-based callsign extraction from transcript |
| CWTranscriptionService | `Services/CWTranscriptionService.swift` | Coordinates all components, publishes state for UI |

## Signal Processing Details

### 1. Audio Capture (`CWAudioCapture`)

- Uses `AVAudioEngine` with input node tap
- Sample rate: 44100 Hz (standard)
- Buffer size: 1024 frames (~23ms latency)
- Outputs `AsyncStream<AudioBuffer>` with samples + timestamps
- Requires `NSMicrophoneUsageDescription` in Info.plist

### 2. Goertzel Signal Processor (`GoertzelSignalProcessor`)

Uses the Goertzel algorithm for efficient single-frequency detection. More computationally efficient than FFT when detecting only one frequency.

**Goertzel Algorithm:**
- Processes audio in small blocks (128 samples, ~3ms at 44.1kHz)
- Computes magnitude at target frequency using recursive formula
- Hamming window applied to reduce spectral leakage

**Parameters:**
- Block size: 128 samples
- Target frequency: 600 Hz default, or adaptive range

### 3. Adaptive Frequency Detection

When enabled, automatically detects the CW tone frequency within a configurable range.

**Filter Bank:**
- Multiple Goertzel filters span the frequency range (e.g., 400-900 Hz)
- 50 Hz spacing between bins (typically 11 filters)
- Each bin's magnitude is smoothed (0.85 factor) to reduce noise

**Frequency Tracking Algorithm:**
1. Only scan for frequency changes when signal is actively present
2. Find the bin with strongest smoothed magnitude
3. Require signal to exceed both:
   - Relative threshold: 5x noise floor
   - Absolute threshold: 0.0005 magnitude
4. Track candidate frequency over multiple blocks
5. Lock to frequency after 15 consecutive blocks of confirmation
6. When locked, only unlock if a different frequency is 2.5x stronger AND persists for 15 blocks
7. During silence, decay bin magnitudes to prevent noise accumulation

**Range Presets:**
- Wide: 400-900 Hz (default)
- Normal: 500-800 Hz
- Narrow: 550-700 Hz

### 4. Adaptive Threshold (`GoertzelThreshold`)

Detects key-down/key-up transitions from Goertzel magnitude.

**Algorithm:**
1. Track `noiseFloor` (bidirectional adaptation)
2. Track `signalPeak` (fast attack, slow decay)
3. Calculate signal-to-noise ratio
4. Base on-threshold: 8.0x noise (adaptive down to 6.0x in poor SNR)
5. Off-threshold: 50% of on-threshold (hysteresis)
6. Confirmation: 3 consecutive blocks required for state change
7. Relative drop detection for catching element gaps

**Transmission Tracking:**
- Locks noise floor at transmission start to prevent drift
- Uses stricter off-confirmation during active transmission
- Ends transmission after 2 seconds of silence

**Calibration:**
- First 30 blocks (~80ms) used for calibration
- UI shows "Calibrating..." during this period

**Output:** Array of `(isDown: Bool, timestamp: TimeInterval)` events

### 5. Level Meter Normalization

Peak amplitude is normalized for UI display:
- Track running maximum of Goertzel magnitudes
- Normalize current peak to 0-1 range: `peak / runningMax`
- Running max decays slowly (0.9995) to adapt to level changes

## Morse Decoding

### Timing Classification (`MorseDecoder`)

Standard Morse timing (PARIS standard):
- Dit = 1 unit
- Dah = 3 units
- Element gap (within character) = 1 unit
- Character gap = 3 units
- Word gap = 7 units

**Classification thresholds:**
- Dit vs Dah: 2 units (with tolerance)
- Element vs Character gap: 2 units
- Character vs Word gap: 5 units

### Adaptive WPM

WPM estimated from measured element durations:
1. Collect recent dit/dah durations
2. Calculate implied unit duration for each
3. Use median for robustness against outliers
4. Smooth with exponential moving average
5. Clamp to valid range (5-60 WPM)

Formula: `unitDuration = 1.2 / WPM` seconds (PARIS standard)

### Character Lookup (`MorseCode`)

Static dictionary mapping Morse patterns to characters:
- Letters: `.-` → A, `-...` → B, etc.
- Numbers: `.----` → 1, `..---` → 2, etc.
- Punctuation: `.-.-.-` → `.`, `--..--` → `,`, etc.
- Prosigns: `-.-.-` → `<CT>`, `.-.-` → `<AA>`, etc.

Unknown patterns output as `[pattern]` for debugging.

## UI Components

### CWTranscriptionView

Main container with:
- Status bar (Ready/Calibrating/Listening indicator)
- Settings controls (WPM slider, Tone frequency slider)
- Waveform visualization
- Level meter (segmented bar)
- Transcript area
- Detected callsign bar
- Control buttons (Start/Stop, Copy, Clear)

### CWLevelMeter

12-segment horizontal bar showing input level:
- Red segments (0-20%): Too quiet
- Yellow/olive (20-50%): Low signal
- Green (50-80%): Good signal level
- Teal/blue (80-100%): High signal
- Unlit segments shown at 25% opacity

### CWWaveformView

Scrolling bar chart visualization:
- 32 bars showing recent envelope samples
- Green when signal detected, gray otherwise
- Updates in real-time from `waveformSamples`

## Data Flow

```
1. CWAudioCapture.startCapture() → AsyncStream<AudioBuffer>

2. For each buffer:
   CWSignalProcessor.process(samples, timestamp) → CWSignalResult
   ├── keyEvents: [(isDown, timestamp)]
   ├── peakAmplitude: Float (normalized 0-1)
   ├── isKeyDown: Bool
   ├── envelopeSamples: [Float]
   └── isCalibrating: Bool

3. For each key event:
   MorseDecoder.processKeyEvent(isKeyDown, timestamp) → [DecodedOutput]
   ├── .character(String) → append to transcript
   ├── .wordSpace → append space
   └── .element(MorseElement) → (debugging only)

   Note: In adaptive mode, result includes detectedFrequency for UI display

4. Timeout checker (100ms interval):
   MorseDecoder.checkTimeout(currentTime) → [DecodedOutput]
   └── Flushes pending character if silence > 5 units

5. UI updates via @Published properties:
   - state: .idle | .listening | .error
   - isCalibrating: Bool
   - estimatedWPM: Int
   - peakAmplitude: Float
   - isKeyDown: Bool
   - waveformSamples: [Float]
   - transcript: [CWTranscriptEntry]
   - currentLine: String
   - detectedCallsign: DetectedCallsign?
```

## Debugging

### Logging (temporary)

Debug print statements at key points:
- `[CW] Calibrating: N/100` - calibration progress with noise/peak values
- `[CW] Buffer:` - periodic buffer stats (every 500 samples)
- `[CW] Key DOWN/UP` - state transitions with signal ratio
- `[CW] Tone ended: DIT/DAH` - element classification with duration
- `[CW] Gap ended:` - gap classification
- `[CW] Decoded:` - pattern → character mapping
- `[CW] Service received:` - characters reaching UI

### Common Issues

**Level meter not moving:**
- Check microphone permission granted
- Verify audio session is active
- Check `peakAmplitude` normalization (runningMax tracking)

**No key events detected:**
- Signal too weak relative to noise floor
- Tone frequency mismatch (adjust slider to match sidetone)
- Calibration not complete (wait for "Listening" status)

**Characters not decoding:**
- Key events happening but gaps not long enough for character flush
- Check timeout checker is running
- Verify `currentPattern` accumulating elements

**Wrong characters decoded:**
- WPM mismatch (manual override may help)
- Timing thresholds need adjustment for sender's fist

**Frequency jumping around:**
- If adaptive mode keeps switching frequencies, try narrowing the range
- Use "Normal" or "Narrow" preset instead of "Wide"
- Or disable adaptive mode and set fixed frequency manually

## Configuration

### User-Adjustable Settings

| Setting | Range | Default | Purpose |
|---------|-------|---------|---------|
| WPM | 5-50 | 20 | Manual WPM override (also adaptive) |
| Adaptive Frequency | On/Off | On | Auto-detect tone frequency |
| Frequency Range | Wide/Normal/Narrow | Wide | Range for adaptive detection |
| Tone Frequency | 400-1000 Hz | 600 Hz | Fixed frequency (when adaptive off) |
| Pre-Amp | On/Off | Off | 10x signal boost for weak signals |

### Internal Constants

| Constant | Value | Location |
|----------|-------|----------|
| Buffer size | 1024 frames | CWAudioCapture |
| Goertzel block size | 128 samples | GoertzelSignalProcessor |
| Frequency step | 50 Hz | GoertzelSignalProcessor |
| Frequency lock threshold | 15 blocks | GoertzelSignalProcessor |
| Bin smoothing factor | 0.85 | GoertzelSignalProcessor |
| Detection ratio | 5.0x noise | GoertzelSignalProcessor |
| Min detection magnitude | 0.0005 | GoertzelSignalProcessor |
| Base on threshold | 8.0x noise | GoertzelThreshold |
| Off threshold ratio | 0.5x on | GoertzelThreshold |
| Calibration blocks | 30 | GoertzelThreshold |
| Confirmation blocks | 3 | GoertzelThreshold |
| Char timeout | 5 units | MorseDecoder |

## Future Improvements

- [ ] Audio recording/playback for practice
- [ ] Confidence indicator for decoded characters
- [ ] Haptic feedback on key-down
- [ ] POTA activation integration (pre-fill callsign)
- [ ] Session persistence
- [ ] iPad layout optimization
