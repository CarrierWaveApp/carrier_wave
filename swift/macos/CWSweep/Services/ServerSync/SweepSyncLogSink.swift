import CarrierWaveData
import OSLog

// MARK: - SweepSyncLogSink

/// Routes the shared Carrier Wave Sync diagnostics into CW Sweep's logs: the
/// unified log (`com.jsvana.CWSweep` / `ServerSync`) and the in-app
/// `CwStoreWriteLog` the Data tab shows.
struct SweepSyncLogSink: ServerSyncLogging {
    // MARK: Internal

    func info(_ message: String) {
        Self.logger.info("\(message, privacy: .public)")
        Task { @MainActor in CwStoreWriteLog.shared.record(message) }
    }

    func error(_ message: String) {
        Self.logger.error("\(message, privacy: .public)")
        Task { @MainActor in CwStoreWriteLog.shared.record("ERROR: \(message)") }
    }

    // MARK: Private

    private static let logger = Logger(subsystem: "com.jsvana.CWSweep", category: "ServerSync")
}
