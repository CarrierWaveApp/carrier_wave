import AVFoundation
import Foundation

// MARK: - RecordingClipMetadata

/// Metadata to embed in an exported SDR recording clip
struct RecordingClipMetadata: Sendable {
    // MARK: Internal

    let receiverName: String
    let frequencyKHz: Double
    let mode: String
    let recordingDate: Date
    let callsigns: [String]

    var title: String {
        let freq = formatFrequency()
        return "\(freq) \(mode) via \(receiverName)"
    }

    var comment: String {
        guard !callsigns.isEmpty else {
            return "SDR Recording - \(receiverName)"
        }
        let calls = callsigns.prefix(10).joined(separator: ", ")
        let suffix = callsigns.count > 10 ? " +\(callsigns.count - 10) more" : ""
        return "QSOs: \(calls)\(suffix)"
    }

    // MARK: Private

    private func formatFrequency() -> String {
        let mHz = frequencyKHz / 1_000
        if mHz == mHz.rounded() {
            return String(format: "%.0f MHz", mHz)
        }
        return String(format: "%.3f MHz", mHz)
    }
}

// MARK: - RecordingClipExporter

/// Exports a time-range clip from a WebSDR recording as M4A.
enum RecordingClipExporter {
    // MARK: Internal

    static func exportClip(
        sourceURL: URL,
        startTime: TimeInterval,
        endTime: TimeInterval,
        metadata: RecordingClipMetadata? = nil
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

        if let metadata {
            session.metadata = buildMetadataItems(from: metadata)
        }

        try await session.export(to: outputURL, as: .m4a)

        return outputURL
    }

    // MARK: Private

    private static func buildMetadataItems(
        from metadata: RecordingClipMetadata
    ) -> [AVMetadataItem] {
        var items: [AVMetadataItem] = []

        items.append(makeItem(
            key: .commonKeyTitle, keySpace: .common, value: metadata.title
        ))
        items.append(makeItem(
            key: .commonKeyArtist, keySpace: .common, value: metadata.receiverName
        ))
        items.append(makeItem(
            key: .commonKeyDescription, keySpace: .common, value: metadata.comment
        ))
        items.append(makeItem(
            key: .commonKeyAlbumName, keySpace: .common, value: "SDR Recordings"
        ))

        let dateFormatter = ISO8601DateFormatter()
        items.append(makeItem(
            key: .commonKeyCreationDate, keySpace: .common,
            value: dateFormatter.string(from: metadata.recordingDate)
        ))

        return items
    }

    private static func makeItem(
        key: AVMetadataKey,
        keySpace: AVMetadataKeySpace,
        value: String
    ) -> AVMetadataItem {
        let item = AVMutableMetadataItem()
        item.key = key as NSCopying & NSObjectProtocol
        item.keySpace = keySpace
        item.value = value as NSString
        return item
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
