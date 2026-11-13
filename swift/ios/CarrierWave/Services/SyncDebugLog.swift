import CarrierWaveData
import Foundation

/// Captures raw QSO data and sync operations for debugging.
/// Persists log entries to disk so they survive app restarts.
@Observable
@MainActor
class SyncDebugLog {
    // MARK: Lifecycle

    private init() {
        loadFromDisk()
        pruneOldEntries()
    }

    // MARK: Internal

    struct RawQSOData: Identifiable, Codable {
        // MARK: Lifecycle

        init(timestamp: Date, service: ServiceType, rawJSON: String, parsedFields: [String: String]) {
            id = UUID()
            self.timestamp = timestamp
            self.service = service
            self.rawJSON = rawJSON
            self.parsedFields = parsedFields
        }

        // MARK: Internal

        let id: UUID
        let timestamp: Date
        let service: ServiceType
        let rawJSON: String
        let parsedFields: [String: String]
    }

    struct LogEntry: Identifiable, Codable {
        // MARK: Lifecycle

        init(timestamp: Date, level: Level, service: ServiceType?, message: String) {
            id = UUID()
            self.timestamp = timestamp
            self.level = level
            self.service = service
            self.message = message
        }

        // MARK: Internal

        enum Level: String, Codable {
            case info = "INFO"
            case warning = "WARN"
            case error = "ERROR"
            case debug = "DEBUG"
            case actionRequired = "ACTION"
        }

        let id: UUID
        let timestamp: Date
        let level: Level
        let service: ServiceType?
        let message: String
    }

    static let shared = SyncDebugLog()

    var rawQSOs: [ServiceType: [RawQSOData]] = [:]
    var logEntries: [LogEntry] = []

    func clearAll() {
        rawQSOs = [:]
        logEntries = []
        scheduleSave()
    }

    func clearLogs() {
        logEntries = []
        scheduleSave()
    }

    // MARK: - Raw QSO Logging

    func logRawQSO(service: ServiceType, rawJSON: String, parsedFields: [String: String]) {
        let entry = RawQSOData(
            timestamp: Date(),
            service: service,
            rawJSON: rawJSON,
            parsedFields: parsedFields
        )

        var serviceQSOs = rawQSOs[service] ?? []
        serviceQSOs.insert(entry, at: 0)
        if serviceQSOs.count > maxQSOsPerService {
            serviceQSOs = Array(serviceQSOs.prefix(maxQSOsPerService))
        }
        rawQSOs[service] = serviceQSOs
        scheduleSave()
    }

    // MARK: - Log Entries

    func log(_ message: String, level: LogEntry.Level = .info, service: ServiceType? = nil) {
        let entry = LogEntry(
            timestamp: Date(),
            level: level,
            service: service,
            message: message
        )

        logEntries.insert(entry, at: 0)
        if logEntries.count > maxLogEntries {
            logEntries = Array(logEntries.prefix(maxLogEntries))
        }

        // Also print for console debugging
        let serviceStr = service.map { "[\($0.displayName)]" } ?? ""
        print("[\(entry.level.rawValue)]\(serviceStr) \(message)")

        scheduleSave()
    }

    func info(_ message: String, service: ServiceType? = nil) {
        log(message, level: .info, service: service)
    }

    func warning(_ message: String, service: ServiceType? = nil) {
        log(message, level: .warning, service: service)
    }

    func error(_ message: String, service: ServiceType? = nil) {
        log(message, level: .error, service: service)
    }

    func debug(_ message: String, service: ServiceType? = nil) {
        log(message, level: .debug, service: service)
    }

    /// Log an issue that requires user action to fix (e.g., missing fields, invalid data)
    func actionRequired(_ message: String, service: ServiceType? = nil) {
        log(message, level: .actionRequired, service: service)
    }

    // MARK: Private

    private struct PersistedData: Codable {
        let logEntries: [LogEntry]
        let rawQSOs: [ServiceType: [RawQSOData]]
    }

    private static var storageURL: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        return appSupport.appendingPathComponent("sync-debug-log.json")
    }

    private let maxQSOsPerService = 5
    private let maxLogEntries = 500
    private let retentionInterval: TimeInterval = 14 * 24 * 60 * 60 // 14 days
    private var saveTask: Task<Void, Never>?

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else {
                return
            }
            self?.saveToDisk()
        }
    }

    private func saveToDisk() {
        let data = PersistedData(logEntries: logEntries, rawQSOs: rawQSOs)
        do {
            let dir = Self.storageURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let encoded = try JSONEncoder().encode(data)
            try encoded.write(to: Self.storageURL, options: .atomic)
        } catch {
            print("[SyncDebugLog] Failed to save: \(error)")
        }
    }

    private func pruneOldEntries() {
        let cutoff = Date().addingTimeInterval(-retentionInterval)
        let logsBefore = logEntries.count
        logEntries.removeAll { $0.timestamp < cutoff }

        var qsosPruned = false
        for (service, entries) in rawQSOs {
            let filtered = entries.filter { $0.timestamp >= cutoff }
            if filtered.count != entries.count {
                rawQSOs[service] = filtered.isEmpty ? nil : filtered
                qsosPruned = true
            }
        }

        if logEntries.count != logsBefore || qsosPruned {
            scheduleSave()
        }
    }

    private func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: Self.storageURL.path) else {
            return
        }
        do {
            let data = try Data(contentsOf: Self.storageURL)
            let persisted = try JSONDecoder().decode(PersistedData.self, from: data)
            logEntries = persisted.logEntries
            rawQSOs = persisted.rawQSOs
        } catch {
            print("[SyncDebugLog] Failed to load: \(error)")
        }
    }
}
