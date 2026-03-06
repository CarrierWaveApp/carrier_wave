import AVFoundation
import CarrierWaveData
import Foundation

// MARK: - RecordingPlaybackEngine

/// Playback engine for WebSDR recordings. Wraps AVAudioPlayer with
/// seeking, speed control, and a timer for UI updates.
@MainActor
@Observable
final class RecordingPlaybackEngine: NSObject {
    // MARK: Internal

    /// Current playback position in seconds
    private(set) var currentTime: TimeInterval = 0

    /// Total duration of the loaded recording
    private(set) var duration: TimeInterval = 0

    /// Whether audio is currently playing
    private(set) var isPlaying = false

    /// Index of the QSO currently under the playback head
    private(set) var activeQSOIndex: Int?

    /// Index of the recording segment currently under the playback head
    private(set) var activeSegmentIndex: Int = 0

    /// Computed time ranges for each QSO
    var qsoRanges: [(start: TimeInterval, end: TimeInterval)] = []

    /// Loaded transcript (nil if none available)
    var transcript: SDRRecordingTranscript?

    /// Currently active transcript line index
    var activeTranscriptLineIndex: Int?

    /// Currently active transcript word index within the active line
    var activeTranscriptWordIndex: Int?

    /// Downsampled amplitude envelope for waveform display (0.0 to 1.0)
    private(set) var amplitudeEnvelope: [Float] = []

    /// Whether the amplitude envelope is still being computed
    private(set) var isLoadingAmplitude = false

    /// Recording segments with frequency/mode metadata
    private(set) var segments: [SDRRecordingSegment] = []

    /// QSO offsets in seconds from recording start, sorted ascending
    var qsoOffsets: [TimeInterval] = []

    /// Window before QSO timestamp to consider "active"
    let activeLeadIn: TimeInterval = 90

    /// Window after QSO timestamp to consider "active"
    let activeTrailOut: TimeInterval = 15

    /// Current playback rate (0.5, 1.0, 1.5, 2.0)
    var playbackRate: Float = 1.0 {
        didSet { player?.rate = playbackRate }
    }

    var isLoaded: Bool {
        player != nil
    }

    var activeSegment: SDRRecordingSegment? {
        guard !segments.isEmpty, activeSegmentIndex < segments.count else {
            return nil
        }
        return segments[activeSegmentIndex]
    }

    // MARK: - Loading

    func load(
        fileURL: URL,
        qsoTimestamps: [Date],
        recordingStart: Date,
        segments: [SDRRecordingSegment] = []
    ) throws {
        stop()

        let audioPlayer = try AVAudioPlayer(contentsOf: fileURL)
        audioPlayer.enableRate = true
        audioPlayer.rate = playbackRate
        audioPlayer.delegate = self
        audioPlayer.prepareToPlay()

        player = audioPlayer
        duration = audioPlayer.duration
        currentTime = 0
        self.segments = segments

        qsoOffsets = qsoTimestamps.map { timestamp in
            timestamp.timeIntervalSince(recordingStart)
        }

        computeQSORanges()
        scanAmplitude(fileURL: fileURL)
    }

    // MARK: - Transport Controls

    func play() {
        guard let player, !isPlaying else {
            return
        }
        player.rate = playbackRate
        player.play()
        isPlaying = true
        startUpdateTimer()
    }

    func pause() {
        guard isPlaying else {
            return
        }
        player?.pause()
        isPlaying = false
        stopUpdateTimer()
        updateCurrentTime()
    }

    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    func stop() {
        player?.stop()
        player = nil
        isPlaying = false
        currentTime = 0
        duration = 0
        activeQSOIndex = nil
        activeSegmentIndex = 0
        qsoRanges = []
        transcript = nil
        activeTranscriptLineIndex = nil
        activeTranscriptWordIndex = nil
        segments = []
        stopUpdateTimer()
    }

    func seek(to time: TimeInterval) {
        let clamped = max(0, min(time, duration))
        player?.currentTime = clamped
        currentTime = clamped
        updateActiveQSO()
        updateActiveSegment()
    }

    func seekToQSO(at index: Int) {
        guard index >= 0, index < qsoOffsets.count else {
            return
        }
        let targetTime = max(0, qsoOffsets[index] - activeLeadIn)
        seek(to: targetTime)
    }

    func skip(by seconds: TimeInterval) {
        seek(to: currentTime + seconds)
    }

    func nextQSO() {
        let nextIndex = qsoOffsets.firstIndex { $0 - activeLeadIn > currentTime + 1 }
        if let idx = nextIndex {
            seekToQSO(at: idx)
        }
    }

    func previousQSO() {
        let prevIndex = qsoOffsets.lastIndex { $0 - activeLeadIn < currentTime - 1 }
        if let idx = prevIndex {
            seekToQSO(at: idx)
        }
    }

    // MARK: - Transcript

    func loadTranscript(sessionId: UUID) {
        transcript = SDRRecordingTranscript.load(sessionId: sessionId)
        if transcript != nil {
            computeQSORanges()
        }
    }

    func setTranscript(_ newTranscript: SDRRecordingTranscript) {
        transcript = newTranscript.filteringNoise()
        computeQSORanges()
    }

    // MARK: - Amplitude Scanning

    func scanAmplitude(fileURL: URL) {
        isLoadingAmplitude = true
        Task.detached(priority: .utility) {
            let envelope = RecordingPlaybackEngine.computeEnvelope(
                fileURL: fileURL, windowSeconds: 0.5
            )
            await MainActor.run { [weak self] in
                self?.amplitudeEnvelope = envelope
                self?.isLoadingAmplitude = false
            }
        }
    }

