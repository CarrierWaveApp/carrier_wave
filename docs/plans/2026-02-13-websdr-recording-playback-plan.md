# WebSDR Recording Playback Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add playback, scrubbing, and QSO-synced navigation for WebSDR recordings, with a compact player in activation details and a new Sessions tab in Logs.

**Architecture:** AVAudioPlayer-based playback engine with amplitude envelope scanning, shared between a compact inline player and a full-screen player. Time alignment maps QSO timestamps to recording offsets. Sessions tab in LogsContainerView groups all LoggingSessions by month.

**Tech Stack:** AVAudioPlayer, AVAudioFile, AVAssetExportSession, CADisplayLink, SwiftUI, SwiftData

**Design doc:** `docs/plans/2026-02-13-websdr-recording-playback-design.md`

**Performance rules:** NEVER use `@Query` for QSO, ServicePresence, LoggingSession, or WebSDRRecording. Use `@State` + `.task` with `FetchDescriptor` and `fetchLimit`. See `CLAUDE.md` and `docs/PERFORMANCE.md`.

**SwiftLint rules:** Files max 500 lines, function bodies max 50 lines, type bodies max 300 lines. Run `make format` before every commit. Split proactively.

**Testing:** This project uses XCTest (not Swift Testing). Tests use in-memory SwiftData via `TestModelContainer`. The user builds and runs tests — never run `xcodebuild` or `swift build` yourself.

---

## Task 1: Recording Query Helpers

Add static helpers to `WebSDRRecording` that find recordings matching a given activation or session. These are the data plumbing everything else depends on.

**Files:**
- Modify: `CarrierWave/Models/WebSDRRecording.swift`
- Test: `CarrierWaveTests/WebSDRRecordingTests.swift` (create)
- Modify: `CarrierWaveTests/Helpers/TestModelContainer.swift` (add WebSDRRecording to schema)

**Step 1: Add WebSDRRecording to test schema**

In `TestModelContainer.swift`, add `WebSDRRecording.self` to the schema array:

```swift
let schema = Schema([
    QSO.self,
    ServicePresence.self,
    UploadDestination.self,
    LoggingSession.self,
    WebSDRRecording.self,
])
```

**Step 2: Write tests for query helpers**

Create `CarrierWaveTests/WebSDRRecordingTests.swift`:

```swift
import SwiftData
import XCTest
@testable import CarrierWave

final class WebSDRRecordingTests: XCTestCase {
    var modelContainer: ModelContainer!
    var modelContext: ModelContext!

    @MainActor
    override func setUp() async throws {
        let (container, context) = try TestModelContainer.createWithContext()
        modelContainer = container
        modelContext = context
    }

    @MainActor
    override func tearDown() async throws {
        modelContext = nil
        modelContainer = nil
    }

    @MainActor
    func testFindRecordingForSession() throws {
        let sessionId = UUID()
        let recording = WebSDRRecording(
            loggingSessionId: sessionId,
            kiwisdrHost: "test.kiwisdr.com",
            kiwisdrName: "Test SDR",
            frequencyKHz: 14060,
            mode: "CW"
        )
        recording.isComplete = true
        modelContext.insert(recording)
        try modelContext.save()

        let found = try WebSDRRecording.findRecording(
            forSessionId: sessionId, in: modelContext
        )
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.kiwisdrHost, "test.kiwisdr.com")
    }

    @MainActor
    func testFindRecordingForSession_NoMatch() throws {
        let found = try WebSDRRecording.findRecording(
            forSessionId: UUID(), in: modelContext
        )
        XCTAssertNil(found)
    }

    @MainActor
    func testFindRecordingsForSessionIds() throws {
        let id1 = UUID()
        let id2 = UUID()
        let id3 = UUID()

        let rec1 = WebSDRRecording(
            loggingSessionId: id1, kiwisdrHost: "a.com",
            kiwisdrName: "A", frequencyKHz: 7030, mode: "CW"
        )
        rec1.isComplete = true

        let rec2 = WebSDRRecording(
            loggingSessionId: id2, kiwisdrHost: "b.com",
            kiwisdrName: "B", frequencyKHz: 14060, mode: "CW"
        )
        rec2.isComplete = true

        modelContext.insert(rec1)
        modelContext.insert(rec2)
        try modelContext.save()

        let found = try WebSDRRecording.findRecordings(
            forSessionIds: [id1, id2, id3], in: modelContext
        )
        XCTAssertEqual(found.count, 2)
    }
}
```

**Step 3: Ask user to run tests to verify they fail**

Ask the user to build and run tests. Expected: compile errors because `findRecording` and `findRecordings` don't exist yet.

**Step 4: Implement query helpers**

Add to `CarrierWave/Models/WebSDRRecording.swift`:

```swift
/// Find the completed recording for a specific logging session
static func findRecording(
    forSessionId sessionId: UUID, in context: ModelContext
) throws -> WebSDRRecording? {
    var descriptor = FetchDescriptor<WebSDRRecording>(
        predicate: #Predicate {
            $0.loggingSessionId == sessionId && $0.isComplete
        }
    )
    descriptor.fetchLimit = 1
    return try context.fetch(descriptor).first
}

/// Find all completed recordings matching any of the given session IDs
static func findRecordings(
    forSessionIds sessionIds: [UUID], in context: ModelContext
) throws -> [WebSDRRecording] {
    // SwiftData predicates can't use `contains` on arrays,
    // so fetch all complete recordings and filter in memory.
    // Recording count is tiny (one per session at most).
    var descriptor = FetchDescriptor<WebSDRRecording>(
        predicate: #Predicate { $0.isComplete }
    )
    descriptor.fetchLimit = 500
    let all = try context.fetch(descriptor)
    let idSet = Set(sessionIds)
    return all.filter { idSet.contains($0.loggingSessionId) }
}
```

**Step 5: Ask user to run tests to verify they pass**

**Step 6: Run `make format` and commit**

