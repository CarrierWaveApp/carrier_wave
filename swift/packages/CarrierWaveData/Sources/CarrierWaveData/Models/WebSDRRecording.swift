import Foundation
import SwiftData

// MARK: - ClipBookmark

/// A bookmarked moment in a recording timeline
public struct ClipBookmark: Codable, Identifiable, Sendable {
    // MARK: Lifecycle

    public init(
        id: UUID = .init(),
        offsetSeconds: Double,
        label: String? = nil,
        createdAt: Date = .init()
    ) {
        self.id = id
        self.offsetSeconds = offsetSeconds
        self.label = label
        self.createdAt = createdAt
    }

    // MARK: Public

    public var id: UUID = .init()
    /// Offset in seconds from the recording start
    public var offsetSeconds: Double
    /// Optional label (e.g., "CQ", "Exchange", user note)
    public var label: String?
    /// When the bookmark was created
    public var createdAt: Date = .init()
}

// MARK: - WebSDRRecording

/// Stores metadata for a WebSDR audio recording associated with a logging session
@Model
nonisolated public final class WebSDRRecording {
    // MARK: Lifecycle

    public init(
        loggingSessionId: UUID,
        kiwisdrHost: String,
        kiwisdrName: String,
        frequencyKHz: Double,
        mode: String
    ) {
        id = UUID()
        self.loggingSessionId = loggingSessionId
        self.kiwisdrHost = kiwisdrHost
        self.kiwisdrName = kiwisdrName
        startedAt = Date()
        self.frequencyKHz = frequencyKHz
        self.mode = mode
    }

    // MARK: Public

    public var id = UUID()
    public var loggingSessionId = UUID()
    public var kiwisdrHost = ""
    public var kiwisdrName = ""
    public var startedAt = Date()
    public var endedAt: Date?
    public var frequencyKHz: Double = 0
    public var mode: String = ""

    /// Relative path within app Documents (e.g., "WebSDRRecordings/uuid.caf")
    public var relativeFilePath: String = ""

    /// File size in bytes
    public var fileSizeBytes: Int64 = 0

    /// Recording duration in seconds
    public var durationSeconds: Double = 0

    /// Whether the recording completed successfully
    public var isComplete: Bool = false

    // MARK: - Spot Metadata (Tune In recordings)

    /// Callsign of the station being listened to
    public var spotCallsign: String?

    /// Park reference (e.g., "US-4557") if POTA activation
    public var spotParkRef: String?

    /// Park name if POTA activation
    public var spotParkName: String?

    /// Summit code (e.g., "W4C/CM-001") if SOTA activation
    public var spotSummitCode: String?

    /// Band (e.g., "20m")
    public var spotBand: String?

    /// Whether this is a standalone Tune In recording (not tied to a logging session)
    public var isTuneInRecording: Bool = false

    // MARK: - Clip Bookmarks

    /// Serialized clip bookmark offsets (seconds into recording)
    public var clipBookmarksData: Data?

    /// Serialized SDR parameter change events (frequency/mode changes during recording)
    public var parameterChangesData: Data?

    /// Clip bookmarks — points of interest during the recording
    public var clipBookmarks: [ClipBookmark] {
        get {
            guard let data = clipBookmarksData else {
                return []
            }
            return (try? JSONDecoder().decode([ClipBookmark].self, from: data)) ?? []
        }
        set {
            clipBookmarksData = try? JSONEncoder().encode(newValue)
        }
    }

    /// SDR parameter change events that occurred during this recording
    public var parameterChanges: [SDRParameterEvent] {
        get {
            guard let data = parameterChangesData else {
                return []
            }
            return (try? JSONDecoder().decode([SDRParameterEvent].self, from: data)) ?? []
        }
        set {
            parameterChangesData = try? JSONEncoder().encode(newValue)
        }
    }

    /// Contiguous recording segments derived from initial parameters and change events.
    public var segments: [SDRRecordingSegment] {
        var result: [SDRRecordingSegment] = []
        var currentFreq = frequencyKHz
        var currentMode = mode
        var currentSilence = false
        var segmentStart: TimeInterval = 0

        let sorted = parameterChanges.sorted { $0.offsetSeconds < $1.offsetSeconds }
        for event in sorted {
            result.append(SDRRecordingSegment(
                startOffset: segmentStart,
                endOffset: event.offsetSeconds,
                frequencyKHz: currentFreq,
                mode: currentMode,
                isSilence: currentSilence
            ))

            switch event.type {
            case .frequency:
                if let newFreq = Double(event.newValue) {
                    currentFreq = newFreq
                }
            case .mode:
                currentMode = event.newValue
            case .pause,
                 .sdrDisconnected:
                currentSilence = true
            case .resume,
                 .sdrConnected:
                currentSilence = false
            }

            segmentStart = event.offsetSeconds
        }

        result.append(SDRRecordingSegment(
            startOffset: segmentStart,
            endOffset: nil,
            frequencyKHz: currentFreq,
            mode: currentMode,
            isSilence: currentSilence
        ))

        return result
    }

    /// Full file URL resolved from relative path
    public var fileURL: URL? {
        guard !relativeFilePath.isEmpty else {
            return nil
        }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        return docs?.appendingPathComponent(relativeFilePath)
    }

    /// Formatted duration (e.g., "1h 23m")
    public var formattedDuration: String {
        let hours = Int(durationSeconds) / 3_600
        let minutes = (Int(durationSeconds) % 3_600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    /// Formatted file size (e.g., "3.5 MB")
    public var formattedFileSize: String {
        ByteCountFormatter.string(fromByteCount: fileSizeBytes, countStyle: .file)
    }

    /// Create the recordings directory if needed, return file URL for a new recording
    public static func newRecordingURL(sessionId: UUID) -> URL? {
        guard let docs = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        ).first else {
            return nil
        }

        let dir = docs.appendingPathComponent("WebSDRRecordings")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("\(sessionId.uuidString).caf")
    }

    /// Relative path for a session's recording
    public static func relativePath(sessionId: UUID) -> String {
        "WebSDRRecordings/\(sessionId.uuidString).caf"
    }

    /// Find the completed recording for a specific logging session
    public static func findRecording(
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
    public static func findRecordings(
        forSessionIds sessionIds: [UUID], in context: ModelContext
    ) throws -> [WebSDRRecording] {
        var descriptor = FetchDescriptor<WebSDRRecording>(
            predicate: #Predicate { $0.isComplete }
        )
        descriptor.fetchLimit = 500
        let all = try context.fetch(descriptor)
        let idSet = Set(sessionIds)
        return all.filter { idSet.contains($0.loggingSessionId) }
    }

    /// Mark recording as finished
    public func finish() {
        endedAt = Date()
        durationSeconds = endedAt?.timeIntervalSince(startedAt) ?? 0
        isComplete = true
        updateFileSize()
    }

    /// Update file size from disk
    public func updateFileSize() {
        guard let url = fileURL else {
            return
        }
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        fileSizeBytes = (attrs?[.size] as? Int64) ?? 0
    }

    /// Delete the recording file from disk
    public func deleteFile() {
        guard let url = fileURL else {
            return
        }
        try? FileManager.default.removeItem(at: url)
    }
}
