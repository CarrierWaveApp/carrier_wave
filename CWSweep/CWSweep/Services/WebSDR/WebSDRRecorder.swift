import AVFoundation
import Foundation

// MARK: - WebSDRRecorder

/// Records KiwiSDR audio frames to a compressed audio file.
/// Runs on a background actor to avoid blocking the main thread.
actor WebSDRRecorder {
    // MARK: Internal

    /// Recording state
    enum State: Sendable, Equatable {
        case idle
        case recording
        case paused
        case finished
        case error(String)
    }

    /// Current recording state
    var currentState: State {
        state
    }

    /// Duration of the recording so far in seconds
    var recordedDuration: TimeInterval {
        Double(totalFramesWritten) / sampleRate
    }

    /// Peak level (0.0 to 1.0) from recent audio for level meter display
    var peakLevel: Float {
        recentPeak
    }

    /// Start recording to a file
    func startRecording(to fileURL: URL, sampleRate: Double) throws {
        guard state == .idle else {
            throw WebSDRRecorderError.alreadyRecording
        }

        self.sampleRate = sampleRate
        self.fileURL = fileURL

        let format = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: true
        )
        guard let format else {
            throw WebSDRRecorderError.invalidFormat
        }

        audioFile = try AVAudioFile(
            forWriting: fileURL,
            settings: format.settings,
            commonFormat: .pcmFormatInt16,
            interleaved: true
        )

        totalFramesWritten = 0
        state = .recording
    }

    /// Write audio samples from a KiwiSDR frame
    func writeFrame(_ samples: [Int16]) throws {
        guard state == .recording else {
            return
        }
        guard let file = audioFile else {
            throw WebSDRRecorderError.noFileOpen
        }

        let frameCount = AVAudioFrameCount(samples.count)
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: file.processingFormat,
            frameCapacity: frameCount
        ) else {
            return
        }

        buffer.frameLength = frameCount

        guard let int16Data = buffer.int16ChannelData?[0] else {
            return
        }
        for i in 0 ..< samples.count {
            int16Data[i] = samples[i]
        }

        updatePeakLevel(samples)

        try file.write(from: buffer)
        totalFramesWritten += Int64(samples.count)
    }

    /// Pause recording (keeps file open)
    func pause() {
        guard state == .recording else {
            return
        }
        state = .paused
    }

    /// Resume recording
    func resume() {
        guard state == .paused else {
            return
        }
        state = .recording
    }

    /// Stop recording and close the file
    func stopRecording() -> URL? {
        guard state == .recording || state == .paused else {
            return nil
        }

        audioFile = nil
        state = .finished
        return fileURL
    }

    // MARK: Private

    private var audioFile: AVAudioFile?
    private var fileURL: URL?
    private var sampleRate: Double = 12_000
    private var totalFramesWritten: Int64 = 0
    private var state: State = .idle
    private var recentPeak: Float = 0

    private func updatePeakLevel(_ samples: [Int16]) {
        var maxSample: Int16 = 0
        for sample in samples {
            let abs = sample == Int16.min ? Int16.max : abs(sample)
            if abs > maxSample {
                maxSample = abs
            }
        }
        recentPeak = Float(maxSample) / Float(Int16.max)
    }
}

// MARK: - WebSDRRecorderError

nonisolated enum WebSDRRecorderError: Error, LocalizedError {
    case alreadyRecording
    case noFileOpen
    case invalidFormat

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case .alreadyRecording: "Already recording"
        case .noFileOpen: "No audio file is open"
        case .invalidFormat: "Could not create audio format"
        }
    }
}