```bash
git add CarrierWave/Models/WebSDRRecording.swift \
       CarrierWaveTests/WebSDRRecordingTests.swift \
       CarrierWaveTests/Helpers/TestModelContainer.swift
git commit -m "Add WebSDRRecording query helpers for session and activation lookup"
```

---

## Task 2: RecordingPlaybackEngine — Core Playback

The audio engine that wraps AVAudioPlayer with play/pause/seek/rate and a display-link timer for currentTime updates. No amplitude scanning yet — that's Task 3.

**Files:**
- Create: `CarrierWave/Services/WebSDR/RecordingPlaybackEngine.swift`

**Step 1: Create RecordingPlaybackEngine**

Create `CarrierWave/Services/WebSDR/RecordingPlaybackEngine.swift`:

```swift
import AVFoundation
import Foundation

/// Playback engine for WebSDR recordings. Wraps AVAudioPlayer with
/// seeking, speed control, and a display-link timer for UI updates.
@MainActor
@Observable
final class RecordingPlaybackEngine: NSObject {
    // MARK: - Public State

    /// Current playback position in seconds
    private(set) var currentTime: TimeInterval = 0

    /// Total duration of the loaded recording
    private(set) var duration: TimeInterval = 0

    /// Whether audio is currently playing
    private(set) var isPlaying = false

    /// Current playback rate (0.5, 1.0, 1.5, 2.0)
    var playbackRate: Float = 1.0 {
        didSet { player?.rate = playbackRate }
    }

    /// Index of the QSO currently under the playback head (nil if none)
    private(set) var activeQSOIndex: Int?

    /// Whether a recording is loaded and ready to play
    var isLoaded: Bool { player != nil }

    // MARK: - QSO Time Alignment

    /// QSO offsets in seconds from recording start, sorted ascending
    private var qsoOffsets: [TimeInterval] = []

    /// Window before QSO timestamp to consider "active" (seconds)
    private let activeLeadIn: TimeInterval = 90

    /// Window after QSO timestamp to consider "active" (seconds)
    private let activeTrailOut: TimeInterval = 15

    // MARK: - Loading

    /// Load a recording file and prepare for playback
    func load(fileURL: URL, qsoTimestamps: [Date], recordingStart: Date) throws {
        stop()

        let audioPlayer = try AVAudioPlayer(contentsOf: fileURL)
        audioPlayer.enableRate = true
        audioPlayer.rate = playbackRate
        audioPlayer.delegate = self
        audioPlayer.prepareToPlay()

        player = audioPlayer
        duration = audioPlayer.duration
        currentTime = 0

        // Compute QSO offsets relative to recording start
        qsoOffsets = qsoTimestamps.map { timestamp in
            timestamp.timeIntervalSince(recordingStart)
        }
    }

    // MARK: - Transport Controls

    func play() {
        guard let player, !isPlaying else { return }
        player.rate = playbackRate
        player.play()
        isPlaying = true
        startDisplayLink()
    }

    func pause() {
        guard isPlaying else { return }
        player?.pause()
        isPlaying = false
        stopDisplayLink()
        updateCurrentTime()
    }

    func togglePlayPause() {
        if isPlaying { pause() } else { play() }
    }

    func stop() {
        player?.stop()
        player = nil
        isPlaying = false
        currentTime = 0
        duration = 0
        activeQSOIndex = nil
        stopDisplayLink()
    }

    /// Seek to a specific time in seconds
    func seek(to time: TimeInterval) {
        let clamped = max(0, min(time, duration))
        player?.currentTime = clamped
        currentTime = clamped
        updateActiveQSO()
    }

    /// Seek to a QSO by index (jumps to activeLeadIn before the QSO timestamp)
    func seekToQSO(at index: Int) {
        guard index >= 0, index < qsoOffsets.count else { return }
        let targetTime = max(0, qsoOffsets[index] - activeLeadIn)
        seek(to: targetTime)
    }

    /// Skip forward or backward by a number of seconds
    func skip(by seconds: TimeInterval) {
        seek(to: currentTime + seconds)
    }

    /// Jump to the next QSO relative to current position
    func nextQSO() {
        let nextIndex = qsoOffsets.firstIndex { $0 - activeLeadIn > currentTime + 1 }
        if let idx = nextIndex {
            seekToQSO(at: idx)
        }
    }

    /// Jump to the previous QSO relative to current position
    func previousQSO() {
        let prevIndex = qsoOffsets.lastIndex { $0 - activeLeadIn < currentTime - 1 }
        if let idx = prevIndex {
            seekToQSO(at: idx)
        }
    }

    // MARK: - Private

    private var player: AVAudioPlayer?
    private var displayLink: CADisplayLink?

    private func startDisplayLink() {
        stopDisplayLink()
        let link = CADisplayLink(target: self, selector: #selector(displayLinkFired))
        link.preferredFrameRateRange = CAFrameRateRange(
            minimum: 10, maximum: 15, preferred: 15
        )
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func displayLinkFired() {
        updateCurrentTime()
    }

    private func updateCurrentTime() {
        guard let player else { return }
        currentTime = player.currentTime
        updateActiveQSO()
    }

    private func updateActiveQSO() {
        // Find the QSO whose active window contains currentTime
        var bestIndex: Int?
        var bestDistance: TimeInterval = .greatestFiniteMagnitude

        for (index, offset) in qsoOffsets.enumerated() {
            let windowStart = offset - activeLeadIn
            let windowEnd = offset + activeTrailOut
            if currentTime >= windowStart, currentTime <= windowEnd {
                // Prefer the QSO closest to its timestamp
                let distance = abs(currentTime - offset)
                if distance < bestDistance {
                    bestDistance = distance
                    bestIndex = index
                }
            }
        }
        activeQSOIndex = bestIndex
    }
}

// MARK: - AVAudioPlayerDelegate

extension RecordingPlaybackEngine: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(
        _ player: AVAudioPlayer, successfully _: Bool
    ) {
        Task { @MainActor in
            self.isPlaying = false
            self.stopDisplayLink()
            self.currentTime = self.duration
        }
    }
}
```

