import Foundation
import SwiftData

/// Stores metadata for a WebSDR audio recording associated with a logging session
@Model
final class WebSDRRecording {
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
