import CarrierWaveCore
import Combine
import Foundation

/// Captures raw QSO data and sync operations for debugging
@MainActor
class SyncDebugLog: ObservableObject {
    // MARK: Lifecycle

    private init() {}

    // MARK: Internal

    struct RawQSOData: Identifiable {
        let id = UUID()
        let timestamp: Date
        let service: ServiceType
        let rawJSON: String
        let parsedFields: [String: String]
    }

    struct LogEntry: Identifiable {
        enum Level: String {
            case info = "INFO"
            case warning = "WARN"
            case error = "ERROR"
            case debug = "DEBUG"
            case actionRequired = "ACTION"
        }

        let id = UUID()
        let timestamp: Date
        let level: Level
        let service: ServiceType?
        let message: String
    }

    static let shared = SyncDebugLog()

    @Published var rawQSOs: [ServiceType: [RawQSOData]] = [:]
    @Published var logEntries: [LogEntry] = []

    func clearAll() {
        rawQSOs = [:]
        logEntries = []
    }

    func clearLogs() {
        logEntries = []
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

    private let maxQSOsPerService = 5
    private let maxLogEntries = 500
}