**Step 2: Ask user to build to verify it compiles**

**Step 3: Run `make format` and commit**

```bash
git add CarrierWave/Services/WebSDR/RecordingPlaybackEngine.swift
git commit -m "Add RecordingPlaybackEngine with AVAudioPlayer playback, seeking, and QSO sync"
```

---

## Task 3: RecordingPlaybackEngine — Amplitude Envelope

Add background amplitude scanning to the engine. Reads PCM samples from the CAF file and produces a downsampled `[Float]` for waveform display.

**Files:**
- Modify: `CarrierWave/Services/WebSDR/RecordingPlaybackEngine.swift`

**Step 1: Add amplitude scanning**

Add these properties and methods to `RecordingPlaybackEngine`:

```swift
// MARK: - Amplitude Envelope

/// Downsampled amplitude envelope for waveform display (0.0 to 1.0)
private(set) var amplitudeEnvelope: [Float] = []

/// Whether the amplitude envelope is still being computed
private(set) var isLoadingAmplitude = false

/// Scan the audio file and compute amplitude envelope on a background task.
/// Call after load(). Each sample represents 0.5 seconds of audio.
func scanAmplitude(fileURL: URL) {
    isLoadingAmplitude = true
    let sampleWindowSeconds: Double = 0.5

    Task.detached(priority: .utility) { [weak self] in
        let envelope = Self.computeEnvelope(
            fileURL: fileURL, windowSeconds: sampleWindowSeconds
        )
        await MainActor.run {
            self?.amplitudeEnvelope = envelope
            self?.isLoadingAmplitude = false
        }
    }
}

/// Compute peak amplitude envelope from a CAF/audio file.
/// Returns one float (0.0-1.0) per window of `windowSeconds`.
private static func computeEnvelope(
    fileURL: URL, windowSeconds: Double
) -> [Float] {
    guard let audioFile = try? AVAudioFile(forReading: fileURL) else {
        return []
    }

    let sampleRate = audioFile.processingFormat.sampleRate
    let totalFrames = AVAudioFrameCount(audioFile.length)
    let windowFrames = AVAudioFrameCount(sampleRate * windowSeconds)

    guard windowFrames > 0 else { return [] }

    // Read into a float buffer for peak detection
    guard let format = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: sampleRate,
        channels: 1,
        interleaved: true
    ) else {
        return []
    }

    var envelope: [Float] = []
    let bufferCapacity = min(windowFrames, 65_536)

    guard let buffer = AVAudioPCMBuffer(
        pcmFormat: format, frameCapacity: bufferCapacity
    ) else {
        return []
    }

    var framesRemaining = totalFrames
    while framesRemaining > 0 {
        let framesToRead = min(bufferCapacity, framesRemaining)
        buffer.frameLength = 0

        do {
            try audioFile.read(into: buffer, frameCount: framesToRead)
        } catch {
            break
        }

        guard let channelData = buffer.floatChannelData?[0] else { break }
        let count = Int(buffer.frameLength)

        // Process in windowFrames-sized chunks
        var offset = 0
        while offset < count {
            let end = min(offset + Int(windowFrames), count)
            var peak: Float = 0
            for i in offset ..< end {
                let abs = Swift.abs(channelData[i])
                if abs > peak { peak = abs }
            }
            envelope.append(peak)
            offset = end
        }

        framesRemaining -= AVAudioFrameCount(count)
    }

    return envelope
}
```

**Step 2: Call `scanAmplitude` from `load()`**

At the end of the `load()` method, add:

```swift
scanAmplitude(fileURL: fileURL)
```

**Step 3: Ask user to build to verify it compiles**

**Step 4: Run `make format` and commit**

```bash
git add CarrierWave/Services/WebSDR/RecordingPlaybackEngine.swift
git commit -m "Add amplitude envelope scanning for waveform display"
```

---

## Task 4: RecordingWaveformView

Reusable SwiftUI view that draws the amplitude waveform with QSO markers, a playback head, and optional drag-to-seek. Used by both the compact and full-screen player.

**Files:**
- Create: `CarrierWave/Views/RecordingPlayer/RecordingWaveformView.swift`

**Step 1: Create the waveform view**

Create directory `CarrierWave/Views/RecordingPlayer/` and file `RecordingWaveformView.swift`:

```swift
import SwiftUI

/// Amplitude waveform visualization with QSO markers and playback head.
/// Reused in both compact and full-screen recording players.
struct RecordingWaveformView: View {
    /// Amplitude samples (0.0 to 1.0)
    let amplitudes: [Float]

    /// Total duration of the recording in seconds
    let duration: TimeInterval

    /// Current playback position in seconds
    let currentTime: TimeInterval

    /// QSO offsets from recording start, in seconds
    let qsoOffsets: [TimeInterval]

    /// Index of the currently active QSO (nil if none)
    let activeQSOIndex: Int?

    /// Height of the waveform
    var height: CGFloat = 40

    /// Whether drag-to-seek is enabled
    var seekable: Bool = false

    /// Called when user drags to seek (time in seconds)
    var onSeek: ((TimeInterval) -> Void)?

    /// Optional callsign labels for QSO markers (must match qsoOffsets count)
    var qsoCallsigns: [String]?

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width

            ZStack(alignment: .leading) {
                // Amplitude bars
                amplitudeBars(width: width)

                // QSO markers
                ForEach(Array(qsoOffsets.enumerated()), id: \.offset) { index, offset in
                    qsoMarker(
                        at: offset, index: index, width: width
                    )
                }

                // Playback head
                playbackHead(width: width)
            }
            .frame(height: height)
            .contentShape(Rectangle())
            .gesture(seekable ? seekGesture(width: width) : nil)
        }
        .frame(height: height)
    }

    // MARK: - Subviews

    private func amplitudeBars(width: CGFloat) -> some View {
        HStack(alignment: .center, spacing: 1) {
            ForEach(Array(amplitudes.enumerated()), id: \.offset) { _, amp in
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.accentColor.opacity(0.6))
                    .frame(height: max(2, height * CGFloat(amp)))
            }
        }
        .frame(width: width, height: height)
    }

    private func qsoMarker(
        at offset: TimeInterval, index: Int, width: CGFloat
    ) -> some View {
        let x = xPosition(for: offset, in: width)
        let isActive = index == activeQSOIndex

        return Rectangle()
            .fill(isActive ? Color.accentColor : Color.secondary.opacity(0.5))
            .frame(width: isActive ? 2 : 1, height: height)
            .position(x: x, y: height / 2)
    }

    private func playbackHead(width: CGFloat) -> some View {
        let x = xPosition(for: currentTime, in: width)

        return Rectangle()
            .fill(Color.primary)
            .frame(width: 2, height: height + 4)
            .position(x: x, y: height / 2)
    }

    // MARK: - Helpers

    private func xPosition(for time: TimeInterval, in width: CGFloat) -> CGFloat {
        guard duration > 0 else { return 0 }
        let fraction = CGFloat(time / duration)
        return max(0, min(width, fraction * width))
    }

    private func seekGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let fraction = max(0, min(1, value.location.x / width))
                let time = TimeInterval(fraction) * duration
                onSeek?(time)
            }
    }
}
```

