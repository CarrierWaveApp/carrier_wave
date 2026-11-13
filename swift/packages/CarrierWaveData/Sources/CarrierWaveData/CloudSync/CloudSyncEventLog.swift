// CarrierWaveData/Sources/CarrierWaveData/CloudSync/CloudSyncEventLog.swift
import Foundation
import OSLog

/// Persists sync events to a JSON file with FIFO retention.
public actor CloudSyncEventLog {
    // MARK: Lifecycle

    public init(
        fileURL: URL? = nil,
        maxEvents: Int = 500
    ) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let libDir = FileManager.default.urls(
                for: .libraryDirectory, in: .userDomainMask
            ).first!
            self.fileURL = libDir
                .appendingPathComponent("CloudSync", isDirectory: true)
                .appendingPathComponent("sync_events.json")
        }
        self.maxEvents = maxEvents
    }

    // MARK: Public

    /// Load events from disk. Call once during service configuration.
    public func load() {
        guard FileManager.default.fileExists(
            atPath: fileURL.path
        ) else {
            return
        }
        do {
            let data = try Data(contentsOf: fileURL)
            events = try JSONDecoder().decode(
                [CloudSyncEvent].self, from: data
            )
        } catch {
            logger.warning(
                "Failed to load sync events: \(error.localizedDescription)"
            )
        }
    }

    /// Append an event, prune if over capacity, write to disk.
    public func append(_ event: CloudSyncEvent) {
        events.append(event)
        if events.count > maxEvents {
            events.removeFirst(events.count - maxEvents)
        }
        writeToDisk()
    }

    /// Return current snapshot of all events.
    public func allEvents() -> [CloudSyncEvent] {
        events
    }

    // MARK: Private

    private var events: [CloudSyncEvent] = []
    private let fileURL: URL
    private let maxEvents: Int
    private let logger = Logger(
        subsystem: "com.jsvana.FullDuplex",
        category: "CloudSyncEventLog"
    )

    private func writeToDisk() {
        do {
            let dir = fileURL.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: dir.path) {
                try FileManager.default.createDirectory(
                    at: dir, withIntermediateDirectories: true
                )
            }
            let data = try JSONEncoder().encode(events)
            try data.write(to: fileURL, options: .atomic)

            // Exclude from backup
            var resourceURL = fileURL
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try resourceURL.setResourceValues(values)
        } catch {
            logger.warning(
                "Failed to write sync events: \(error.localizedDescription)"
            )
        }
    }
}
