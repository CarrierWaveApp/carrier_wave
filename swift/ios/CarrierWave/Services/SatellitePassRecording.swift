import UIKit

// MARK: - SatellitePassRecording

/// One recorded satellite pass: an audio file plus the "I just worked
/// someone" tap marks, stored as offsets from the recording start. This is
/// the community's own coping mechanism productized — record the whole pass,
/// log after LOS from the recording (P3 of the satellite-workflow plan).
nonisolated struct SatellitePassRecording: Codable, Equatable, Identifiable {
    var id: UUID
    var noradID: Int
    /// Short OSCAR designator ("AO-91") at record time.
    var satelliteName: String
    var startedAt: Date
    var endedAt: Date?
    /// Seconds from `startedAt`, one per mark tap, ascending.
    var markOffsets: [TimeInterval]
    /// Basename of the audio file next to the sidecar JSON.
    var audioFileName: String

    /// Absolute timestamps of the marks (pre-seed the quick-log rows).
    var markDates: [Date] {
        markOffsets.map { startedAt.addingTimeInterval($0) }
    }
}

// MARK: - SatellitePassRecordingStore

/// Sidecar-JSON persistence for pass recordings under Application Support.
/// Pure file plumbing with injectable directory + clock so retention and
/// lookup rules are unit-testable; the `AVAudioRecorder` lifecycle lives in
/// `SatellitePassRecorder`.
nonisolated enum SatellitePassRecordingStore {
    // MARK: Internal

    /// Pass audio is a scratchpad for post-LOS logging, not an archive.
    static let retention: TimeInterval = 7 * 24 * 3_600

    /// A recording only pre-seeds a quick log while the pass is still fresh.
    static let recentWindow: TimeInterval = 45 * 60

    static func defaultDirectory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        )
        var directory = base.appendingPathComponent("SatellitePassRecordings", isDirectory: true)
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            // Transient scratch audio — keep it out of iCloud/iTunes backups.
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? directory.setResourceValues(values)
        }
        return directory
    }

    static func audioURL(for recording: SatellitePassRecording, in directory: URL) -> URL {
        directory.appendingPathComponent(recording.audioFileName)
    }

    static func save(_ recording: SatellitePassRecording, in directory: URL) throws {
        let data = try JSONEncoder().encode(recording)
        try data.write(to: sidecarURL(id: recording.id, in: directory), options: .atomic)
    }

    static func loadAll(in directory: URL) -> [SatellitePassRecording] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        )) ?? []
        return contents
            .filter { $0.pathExtension == "json" }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url) else {
                    return nil
                }
                return try? JSONDecoder().decode(SatellitePassRecording.self, from: data)
            }
            .sorted { $0.startedAt > $1.startedAt }
    }

    /// The freshest finished recording for a bird, within `recentWindow` of
    /// its end — the one the post-LOS quick log should play back.
    static func latest(
        noradID: Int,
        in directory: URL,
        now: Date = Date()
    ) -> SatellitePassRecording? {
        loadAll(in: directory).first { recording in
            guard recording.noradID == noradID, let ended = recording.endedAt else {
                return false
            }
            return now.timeIntervalSince(ended) < recentWindow
        }
    }

    /// Delete recordings (sidecar + audio) older than `retention`.
    static func prune(in directory: URL, now: Date = Date()) {
        for recording in loadAll(in: directory)
            where now.timeIntervalSince(recording.startedAt) > retention
        {
            try? FileManager.default.removeItem(at: audioURL(for: recording, in: directory))
            try? FileManager.default.removeItem(at: sidecarURL(id: recording.id, in: directory))
        }
    }

    // MARK: Private

    private static func sidecarURL(id: UUID, in directory: URL) -> URL {
        directory.appendingPathComponent("\(id.uuidString.lowercased()).json")
    }
}