**Step 2: Ask user to build to verify it compiles**

**Step 3: Run `make format` and commit**

```bash
git add CarrierWave/Views/RecordingPlayer/RecordingWaveformView.swift
git commit -m "Add RecordingWaveformView with amplitude bars, QSO markers, and seek gesture"
```

---

## Task 5: CompactRecordingPlayer

Inline card view for activation detail and sessions list. Shows mini waveform, play/pause, time labels, receiver info.

**Files:**
- Create: `CarrierWave/Views/RecordingPlayer/CompactRecordingPlayer.swift`

**Step 1: Create the compact player view**

```swift
import SwiftUI

/// Compact inline recording player shown in activation detail and sessions list.
/// Tapping navigates to the full-screen RecordingPlayerView.
struct CompactRecordingPlayer: View {
    let recording: WebSDRRecording
    let qsos: [QSO]
    @Bindable var engine: RecordingPlaybackEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            headerRow
            waveformSection
            receiverInfoRow
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .task {
            await loadIfNeeded()
        }
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack {
            Image(systemName: "waveform.circle.fill")
                .foregroundStyle(.red)
            Text("Recording")
                .font(.subheadline)
                .fontWeight(.medium)

            Spacer()

            Button {
                engine.togglePlayPause()
            } label: {
                Image(
                    systemName: engine.isPlaying
                        ? "pause.circle.fill" : "play.circle.fill"
                )
                .font(.title2)
            }
            .buttonStyle(.borderless)

            Text(formatTime(engine.currentTime))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Waveform

    private var waveformSection: some View {
        RecordingWaveformView(
            amplitudes: engine.amplitudeEnvelope,
            duration: engine.duration,
            currentTime: engine.currentTime,
            qsoOffsets: qsoOffsets,
            activeQSOIndex: engine.activeQSOIndex,
            height: 40,
            seekable: true,
            onSeek: { time in engine.seek(to: time) }
        )
    }

    // MARK: - Receiver Info

    private var receiverInfoRow: some View {
        HStack(spacing: 8) {
            Text(recording.kiwisdrName)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(formatFrequency(recording.frequencyKHz))
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(recording.mode)
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Text(recording.formattedDuration)
                .font(.caption)
                .foregroundStyle(.secondary)

            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Helpers

    private var qsoOffsets: [TimeInterval] {
        let start = recording.startedAt
        return qsos.map { $0.timestamp.timeIntervalSince(start) }
    }

    private func loadIfNeeded() async {
        guard !engine.isLoaded, let fileURL = recording.fileURL else { return }
        let timestamps = qsos.sorted { $0.timestamp < $1.timestamp }
            .map(\.timestamp)
        try? engine.load(
            fileURL: fileURL,
            qsoTimestamps: timestamps,
            recordingStart: recording.startedAt
        )
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let h = total / 3_600
        let m = (total % 3_600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }

    private func formatFrequency(_ kHz: Double) -> String {
        let mHz = kHz / 1_000
        if mHz == mHz.rounded() {
            return String(format: "%.0f MHz", mHz)
        }
        return String(format: "%.3f MHz", mHz)
    }
}
```

**Step 2: Ask user to build to verify it compiles**

**Step 3: Run `make format` and commit**

```bash
git add CarrierWave/Views/RecordingPlayer/CompactRecordingPlayer.swift
git commit -m "Add CompactRecordingPlayer inline card with waveform and playback controls"
```

---

## Task 6: RecordingPlayerView — Full-Screen Player

The main playback experience with large waveform, transport controls, speed picker, and synced QSO list.

**Files:**
- Create: `CarrierWave/Views/RecordingPlayer/RecordingPlayerView.swift`

**Step 1: Create the full-screen player view**

