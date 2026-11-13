import Foundation
import OSLog

public enum QueryFacade {
    // MARK: Public

    public static var current: QueryStore? {
        slot.lock.withLock { slot.store }
    }

    public static func register(_ store: QueryStore) {
        slot.lock.withLock { slot.store = store }
    }

    public static func unregister() {
        slot.lock.withLock { slot.store = nil }
    }

    public static func mirrorQSO(_ qso: QSO) {
        guard let store = current,
              let row = QSOMapper.slimRow(from: qso)
        else {
            return
        }
        Task.detached(priority: .utility) {
            do {
                try await store.upsertQSO(row)
            } catch {
                logger.error("mirrorQSO failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    public static func mirrorQSOs(_ qsos: [QSO]) {
        guard let store = current else {
            return
        }
        let rows = qsos.compactMap(QSOMapper.slimRow(from:))
        guard !rows.isEmpty else {
            return
        }
        Task.detached(priority: .utility) {
            do {
                try await store.upsertQSOs(rows)
            } catch {
                logger.error("mirrorQSOs failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    public static func mirrorOperatorProfile(_ row: OperatorProfileRow) {
        guard let store = current else {
            return
        }
        Task.detached(priority: .utility) {
            do {
                try await store.upsertOperatorProfile(row)
            } catch {
                logger.error(
                    "mirrorOperatorProfile failed: \(error.localizedDescription, privacy: .public)"
                )
            }
        }
    }

    public static func deleteMirroredQSO(id: UUID) {
        guard let store = current else {
            return
        }
        Task.detached(priority: .utility) {
            do {
                try await store.deleteQSO(id: id.uuidString)
            } catch {
                logger.error("deleteMirroredQSO failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: Private

    private final class Slot: @unchecked Sendable {
        let lock = NSLock()
        var store: QueryStore?
    }

    private static let slot = Slot()
    private static let logger = Logger(subsystem: "com.fullduplex.shared", category: "QueryFacade")
}
