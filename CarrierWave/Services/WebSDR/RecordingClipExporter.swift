import AVFoundation
import Foundation

// MARK: - RecordingClipExporter

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

        session.timeRange = timeRange

        try await session.export(to: outputURL, as: .m4a)

        return outputURL
    }
}

// MARK: - ClipExportError

enum ClipExportError: Error, LocalizedError {
    case invalidRange
    case exportSessionFailed
    case exportFailed(String)

    // MARK: Internal

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