```swift
import SwiftUI

/// Full-screen recording player with waveform scrubber, transport controls,
/// speed selector, and QSO list with bidirectional sync.
struct RecordingPlayerView: View {
    let recording: WebSDRRecording
    let qsos: [QSO]
    @Bindable var engine: RecordingPlaybackEngine

    var body: some View {
        VStack(spacing: 0) {
            headerSection
                .padding(.horizontal)
                .padding(.top, 8)

            waveformSection
                .padding(.horizontal)
                .padding(.top, 16)

            timeLabelsRow
                .padding(.horizontal)

            transportControls
                .padding(.top, 16)

            speedPicker
                .padding(.top, 12)

            Divider()
                .padding(.top, 16)

            qsoList
        }
        .navigationTitle("Recording")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadIfNeeded()
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(recording.kiwisdrName)
                .font(.headline)
            HStack(spacing: 8) {
                Text(formatFrequency(recording.frequencyKHz))
                Text(recording.mode)
                Text(recording.startedAt.formatted(
                    date: .abbreviated, time: .shortened
                ))
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Waveform

    private var waveformSection: some View {
        RecordingWaveformView(
            amplitudes: engine.amplitudeEnvelope,
            duration: engine.duration,
            currentTime: engine.currentTime,
            qsoOffsets: qsoOffsets,
            activeQSOIndex: engine.activeQSOIndex,
            height: 80,
            seekable: true,
            onSeek: { time in engine.seek(to: time) },
            qsoCallsigns: sortedQSOs.map(\.callsign)
        )
    }

    // MARK: - Time Labels

    private var timeLabelsRow: some View {
        HStack {
            Text(formatUTCTime(engine.currentTime))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Spacer()
            Text(formatUTCTime(engine.duration))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Transport

    private var transportControls: some View {
        HStack(spacing: 24) {
            Button { engine.previousQSO() } label: {
                Image(systemName: "backward.end.fill")
                    .font(.title3)
            }

            Button { engine.skip(by: -15) } label: {
                Image(systemName: "gobackward.15")
                    .font(.title2)
            }

            Button { engine.togglePlayPause() } label: {
                Image(
                    systemName: engine.isPlaying
                        ? "pause.circle.fill" : "play.circle.fill"
                )
                .font(.largeTitle)
            }

            Button { engine.skip(by: 15) } label: {
                Image(systemName: "goforward.15")
                    .font(.title2)
            }

            Button { engine.nextQSO() } label: {
                Image(systemName: "forward.end.fill")
                    .font(.title3)
            }
        }
        .buttonStyle(.borderless)
    }

    // MARK: - Speed Picker

    @State private var selectedRate: Float = 1.0

    private var speedPicker: some View {
        HStack(spacing: 0) {
            ForEach([Float(0.5), 1.0, 1.5, 2.0], id: \.self) { rate in
                Button {
                    selectedRate = rate
                    engine.playbackRate = rate
                } label: {
                    Text(rate == 1.0 ? "1x" : String(format: "%.1fx", rate))
                        .font(.caption)
                        .fontWeight(selectedRate == rate ? .bold : .regular)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            selectedRate == rate
                                ? Color.accentColor.opacity(0.15)
                                : Color.clear
                        )
                        .clipShape(Capsule())
                }
                .buttonStyle(.borderless)
            }
        }
    }

    // MARK: - QSO List

    private var qsoList: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(
                    Array(sortedQSOs.enumerated()), id: \.element.id
                ) { index, qso in
                    qsoRow(qso, index: index)
                        .id(qso.id)
                        .onTapGesture {
                            engine.seekToQSO(at: index)
                        }
                }
            }
            .listStyle(.plain)
            .onChange(of: engine.activeQSOIndex) { _, newIndex in
                if let idx = newIndex, idx < sortedQSOs.count {
                    withAnimation {
                        proxy.scrollTo(sortedQSOs[idx].id, anchor: .center)
                    }
                }
            }
        }
    }

    private func qsoRow(_ qso: QSO, index: Int) -> some View {
        let isActive = index == engine.activeQSOIndex

        return HStack(spacing: 8) {
            if isActive {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.caption)
                    .foregroundStyle(.accentColor)
            } else {
                Text(formatQSOTime(qso.timestamp))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Text(qso.callsign)
                .font(.subheadline)
                .fontWeight(isActive ? .bold : .regular)

            Spacer()

            if let rst = qso.rstSent {
                Text(rst)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(qso.band)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(qso.mode)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .listRowBackground(
            isActive ? Color.accentColor.opacity(0.1) : nil
        )
    }

    // MARK: - Helpers

    private var sortedQSOs: [QSO] {
        qsos.sorted { $0.timestamp < $1.timestamp }
    }

    private var qsoOffsets: [TimeInterval] {
        let start = recording.startedAt
        return sortedQSOs.map { $0.timestamp.timeIntervalSince(start) }
    }

    private func loadIfNeeded() async {
        guard !engine.isLoaded, let fileURL = recording.fileURL else { return }
        let timestamps = sortedQSOs.map(\.timestamp)
        try? engine.load(
            fileURL: fileURL,
            qsoTimestamps: timestamps,
            recordingStart: recording.startedAt
        )
    }

    private func formatUTCTime(_ offset: TimeInterval) -> String {
        let date = recording.startedAt.addingTimeInterval(offset)
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date) + "z"
    }

    private func formatQSOTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date) + "z"
    }

    private func formatFrequency(_ kHz: Double) -> String {
        let mHz = kHz / 1_000
        if mHz == mHz.rounded() {
            return String(format: "%.0f MHz", mHz)
        }
        return String(format: "%.3f MHz", mHz)
    }
}
```

**Step 2: Check line count** — this file will be close to the limit. If over 400 lines, extract the QSO list section into a separate `RecordingPlayerQSOList.swift`.

**Step 3: Ask user to build to verify it compiles**

**Step 4: Run `make format` and commit**

```bash
git add CarrierWave/Views/RecordingPlayer/RecordingPlayerView.swift
git commit -m "Add RecordingPlayerView full-screen player with transport, speed, and QSO sync"
```

---

## Task 7: Integrate Compact Player into POTAActivationDetailView

Wire the compact player into the activation detail when a recording exists for the activation's session.

**Files:**
- Modify: `CarrierWave/Views/POTAActivations/POTAActivationDetailView.swift`

**Step 1: Add recording state and lookup**

Add to `POTAActivationDetailView` private properties:

```swift
@State private var recording: WebSDRRecording?
@State private var engine = RecordingPlaybackEngine()
@Environment(\.modelContext) private var modelContext
```

Add a `.task` to the existing body to look up the recording:

```swift
.task {
    await loadRecording()
}
```

Add the helper method:

