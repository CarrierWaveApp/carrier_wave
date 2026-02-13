import AVFoundation
import Foundation

// MARK: - RecordingPlaybackEngine

/// Playback engine for WebSDR recordings. Wraps AVAudioPlayer with
/// seeking, speed control, and a display-link timer for UI updates.
@MainActor
@Observable
final class RecordingPlaybackEngine: NSObject {
    // MARK: Internal

    // MARK: - Public State

    /// Current playback position in seconds
    private(set) var currentTime: TimeInterval = 0

    /// Total duration of the loaded recording
    private(set) var duration: TimeInterval = 0

    /// Whether audio is currently playing
    private(set) var isPlaying = false

    /// Index of the QSO currently under the playback head (nil if none)
    private(set) var activeQSOIndex: Int?

    // MARK: - Amplitude Envelope

    /// Downsampled amplitude envelope for waveform display (0.0 to 1.0)
    private(set) var amplitudeEnvelope: [Float] = []

    /// Whether the amplitude envelope is still being computed
    private(set) var isLoadingAmplitude = false

    /// Current playback rate (0.5, 1.0, 1.5, 2.0)
    var playbackRate: Float = 1.0 {
        didSet { player?.rate = playbackRate }
    }

    /// Whether a recording is loaded and ready to play
    var isLoaded: Bool {
        player != nil
    }

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
        startDisplayLink()
    }

    func pause() {
        guard isPlaying else {
            return
        }
        player?.pause()
        isPlaying = false
        stopDisplayLink()
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
        guard index >= 0, index < qsoOffsets.count else {
            return
        }
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

    // MARK: - Amplitude Scanning

    /// Scan the audio file and compute amplitude envelope on a background task.
    /// Call after load(). Each sample represents 0.5 seconds of audio.
    func scanAmplitude(fileURL: URL) {
        isLoadingAmplitude = true
        let sampleWindowSeconds = 0.5

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

    // MARK: Private

    // MARK: - QSO Time Alignment

    /// QSO offsets in seconds from recording start, sorted ascending
    private var qsoOffsets: [TimeInterval] = []

    /// Window before QSO timestamp to consider "active" (seconds)
    private let activeLeadIn: TimeInterval = 90

    /// Window after QSO timestamp to consider "active" (seconds)
    private let activeTrailOut: TimeInterval = 15

    private var player: AVAudioPlayer?
    private var displayLink: CADisplayLink?

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

        guard windowFrames > 0 else {
            return []
        }

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

    /// Extract peak amplitudes from a buffer in windowed chunks
    private static func extractPeaks(
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
        guard let player else {
            return
        }
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

// MARK: AVAudioPlayerDelegate

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
