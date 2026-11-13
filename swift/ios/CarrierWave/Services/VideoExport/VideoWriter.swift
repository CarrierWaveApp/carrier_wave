// Video Writer
//
// AVAssetWriter wrapper for writing H.264 video with optional AAC audio.

import AVFoundation
import Foundation

/// Nonisolated so the export actor can call it from its own isolation domain.
/// @unchecked Sendable: only accessed from VideoExportActor.
nonisolated final class VideoWriter: @unchecked Sendable {
    // MARK: Lifecycle

    init(outputURL: URL, includeAudio: Bool, sampleRate: Double = 12_000) throws {
        self.outputURL = outputURL
        writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)

        // Video input: H.264, 1920x1080, 8Mbps
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 1_920,
            AVVideoHeightKey: 1_080,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 8_000_000,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
            ],
        ]
        videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = false

        let bufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 1_920,
            kCVPixelBufferHeightKey as String: 1_080,
        ]
        adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: bufferAttributes
        )
        writer.add(videoInput)

        // Audio input (optional): AAC at 44.1kHz (standard rate for AAC compatibility).
        // Source audio is resampled from the recording's native rate (typically 12kHz).
        if includeAudio {
            let audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 64_000,
            ]
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            input.expectsMediaDataInRealTime = false
            writer.add(input)
            audioInput = input
        }

        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
    }

    // MARK: Internal

    var pixelBufferPool: CVPixelBufferPool? {
        adaptor.pixelBufferPool
    }

    /// Writer status — check after failure.
    var statusDescription: String {
        "status=\(writer.status.rawValue) error=\(writer.error?.localizedDescription ?? "none")"
    }

    /// Check if the writer is still in a good state.
    var isWriting: Bool {
        writer.status == .writing
    }

    /// Append a video frame, waiting briefly for the input to be ready.
    func appendVideoFrame(_ buffer: CVPixelBuffer, at time: CMTime) -> Bool {
        let waited = waitForReady(videoInput, limit: 50)
        if waited < 0 {
            return false
        }
        if waited > 5 {
            logStall("video", waitMs: waited, at: time)
        }
        return adaptor.append(buffer, withPresentationTime: time)
    }

    func appendAudioSamples(_ sampleBuffer: CMSampleBuffer) -> Bool {
        guard let input = audioInput else {
            return false
        }
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let waited = waitForReady(input, limit: 200)
        if waited < 0 {
            return false
        }
        if waited > 5 {
            logStall("audio", waitMs: waited, at: pts)
        }
        return input.append(sampleBuffer)
    }

    func finish() async -> Bool {
        videoInput.markAsFinished()
        audioInput?.markAsFinished()
        await writer.finishWriting()
        if writer.status != .completed {
            Task { @MainActor in
                SyncDebugLog.shared.log(
                    "VideoWriter finish failed: \(statusDescription)",
                    level: .error
                )
            }
        }
        return writer.status == .completed
    }

    func cancel() {
        writer.cancelWriting()
    }

    // MARK: Private

    private let outputURL: URL
    private let writer: AVAssetWriter
    private let videoInput: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private var audioInput: AVAssetWriterInput?

    /// Spin-waits for input readiness. Returns ms waited, or -1 on timeout/failure.
    private func waitForReady(_ input: AVAssetWriterInput, limit: Int) -> Int {
        var retries = 0
        while !input.isReadyForMoreMediaData {
            retries += 1
            if retries > limit || writer.status != .writing {
                return -1
            }
            usleep(1_000)
        }
        return retries
    }

    private func logStall(_ track: String, waitMs: Int, at time: CMTime) {
        let ts = String(format: "%.3f", CMTimeGetSeconds(time))
        Task { @MainActor in
            SyncDebugLog.shared.log(
                "VideoWriter: \(track) stall \(waitMs)ms at t=\(ts)s",
                level: .error
            )
        }
    }
}
