import AVFoundation
import Foundation

// MARK: - SDRReplayEngine

/// Manages a rolling history buffer of recent SDR audio and plays back
/// the last N seconds on demand. Used during live recording sessions
/// so the operator can re-hear a recent signal.
@MainActor
@Observable
final class SDRReplayEngine {
    // MARK: Internal

    /// Default replay duration in seconds
    static let defaultReplayDuration: TimeInterval = 15

    /// Whether audio is currently being replayed
    private(set) var isReplaying = false

    /// Replay progress (0.0 to 1.0)
    private(set) var replayProgress: Double = 0

    /// Available history duration in seconds
    var availableHistorySeconds: TimeInterval {
        Double(historyBuffer.count) / sampleRate
    }

    /// Configure the engine for a new recording session.
    func configure(sampleRate: Double) {
        stopReplay()
        self.sampleRate = sampleRate
        historyBuffer.removeAll(keepingCapacity: true)
        historyBuffer.reserveCapacity(maxCapacity)
    }

    /// Feed incoming audio samples into the history buffer.
    /// Call this from the audio stream processing path.
    func feedSamples(_ samples: [Int16]) {
        historyBuffer.append(contentsOf: samples)
        let capacity = maxCapacity
        if historyBuffer.count > capacity {
            let excess = historyBuffer.count - capacity
            historyBuffer.removeFirst(excess)
        }
    }

    /// Replay the last N seconds of captured audio.
    /// Returns immediately; playback runs asynchronously.
    func replayLast(
        _ seconds: TimeInterval = SDRReplayEngine.defaultReplayDuration
    ) {
        guard !isReplaying, !historyBuffer.isEmpty else {
            return
        }

        let count = min(
            Int(seconds * sampleRate),
            historyBuffer.count
        )
        let startIndex = historyBuffer.count - count
        let samples = Array(historyBuffer[startIndex...])

        guard let fileURL = writeTempCAF(samples: samples) else {
            return
        }
        tempFileURL = fileURL

        do {
            let audioPlayer = try AVAudioPlayer(contentsOf: fileURL)
            audioPlayer.prepareToPlay()
            audioPlayer.play()
            player = audioPlayer
            isReplaying = true
            replayProgress = 0
            startProgressMonitor()
        } catch {
            cleanupTempFile()
        }
    }

    /// Stop replay playback immediately.
    func stopReplay() {
        progressTask?.cancel()
        progressTask = nil
        player?.stop()
        player = nil
        isReplaying = false
        replayProgress = 0
        cleanupTempFile()
    }

    /// Clear history buffer (called on session finalize).
    func reset() {
        stopReplay()
        historyBuffer.removeAll(keepingCapacity: false)
    }

    // MARK: Private

    // MARK: - Configuration

    private var sampleRate: Double = 12_000
    private let maxHistorySeconds: TimeInterval = 30
    private var historyBuffer: [Int16] = []
    private var player: AVAudioPlayer?
    private var progressTask: Task<Void, Never>?
    private var tempFileURL: URL?

    private var maxCapacity: Int {
        Int(sampleRate * maxHistorySeconds)
    }
}

// MARK: - Private Helpers

extension SDRReplayEngine {
    private func startProgressMonitor() {
        progressTask?.cancel()
        progressTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self,
                      let player
                else {
                    break
                }

                if !player.isPlaying {
                    stopReplay()
                    break
                }

                let duration = player.duration
                if duration > 0 {
                    replayProgress = player.currentTime / duration
                }

                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    private func writeTempCAF(samples: [Int16]) -> URL? {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent(
            "sdr-replay-\(UUID().uuidString).caf"
        )

        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: true
        ) else {
            return nil
        }

        let frameCount = AVAudioFrameCount(samples.count)
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: frameCount
        ) else {
            return nil
        }
        buffer.frameLength = frameCount

        guard let channelData = buffer.int16ChannelData?[0] else {
            return nil
        }
        for idx in 0 ..< samples.count {
            channelData[idx] = samples[idx]
        }

        do {
            let file = try AVAudioFile(
                forWriting: fileURL,
                settings: format.settings,
                commonFormat: .pcmFormatInt16,
                interleaved: true
            )
            try file.write(from: buffer)
            return fileURL
        } catch {
            return nil
        }
    }

    private func cleanupTempFile() {
        guard let url = tempFileURL else {
            return
        }
        try? FileManager.default.removeItem(at: url)
        tempFileURL = nil
    }
}