    func computeQSORanges() {
        if let transcript, !transcript.detectedQSORanges.isEmpty {
            qsoRanges = transcript.detectedQSORanges.map {
                (start: $0.startOffset, end: $0.endOffset)
            }
            return
        }

        guard !qsoOffsets.isEmpty else {
            qsoRanges = []
            return
        }

        var ranges: [(start: TimeInterval, end: TimeInterval)] = []
        for i in 0 ..< qsoOffsets.count {
            let qsoTime = qsoOffsets[i]
            let start: TimeInterval
            let end: TimeInterval

            if i == 0 {
                start = max(0, qsoTime - activeLeadIn)
            } else {
                let prev = qsoOffsets[i - 1] + activeTrailOut
                let curr = qsoTime - activeLeadIn
                start = max(0, (prev + curr) / 2)
            }

            if i == qsoOffsets.count - 1 {
                end = min(duration, qsoTime + activeTrailOut)
            } else {
                let curr = qsoTime + activeTrailOut
                let next = qsoOffsets[i + 1] - activeLeadIn
                end = min(duration, (curr + next) / 2)
            }

            ranges.append((start: start, end: end))
        }
        qsoRanges = ranges
    }

    func updateActiveTranscript() {
        guard let lines = transcript?.lines, !lines.isEmpty else {
            activeTranscriptLineIndex = nil
            activeTranscriptWordIndex = nil
            return
        }

        var lineIdx: Int?
        for (i, line) in lines.enumerated() {
            if currentTime >= line.startOffset, currentTime <= line.endOffset {
                lineIdx = i
                break
            }
        }

        if lineIdx == nil {
            lineIdx = lines.lastIndex { $0.endOffset <= currentTime }
        }

        activeTranscriptLineIndex = lineIdx

        if let li = lineIdx {
            let words = lines[li].words
            activeTranscriptWordIndex = words.firstIndex {
                currentTime >= $0.startOffset && currentTime <= $0.endOffset
            }
        } else {
            activeTranscriptWordIndex = nil
        }
    }

    // MARK: Private

    private var player: AVAudioPlayer?
    private var updateTimer: Timer?

    nonisolated private static func computeEnvelope(
        fileURL: URL, windowSeconds: Double
    ) -> [Float] {
        guard let audioFile = try? AVAudioFile(forReading: fileURL) else {
            return []
        }

        let format = audioFile.processingFormat
        let sampleRate = format.sampleRate
        let totalFrames = AVAudioFrameCount(audioFile.length)
        let windowFrames = AVAudioFrameCount(sampleRate * windowSeconds)
        guard windowFrames > 0 else {
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
            } catch { break }

            guard let channelData = buffer.floatChannelData?[0] else {
                break
            }

            let peaks = extractPeaks(
                from: channelData,
                frameCount: Int(buffer.frameLength),
                windowFrames: Int(windowFrames)
            )
            envelope.append(contentsOf: peaks)
            framesRemaining -= buffer.frameLength
        }

        return envelope
    }

    nonisolated private static func extractPeaks(
        from channelData: UnsafePointer<Float>,
        frameCount: Int,
        windowFrames: Int
    ) -> [Float] {
        var peaks: [Float] = []
        var offset = 0
        while offset < frameCount {
            let end = min(offset + windowFrames, frameCount)
            var peak: Float = 0
            for i in offset ..< end {
                let abs = Swift.abs(channelData[i])
                if abs > peak {
                    peak = abs
                }
            }
            peaks.append(peak)
            offset = end
        }
        return peaks
    }

    /// Timer-based position tracking (replaces CADisplayLink on macOS)
    private func startUpdateTimer() {
        stopUpdateTimer()
        updateTimer = Timer.scheduledTimer(
            withTimeInterval: 1.0 / 15.0,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                self?.updateCurrentTime()
            }
        }
    }

    private func stopUpdateTimer() {
        updateTimer?.invalidate()
        updateTimer = nil
    }

    private func updateCurrentTime() {
        guard let player else {
            return
        }
        currentTime = player.currentTime
        updateActiveQSO()
        updateActiveSegment()
        updateActiveTranscript()
    }

    private func updateActiveQSO() {
        var bestIndex: Int?
        var bestDistance: TimeInterval = .greatestFiniteMagnitude

        for (index, offset) in qsoOffsets.enumerated() {
            let windowStart = offset - activeLeadIn
            let windowEnd = offset + activeTrailOut
            if currentTime >= windowStart, currentTime <= windowEnd {
                let distance = abs(currentTime - offset)
                if distance < bestDistance {
                    bestDistance = distance
                    bestIndex = index
                }
            }
        }
        activeQSOIndex = bestIndex
    }

    private func updateActiveSegment() {
        guard !segments.isEmpty else {
            return
        }
        for (index, segment) in segments.enumerated() {
            let end = segment.endOffset ?? duration
            if currentTime >= segment.startOffset, currentTime < end {
                activeSegmentIndex = index
                return
            }
        }
        activeSegmentIndex = segments.count - 1
    }
}

// MARK: AVAudioPlayerDelegate

extension RecordingPlaybackEngine: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(
        _ player: AVAudioPlayer, successfully _: Bool
    ) {
        Task { @MainActor in
            self.isPlaying = false
            self.stopUpdateTimer()
            self.currentTime = self.duration
        }
    }
}
