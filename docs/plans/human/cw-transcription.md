# CW Transcription Feature Design

## Overview

A real-time CW (Morse code) transcription view that listens via the device microphone, decodes Morse code audio, and helps log QSOs by extracting callsigns and signal reports from the decoded text.

## Goals

1. **Real-time decoding**: Transcribe CW audio from microphone with minimal latency
2. **Callsign extraction**: Automatically detect and highlight callsigns in transcript
3. **QSO assistance**: Pre-fill callsign and RST fields for quick logging
4. **Adaptive WPM**: Automatically adjust to sender's speed (10-40+ WPM)
5. **Integration**: Seamlessly integrate with existing logging workflow and POTA activations

## Technical Approach

### Audio Processing Pipeline

Two signal processing backends are available, selectable at runtime:

#### Backend 1: Bandpass Filter (Default)

Based on [cw-companion](https://github.com/cerkit/cw-companion) approach:

```
Microphone → Bandpass Filter → Envelope Detector → Threshold → Timing Decoder → Text
     ↓              ↓                  ↓               ↓              ↓
AVAudioEngine   vDSP Biquad      Envelope         Adaptive      State Machine
                @ 600Hz          Follower         Threshold     (dit/dah/space)
```

#### Backend 2: Goertzel Algorithm

Uses the Goertzel algorithm for efficient single-frequency detection:

```
Microphone → Block Buffer → Hamming Window → Goertzel DFT → Threshold → Timing Decoder → Text
     ↓            ↓              ↓                ↓              ↓              ↓
AVAudioEngine  128 samples    Reduce         Magnitude at    Adaptive      State Machine
               (~3ms blocks)  Leakage        target freq     Threshold     (dit/dah/space)
```

The Goertzel algorithm computes `magnitude = sqrt(s1² + s2² - coeff*s1*s2)` where:
- `coeff = 2 * cos(2π * targetFreq / sampleRate)`
- Main recursion: `s0 = sample + coeff * s1 - s2`

This approach is more computationally efficient for detecting a single frequency compared to FFT or bandpass filtering.

#### 1. Audio Capture (AVFoundation)

```swift
actor CWAudioCapture {
    private let audioEngine = AVAudioEngine()
    private let bufferSize: AVAudioFrameCount = 1024

    func startCapture() async throws -> AsyncStream<[Float]>
}
```

- Use `AVAudioEngine` with input node tap
- Sample rate: 44100 Hz
- Buffer size: 1024 frames (~23ms latency)
- Request microphone permission via `NSMicrophoneUsageDescription`

#### 2. Bandpass Filter (Accelerate/vDSP)

```swift
struct BandpassFilter {
    // Digital biquad filter centered at CW tone frequency
    // Typical CW sidetone: 500-800 Hz (configurable, default 600 Hz)
    // Q factor: 5.0-10.0 (narrow band to reject noise)

    func process(_ samples: [Float]) -> [Float]
}
```

#### 3. Envelope Detection

```swift
struct EnvelopeFollower {
    // Fast attack (~5ms) to catch tone onset
    // Slower decay (~20ms) to smooth gaps
    // Outputs amplitude envelope 0.0-1.0

    func process(_ samples: [Float]) -> [Float]
}
```

#### 4. Adaptive Threshold

```swift
struct AdaptiveThreshold {
    // Tracks signal floor and peak levels
    // Adjusts threshold dynamically for varying signal strengths
    // Outputs ON/OFF state with hysteresis

    func process(_ envelope: [Float]) -> [Bool]
}
```

#### 5. Morse Decoder (State Machine)

```swift
actor MorseDecoder {
    // Timing-based state machine
    // Measures ON durations → dit (1 unit) or dah (3 units)
    // Measures OFF durations → element gap (1), char gap (3), word gap (7)

    // Adaptive WPM estimation from measured timings
    var estimatedWPM: Int

    func process(_ keyStates: AsyncStream<(Bool, TimeInterval)>) -> AsyncStream<DecodedElement>
}
```

### Data Models

#### CWTranscriptEntry

```swift
struct CWTranscriptEntry: Identifiable {
    let id: UUID
    let timestamp: Date
    let rawText: String
    let elements: [CWElement]  // For highlighted rendering

    enum CWElement {
        case text(String)
        case callsign(String)
        case signalReport(String)  // 599, 579, etc.
        case prosign(String)       // CQ, DE, K, BK, etc.
    }
}
```

#### CWSession (SwiftData, optional persistence)

```swift
@Model
final class CWSession {
    var startTime: Date
    var endTime: Date?
    var transcript: String
    var detectedCallsigns: [String]
    var audioFileURL: URL?  // Optional recording
    var linkedQSOs: [QSO]?
}
```

### Callsign Detection

Use regex patterns to identify callsigns in decoded text:

```swift
struct CallsignDetector {
    // International callsign patterns
    // Prefix (1-3 chars) + number + suffix (1-4 chars)
    // Examples: W1AW, VK2ABC, JA1XYZ, 9A2AA

    static let pattern = #"[A-Z0-9]{1,3}[0-9][A-Z]{1,4}"#

    func extract(from text: String) -> [String]
    func highlightCallsigns(in entry: CWTranscriptEntry) -> CWTranscriptEntry
}
```

### QSO Pattern Recognition

Detect common QSO exchange patterns:

```swift
struct QSOPatternMatcher {
    // "CQ CQ CQ DE {callsign} {callsign} K"
    // "{callsign} DE {callsign} UR 599 599 {state} K"
    // "R R {callsign} UR 599 {state} TU"

    func detectExchange(entries: [CWTranscriptEntry]) -> DetectedQSO?
}

struct DetectedQSO {
    var theirCallsign: String?
    var myCallsign: String?
    var rstSent: String?
    var rstReceived: String?
    var exchange: String?  // State, serial, etc.
}
```

## UI Design

### View Hierarchy

```
CWTranscriptionView
├── Header (activation context, if any)
├── TranscriptionControls
│   ├── StatusIndicator (Listening/Paused/Recording)
│   ├── WPMDisplay (adaptive, with manual override)
│   └── CloseButton
├── WaveformView (real-time audio visualization)
├── TranscriptView (scrolling decoded text)
│   └── TranscriptEntryRow (timestamp + highlighted text)
├── DetectedCallsignBar (prominent, with "Use" button)
├── ActionButtons (Audio settings, Record, Copy, Clear)
└── QuickLogBar (RST fields + Log button)
```

### CWTranscriptionView (Main Container)

```swift
struct CWTranscriptionView: View {
    @State private var transcriptionService: CWTranscriptionService
    @State private var isListening = false
    @State private var estimatedWPM: Int = 20
    @State private var transcript: [CWTranscriptEntry] = []
    @State private var detectedCallsign: String?
    @State private var isRecording = false

    // Pre-filled from detected QSO
    @State private var rstSent: String = "599"
    @State private var rstReceived: String = "599"

    // Optional activation context
    var activation: POTAActivation?
    var onLog: (QSO) -> Void
}
```

### WaveformView

```swift
struct WaveformView: View {
    let samples: [Float]  // Recent audio levels
    let isKeyDown: Bool   // Current key state for color

    // Renders scrolling bar chart visualization
    // Green bars when signal detected, gray otherwise
}
```

### TranscriptView

```swift
struct TranscriptView: View {
    let entries: [CWTranscriptEntry]

    // Scrolling list with auto-scroll to bottom
    // Each entry shows: timestamp | decoded text with highlights
    // Callsigns in color (e.g., blue for calling station, red for responding)
    // Prosigns dimmed (CQ, DE, K, etc.)
}
```

### DetectedCallsignBar

```swift
struct DetectedCallsignBar: View {
    let callsign: String?
    let onUse: (String) -> Void

    // Prominent display when callsign detected
    // "Detected callsign: K4SWL [Use]"
    // Tapping "Use" populates the logging fields
}
```

## Services

### CWTranscriptionService

```swift
@MainActor
final class CWTranscriptionService: ObservableObject {
    @Published var isListening = false
    @Published var estimatedWPM: Int = 20
    @Published var transcript: [CWTranscriptEntry] = []
    @Published var detectedCallsign: String?
    @Published var currentAmplitude: Float = 0
    @Published var recentSamples: [Float] = []
    @Published var isKeyDown = false

    private let audioCapture: CWAudioCapture
    private let signalProcessor: CWSignalProcessor
    private let morseDecoder: MorseDecoder
    private let callsignDetector: CallsignDetector

    func startListening() async throws
    func stopListening()
    func clear()
    func copyTranscript() -> String

    // Recording
    func startRecording() async throws
    func stopRecording() -> URL?
}
```

### CWSignalProcessor Protocol

Both backends conform to `CWSignalProcessorProtocol`:

```swift
protocol CWSignalProcessorProtocol: Actor {
    var currentToneFrequency: Double { get }
    func process(samples: [Float], timestamp: TimeInterval) -> CWSignalResult
    func setToneFrequency(_ frequency: Double)
    func reset()
}

enum CWDecoderBackend: String, CaseIterable {
    case bandpass = "Bandpass Filter"
    case goertzel = "Goertzel"
}
```

#### CWSignalProcessor (Bandpass Backend)

```swift
actor CWSignalProcessor: CWSignalProcessorProtocol {
    private var bandpassFilter: BiquadFilter
    private var envelopeFollower: EnvelopeFollower
    private var threshold: AdaptiveThreshold

    func process(samples: [Float], timestamp: TimeInterval) -> CWSignalResult
}
```

#### GoertzelSignalProcessor (Goertzel Backend)

```swift
actor GoertzelSignalProcessor: CWSignalProcessorProtocol {
    private var goertzelFilter: GoertzelFilter
    private var threshold: GoertzelThreshold
    private let blockSize: Int = 128  // ~3ms at 44.1kHz

    func process(samples: [Float], timestamp: TimeInterval) -> CWSignalResult
}

struct GoertzelFilter {
    let coefficient: Double  // 2 * cos(2π * k / N)
    func processSamples(_ samples: [Float]) -> Float  // Returns magnitude
}
```

#### CWSignalResult

```swift
struct CWSignalResult {
    let keyEvents: [(isDown: Bool, timestamp: TimeInterval)]
    let peakAmplitude: Float
    let isKeyDown: Bool
    let envelopeSamples: [Float]
    let isCalibrating: Bool
    let noiseFloor: Float
    let signalToNoiseRatio: Float
}
```

## Integration Points

### 1. POTA Activation Context

When opened from a POTA activation view:
- Show activation header (callsign, park, QSO count)
- Pre-fill band/mode/frequency from activation
- Logged QSOs automatically associated with activation

### 2. Quick Log Flow

```
Detect callsign → User taps "Use" → Pre-fill callsign field
                                  → Auto-detect RST from transcript
                                  → User taps "Log" → Create QSO
```

### 3. ContentView Integration

Add as sheet/modal accessible from:
- Dashboard (new "CW Assist" button)
- POTA Activation detail view
- Could also be a tab for frequent CW operators

## Settings

### CWTranscriptionSettings

```swift
struct CWTranscriptionSettings {
    var toneFrequency: Int = 600      // Hz, 400-1000 range
    var minWPM: Int = 10
    var maxWPM: Int = 40
    var noiseThreshold: Float = 0.1   // Minimum signal level
    var autoRecordSessions: Bool = false
    var hapticFeedback: Bool = true   // Vibrate on key-down
}
```

## Implementation Phases

### Phase 1: Core Audio Pipeline
- [x] AVAudioEngine microphone capture
- [x] Bandpass filter implementation (vDSP)
- [x] Envelope follower
- [x] Basic threshold detection
- [ ] Unit tests with sample audio

### Phase 2: Morse Decoder
- [x] Timing state machine
- [x] Dit/dah/space classification
- [x] Character/word assembly
- [x] Adaptive WPM estimation
- [x] Morse code lookup table

### Phase 3: Basic UI
- [x] CWTranscriptionView layout
- [x] WaveformView visualization
- [x] TranscriptView with scrolling
- [x] Start/stop controls
- [x] WPM display

### Phase 4: Callsign Detection
- [x] Callsign regex patterns
- [x] Highlight callsigns in transcript
- [x] DetectedCallsignBar with "Use" button
- [ ] QSO pattern recognition

### Phase 5: Logging Integration
- [ ] QuickLogBar with RST fields
- [ ] Create QSO from detected data
- [ ] POTA activation integration
- [ ] Session persistence (optional)

### Phase 6: Polish
- [ ] Audio recording option
- [x] Copy transcript
- [x] Settings view (WPM, tone frequency, backend selection)
- [ ] Haptic feedback
- [ ] iPad layout

### Phase 7: Alternative Backends
- [x] CWSignalProcessorProtocol for backend abstraction
- [x] GoertzelSignalProcessor implementation
- [x] Backend selection UI (segmented control + menu)
- [ ] Performance comparison/benchmarking

## Technical Considerations

### Performance
- DSP processing on background queue
- UI updates throttled to 30fps for waveform
- Transcript entries batched to avoid excessive redraws

### Accuracy Limitations
- Works best with clean sidetone audio
- Over-the-air reception will have more errors
- Manual WPM override may be needed for difficult signals
- Consider "confidence" indicator for decoded characters

### Privacy
- Requires microphone permission
- Audio data processed locally only
- Optional recording stored in app sandbox

## References

### Bandpass Filter Approach
- [cw-companion](https://github.com/cerkit/cw-companion) - macOS CW decoder
- [Apple Accelerate vDSP](https://developer.apple.com/documentation/accelerate/vdsp)
- [AVAudioEngine](https://developer.apple.com/documentation/avfaudio/avaudioengine)

### Goertzel Algorithm
- [Goertzel Algorithm - Wikipedia](https://en.wikipedia.org/wiki/Goertzel_algorithm)
- [Hackaday.io - Goertzel Algorithm](https://hackaday.io/project/180672/log/195058-getting-goertzels-algorithm-to-work)
- [CWDecoder ESP32 + Goertzel](https://github.com/Christian-ALLEGRE/CWDecoder)

### Morse Code
- [Morse Code Timing](https://morsecode.world/international/timing.html)