```swift
private func loadRecording() async {
    // Find sessions matching this activation's park + date
    let parkRef = activation.parkReference
    let activationDate = activation.utcDate

    let calendar = Calendar.current
    let startOfDay = calendar.startOfDay(for: activationDate)
    let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay

    var sessionDescriptor = FetchDescriptor<LoggingSession>(
        predicate: #Predicate {
            $0.parkReference == parkRef
                && $0.startedAt >= startOfDay
                && $0.startedAt < endOfDay
        }
    )
    sessionDescriptor.fetchLimit = 10

    guard let sessions = try? modelContext.fetch(sessionDescriptor) else { return }
    let sessionIds = sessions.map(\.id)

    let recordings = (try? WebSDRRecording.findRecordings(
        forSessionIds: sessionIds, in: modelContext
    )) ?? []

    recording = recordings.first
}
```

**Step 2: Add recording section to the body**

In the `List` inside `body`, add after `activationInfoSection`:

```swift
if let recording {
    Section {
        NavigationLink {
            RecordingPlayerView(
                recording: recording,
                qsos: activation.qsos,
                engine: engine
            )
        } label: {
            CompactRecordingPlayer(
                recording: recording,
                qsos: activation.qsos,
                engine: engine
            )
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
    }
}
```

**Step 3: Ask user to build and manually test with an activation that has a recording**

**Step 4: Run `make format` and commit**

```bash
git add CarrierWave/Views/POTAActivations/POTAActivationDetailView.swift
git commit -m "Integrate compact recording player into POTA activation detail view"
```

---

## Task 8: Clip Export

Add the ability to export a time-range clip from a recording as M4A for sharing.

**Files:**
- Create: `CarrierWave/Services/WebSDR/RecordingClipExporter.swift`

**Step 1: Create the clip exporter**

```swift
import AVFoundation
import Foundation

/// Exports a time-range clip from a WebSDR recording as M4A.
enum RecordingClipExporter {
    /// Export a clip from sourceURL between startTime and endTime.
    /// Returns the URL of the exported M4A file in a temp directory.
    static func exportClip(
        sourceURL: URL,
        startTime: TimeInterval,
        endTime: TimeInterval
    ) async throws -> URL {
        let asset = AVURLAsset(url: sourceURL)
        let duration = try await asset.load(.duration)
        let totalSeconds = CMTimeGetSeconds(duration)

        let clampedStart = max(0, startTime)
        let clampedEnd = min(totalSeconds, endTime)

        guard clampedEnd > clampedStart else {
            throw ClipExportError.invalidRange
        }

        let startCMTime = CMTime(seconds: clampedStart, preferredTimescale: 44_100)
        let endCMTime = CMTime(seconds: clampedEnd, preferredTimescale: 44_100)
        let timeRange = CMTimeRange(start: startCMTime, end: endCMTime)

        guard let session = AVAssetExportSession(
            asset: asset, presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw ClipExportError.exportSessionFailed
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("clip-\(UUID().uuidString).m4a")

        session.outputURL = outputURL
        session.outputFileType = .m4a
        session.timeRange = timeRange

        await session.export()

        guard session.status == .completed else {
            throw ClipExportError.exportFailed(
                session.error?.localizedDescription ?? "Unknown error"
            )
        }

        return outputURL
    }
}

enum ClipExportError: Error, LocalizedError {
    case invalidRange
    case exportSessionFailed
    case exportFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidRange:
            "Invalid time range for clip export"
        case .exportSessionFailed:
            "Could not create export session"
        case let .exportFailed(msg):
            "Export failed: \(msg)"
        }
    }
}
```

**Step 2: Ask user to build to verify it compiles**

**Step 3: Run `make format` and commit**

```bash
git add CarrierWave/Services/WebSDR/RecordingClipExporter.swift
git commit -m "Add RecordingClipExporter for M4A clip export from recordings"
```

---

## Task 9: RecordingPlayerView+Actions (Trim & Share)

Add trim and share clip UI to the full-screen player.

**Files:**
- Create: `CarrierWave/Views/RecordingPlayer/RecordingPlayerView+Actions.swift`

**Step 1: Create the actions extension**

This file adds a share clip sheet and trim sheet to RecordingPlayerView. The sheets use the waveform with draggable range handles.

```swift
import SwiftUI

// MARK: - Share Clip Sheet

/// Sheet for selecting a time range and exporting a clip
struct ShareClipSheet: View {
    let recording: WebSDRRecording
    let engine: RecordingPlaybackEngine
    let qsos: [QSO]
    @Environment(\.dismiss) private var dismiss

    @State private var rangeStart: TimeInterval = 0
    @State private var rangeEnd: TimeInterval = 0
    @State private var isExporting = false
    @State private var exportedURL: URL?
    @State private var exportError: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Select clip range")
                    .font(.headline)

                RecordingWaveformView(
                    amplitudes: engine.amplitudeEnvelope,
                    duration: engine.duration,
                    currentTime: engine.currentTime,
                    qsoOffsets: [],
                    activeQSOIndex: nil,
                    height: 60,
                    seekable: false
                )
                .overlay {
                    rangeOverlay
                }
                .padding(.horizontal)

                HStack {
                    Text(formatTime(rangeStart))
                    Spacer()
                    Text(formatTime(rangeEnd))
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .padding(.horizontal)

                durationLabel

                if let error = exportError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                if let url = exportedURL {
                    ShareLink(item: url) {
                        Label("Share Clip", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button {
                        Task { await exportClip() }
                    } label: {
                        if isExporting {
                            ProgressView()
                        } else {
                            Label("Export Clip", systemImage: "scissors")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isExporting)
                }
            }
            .padding()
            .navigationTitle("Share Clip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear { setDefaultRange() }
        }
    }

    private var rangeOverlay: some View {
        GeometryReader { geo in
            let startX = xPos(rangeStart, in: geo.size.width)
            let endX = xPos(rangeEnd, in: geo.size.width)

            // Dimmed regions outside range
            HStack(spacing: 0) {
                Rectangle()
                    .fill(Color.black.opacity(0.3))
                    .frame(width: startX)
                Spacer()
                Rectangle()
                    .fill(Color.black.opacity(0.3))
                    .frame(width: geo.size.width - endX)
            }
        }
    }

    private var durationLabel: some View {
        let clipDuration = rangeEnd - rangeStart
        return Text("Clip: \(formatTime(clipDuration))")
            .font(.subheadline)
    }

    private func setDefaultRange() {
        if let activeIdx = engine.activeQSOIndex {
            let sortedQSOs = qsos.sorted { $0.timestamp < $1.timestamp }
            if activeIdx < sortedQSOs.count {
                let offset = sortedQSOs[activeIdx].timestamp
                    .timeIntervalSince(recording.startedAt)
                rangeStart = max(0, offset - 90)
                rangeEnd = min(engine.duration, offset + 15)
                return
            }
        }
        rangeStart = 0
        rangeEnd = min(60, engine.duration)
    }

    private func exportClip() async {
        guard let fileURL = recording.fileURL else { return }
        isExporting = true
        exportError = nil

        do {
            let url = try await RecordingClipExporter.exportClip(
                sourceURL: fileURL,
                startTime: rangeStart,
                endTime: rangeEnd
            )
            exportedURL = url
        } catch {
            exportError = error.localizedDescription
        }

        isExporting = false
    }

    private func xPos(_ time: TimeInterval, in width: CGFloat) -> CGFloat {
        guard engine.duration > 0 else { return 0 }
        return CGFloat(time / engine.duration) * width
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}
```

