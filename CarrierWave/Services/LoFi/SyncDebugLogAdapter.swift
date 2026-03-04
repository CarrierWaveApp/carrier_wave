import CarrierWaveData
import Foundation

/// Adapts SyncDebugLog to the LoFiLogger protocol
/// Must be created on @MainActor since SyncDebugLog.shared is @MainActor
@MainActor
final class SyncDebugLogAdapter: LoFiLogger {
    // MARK: Internal

    nonisolated func info(_ message: String) {
        Task { @MainActor in
            SyncDebugLog.shared.info(message, service: .lofi)
        }
    }

    nonisolated func warning(_ message: String) {
        Task { @MainActor in
            SyncDebugLog.shared.warning(message, service: .lofi)
        }
    }

    nonisolated func error(_ message: String) {
        Task { @MainActor in
            SyncDebugLog.shared.error(message, service: .lofi)
        }
    }

    nonisolated func debug(_ message: String) {
        Task { @MainActor in
            SyncDebugLog.shared.debug(message, service: .lofi)
        }
    }

    // MARK: Private

    private let debugLog = SyncDebugLog.shared
}
