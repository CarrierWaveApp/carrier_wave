import Foundation
import SwiftData

// MARK: - ClipBookmark

/// A bookmarked moment in a recording timeline
struct ClipBookmark: Codable, Identifiable, Sendable {
    var id: UUID = .init()
    /// Offset in seconds from the recording start
    var offsetSeconds: Double
    /// Optional label (e.g., "CQ", "Exchange", user note)
    var label: String?
    /// When the bookmark was created
    var createdAt: Date = .init()
}

// MARK: - WebSDRRecording

/// Stores metadata for a WebSDR audio recording associated with a logging session
@Model
nonisolated final class WebSDRRecording {
    // MARK: Lifecycle

    init(
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

    // MARK: Internal

    var id = UUID()
    var loggingSessionId = UUID()
    var kiwisdrHost = ""
    var kiwisdrName = ""
    var startedAt = Date()
    var endedAt: Date?
    var frequencyKHz: Double = 0
    var mode: String = ""

    /// Relative path within app Documents (e.g., "WebSDRRecordings/uuid.m4a")
    var relativeFilePath: String = ""

    /// File size in bytes
    var fileSizeBytes: Int64 = 0

    /// Recording duration in seconds
    var durationSeconds: Double = 0

    /// Whether the recording completed successfully
    var isComplete: Bool = false

    // MARK: - Spot Metadata (Tune In recordings)

    /// Callsign of the station being listened to
    var spotCallsign: String?

    /// Park reference (e.g., "US-4557") if POTA activation
    var spotParkRef: String?

    /// Park name if POTA activation
    var spotParkName: String?

    /// Summit code (e.g., "W4C/CM-001") if SOTA activation
    var spotSummitCode: String?

    /// Band (e.g., "20m")
    var spotBand: String?

    /// Whether this is a standalone Tune In recording (not tied to a logging session)
    var isTuneInRecording: Bool = false

    // MARK: - Clip Bookmarks

    /// Serialized clip bookmark offsets (seconds into recording)
    var clipBookmarksData: Data?

    /// Clip bookmarks — points of interest during the recording
    var clipBookmarks: [ClipBookmark] {
        get {
            guard let data = clipBookmarksData else { return [] }
            return (try? JSONDecoder().decode(
                [ClipBookmark].self, from: data
            )) ?? []
        }
        set {
            clipBookmarksData = try? JSONEncoder().encode(newValue)
        }
    }

    /// Serialized SDR parameter change events (frequency/mode changes during recording)
    var parameterChangesData: Data?

    /// SDR parameter change events that occurred during this recording
    var parameterChanges: [SDRParameterEvent] {
        get {
            guard let data = parameterChangesData else {
                return []
            }
            return (try? JSONDecoder().decode(
                [SDRParameterEvent].self, from: data
            )) ?? []
        }
        set {
            parameterChangesData = try? JSONEncoder().encode(newValue)
        }
    }

    /// Contiguous recording segments derived from initial parameters and change events.
    /// Each segment has a consistent frequency, mode, and silence/active status.
    var segments: [SDRRecordingSegment] {
        var result: [SDRRecordingSegment] = []
        var currentFreq = frequencyKHz
        var currentMode = mode
        var currentSilence = false
        var segmentStart: TimeInterval = 0

        let sorted = parameterChanges.sorted { $0.offsetSeconds < $1.offsetSeconds }
        for event in sorted {
            // Close the current segment at this event's offset
            result.append(SDRRecordingSegment(
                startOffset: segmentStart,
                endOffset: event.offsetSeconds,
                frequencyKHz: currentFreq,
                mode: currentMode,
                isSilence: currentSilence
            ))

            // Apply the change
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

        // Final segment (open-ended, closed by recording duration)
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
    var fileURL: URL? {
        guard !relativeFilePath.isEmpty else {
            return nil
        }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        return docs?.appendingPathComponent(relativeFilePath)
    }

    /// Formatted duration (e.g., "1h 23m")
    var formattedDuration: String {
        let hours = Int(durationSeconds) / 3_600
        let minutes = (Int(durationSeconds) % 3_600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    /// Formatted file size (e.g., "3.5 MB")
    var formattedFileSize: String {
        ByteCountFormatter.string(fromByteCount: fileSizeBytes, countStyle: .file)
    }

    /// Create the recordings directory if needed, return file URL for a new recording
    static func newRecordingURL(sessionId: UUID) -> URL? {
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
    static func relativePath(sessionId: UUID) -> String {
        "WebSDRRecordings/\(sessionId.uuidString).caf"
    }

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

    /// Mark recording as finished
    func finish() {
        endedAt = Date()
        durationSeconds = endedAt?.timeIntervalSince(startedAt) ?? 0
        isComplete = true
        updateFileSize()
    }

    /// Update file size from disk
    func updateFileSize() {
        guard let url = fileURL else {
            return
        }
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        fileSizeBytes = (attrs?[.size] as? Int64) ?? 0
    }

    /// Delete the recording file from disk
    func deleteFile() {
        guard let url = fileURL else {
            return
        }
        try? FileManager.default.removeItem(at: url)
    }
}