**Step 2: Add share clip button to RecordingPlayerView**

Add `@State private var showShareClip = false` to RecordingPlayerView, then add after the QSO list:

```swift
.safeAreaInset(edge: .bottom) {
    HStack(spacing: 16) {
        Button {
            showShareClip = true
        } label: {
            Label("Share Clip", systemImage: "scissors")
        }
        .buttonStyle(.bordered)
    }
    .padding()
    .background(.bar)
}
.sheet(isPresented: $showShareClip) {
    ShareClipSheet(
        recording: recording,
        engine: engine,
        qsos: qsos
    )
    .presentationDetents([.medium])
}
```

**Step 3: Ask user to build to verify it compiles**

**Step 4: Run `make format` and commit**

```bash
git add CarrierWave/Views/RecordingPlayer/RecordingPlayerView+Actions.swift \
       CarrierWave/Views/RecordingPlayer/RecordingPlayerView.swift
git commit -m "Add share clip sheet with range selection and M4A export"
```

---

## Task 10: Sessions Tab

Add the "Sessions" segment to `LogsContainerView` with a `SessionsView` that lists all logging sessions grouped by month.

**Files:**
- Modify: `CarrierWave/Views/Logs/LogsContainerView.swift`
- Create: `CarrierWave/Views/Sessions/SessionsView.swift`
- Create: `CarrierWave/Views/Sessions/SessionDetailView.swift`

**Step 1: Add sessions segment to LogsContainerView**

In `LogsContainerView.swift`, add to the `LogsSegment` enum:

```swift
case sessions = "Sessions"
```

Add to the `selectedContent` switch:

```swift
case .sessions:
    SessionsView()
```

**Step 2: Create SessionsView**

Create `CarrierWave/Views/Sessions/SessionsView.swift`:

```swift
import SwiftData
import SwiftUI

/// Lists all completed logging sessions grouped by month.
/// Sessions with WebSDR recordings show a mini waveform and recording badge.
struct SessionsView: View {
    var body: some View {
        Group {
            if sessions.isEmpty {
                emptyState
            } else {
                sessionsList
            }
        }
        .navigationTitle("Sessions")
        .task {
            await loadSessions()
            await loadRecordings()
        }
    }

    // MARK: - Private

    @Environment(\.modelContext) private var modelContext
    @State private var sessions: [LoggingSession] = []
    @State private var recordingsBySessionId: [UUID: WebSDRRecording] = [:]
    @State private var engines: [UUID: RecordingPlaybackEngine] = [:]

    private var sessionsByMonth: [(month: String, sessions: [LoggingSession])] {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        formatter.timeZone = TimeZone(identifier: "UTC")

        let grouped = Dictionary(grouping: sessions) { session in
            formatter.string(from: session.startedAt)
        }

        return grouped
            .sorted { $0.value[0].startedAt > $1.value[0].startedAt }
            .map { (month: $0.key, sessions: $0.value) }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No Sessions",
            systemImage: "clock",
            description: Text(
                "Completed logging sessions will appear here."
            )
        )
    }

    private var sessionsList: some View {
        List {
            ForEach(sessionsByMonth, id: \.month) { group in
                Section(group.month) {
                    ForEach(group.sessions, id: \.id) { session in
                        sessionRow(session)
                    }
                }
            }
        }
    }

    private func sessionRow(_ session: LoggingSession) -> some View {
        let recording = recordingsBySessionId[session.id]
        let hasRecording = recording != nil

        return NavigationLink {
            if let recording {
                RecordingPlayerView(
                    recording: recording,
                    qsos: [], // Loaded by detail view
                    engine: engineFor(session.id)
                )
            } else {
                SessionDetailView(session: session)
            }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: session.activationType.icon)
                        .foregroundStyle(.secondary)
                    Text(session.displayTitle)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    Spacer()
                    Text(session.startedAt.formatted(
                        date: .abbreviated, time: .omitted
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    Text("\(session.qsoCount) QSO\(session.qsoCount == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(session.formattedDuration)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if hasRecording {
                        Label("Recording", systemImage: "waveform.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func engineFor(_ sessionId: UUID) -> RecordingPlaybackEngine {
        if let existing = engines[sessionId] {
            return existing
        }
        let engine = RecordingPlaybackEngine()
        engines[sessionId] = engine
        return engine
    }

    private func loadSessions() async {
        var descriptor = FetchDescriptor<LoggingSession>(
            predicate: #Predicate { $0.statusRawValue == "completed" },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 200

        sessions = (try? modelContext.fetch(descriptor)) ?? []
    }

    private func loadRecordings() async {
        let sessionIds = sessions.map(\.id)
        guard !sessionIds.isEmpty else { return }

        let recordings = (try? WebSDRRecording.findRecordings(
            forSessionIds: sessionIds, in: modelContext
        )) ?? []

        var dict: [UUID: WebSDRRecording] = [:]
        for recording in recordings {
            dict[recording.loggingSessionId] = recording
        }
        recordingsBySessionId = dict
    }
}
```

**Step 3: Create SessionDetailView**

Create `CarrierWave/Views/Sessions/SessionDetailView.swift`:

```swift
import SwiftData
import SwiftUI

/// Simple detail view for sessions without recordings.
/// Shows session metadata and QSO list.
struct SessionDetailView: View {
    let session: LoggingSession

    var body: some View {
        List {
            infoSection
            qsoSection
        }
        .navigationTitle(session.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadQSOs()
        }
    }

    // MARK: - Private

    @Environment(\.modelContext) private var modelContext
    @State private var qsos: [QSO] = []

    private var infoSection: some View {
        Section("Session Info") {
            LabeledContent("Type", value: session.activationType.displayName)

            if let freq = session.frequency {
                LabeledContent("Frequency") {
                    Text(String(format: "%.3f MHz", freq))
                }
            }

            LabeledContent("Mode", value: session.mode)

            LabeledContent("Duration", value: session.formattedDuration)

            if let ref = session.activationReference {
                LabeledContent("Reference", value: ref)
            }

            if let grid = session.myGrid {
                LabeledContent("Grid", value: grid)
            }
        }
    }

    private var qsoSection: some View {
        Section("\(qsos.count) QSO\(qsos.count == 1 ? "" : "s")") {
            ForEach(qsos.sorted { $0.timestamp > $1.timestamp }) { qso in
                HStack {
                    Text(qso.callsign)
                        .font(.subheadline)
                    Spacer()
                    Text(qso.band)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(qso.mode)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(qso.timestamp.formatted(date: .omitted, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func loadQSOs() async {
        let sessionStart = session.startedAt
        let sessionEnd = session.endedAt ?? Date()
        let callsign = session.myCallsign

        var descriptor = FetchDescriptor<QSO>(
            predicate: #Predicate {
                $0.myCallsign == callsign
                    && $0.timestamp >= sessionStart
                    && $0.timestamp <= sessionEnd
                    && !$0.isHidden
            },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = 500

        qsos = (try? modelContext.fetch(descriptor)) ?? []
    }
}
```

**Step 4: Ask user to build and test the new Sessions tab**

**Step 5: Run `make format` and commit**

```bash
git add CarrierWave/Views/Logs/LogsContainerView.swift \
       CarrierWave/Views/Sessions/SessionsView.swift \
       CarrierWave/Views/Sessions/SessionDetailView.swift
git commit -m "Add Sessions tab with month-grouped session history and recording indicators"
```

---

## Task 11: Update FILE_INDEX.md

Add all new files to the file index.

**Files:**
- Modify: `docs/FILE_INDEX.md`

**Step 1: Add new entries**

Add a new section for the recording player views and add the new service files:

Under **Services - WebSDR**:

| File | Purpose |
|------|---------|
| `RecordingPlaybackEngine.swift` | @Observable AVAudioPlayer wrapper with amplitude scanning, seeking, speed control |
| `RecordingClipExporter.swift` | M4A clip export for sharing time-range clips from recordings |

Add a new section **Views - Recording Player (`CarrierWave/Views/RecordingPlayer/`)**:

| File | Purpose |
|------|---------|
| `RecordingWaveformView.swift` | Reusable amplitude waveform with QSO markers, playback head, drag-to-seek |
| `CompactRecordingPlayer.swift` | Inline card for activation detail / sessions list |
| `RecordingPlayerView.swift` | Full-screen player with transport, speed picker, and synced QSO list |
| `RecordingPlayerView+Actions.swift` | Share clip sheet with range selection and M4A export |

Add a new section **Views - Sessions (`CarrierWave/Views/Sessions/`)**:

| File | Purpose |
|------|---------|
| `SessionsView.swift` | Sessions list with month grouping and recording previews |
| `SessionDetailView.swift` | Non-POTA session detail (metadata, QSO list) |

**Step 2: Commit**

```bash
git add docs/FILE_INDEX.md
git commit -m "Update FILE_INDEX.md with recording player and sessions files"
```

---

## Task 12: Update CHANGELOG.md

**Step 1: Add entries under [Unreleased]**

```markdown
### Added
- Add WebSDR recording playback with amplitude waveform visualization and scrubbing
- Add bidirectional QSO-to-audio sync (scrubbing highlights QSOs, tapping QSOs seeks audio)
- Add playback speed control (0.5x, 1.0x, 1.5x, 2.0x)
- Add audio clip export for sharing specific QSO segments
- Add compact recording player in POTA activation detail view
- Add Sessions tab in Logs showing all logging sessions with recording indicators
```

**Step 2: Commit**

```bash
git add CHANGELOG.md
git commit -m "Update CHANGELOG with WebSDR recording playback features"
```

---

## Summary

| Task | Description | New Files | Modified Files |
|------|-------------|-----------|----------------|
| 1 | Recording query helpers + tests | `WebSDRRecordingTests.swift` | `WebSDRRecording.swift`, `TestModelContainer.swift` |
| 2 | Playback engine core | `RecordingPlaybackEngine.swift` | — |
| 3 | Amplitude envelope scanning | — | `RecordingPlaybackEngine.swift` |
| 4 | Waveform view | `RecordingWaveformView.swift` | — |
| 5 | Compact player | `CompactRecordingPlayer.swift` | — |
| 6 | Full-screen player | `RecordingPlayerView.swift` | — |
| 7 | Activation detail integration | — | `POTAActivationDetailView.swift` |
| 8 | Clip exporter | `RecordingClipExporter.swift` | — |
| 9 | Share clip UI | `RecordingPlayerView+Actions.swift` | `RecordingPlayerView.swift` |
| 10 | Sessions tab | `SessionsView.swift`, `SessionDetailView.swift` | `LogsContainerView.swift` |
| 11 | File index update | — | `FILE_INDEX.md` |
| 12 | Changelog update | — | `CHANGELOG.md` |
