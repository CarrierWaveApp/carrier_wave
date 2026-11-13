import CarrierWaveData
import Foundation
import SwiftData

// MARK: - Persistence

extension ActivityLogManager {
    /// Re-read the active log from persistence. Used by views that share a
    /// manager instance with another view: when the *other* view creates a
    /// log, this manager's in-memory `activeLog` stays stale until something
    /// either re-runs `loadActiveLog` or recreates the manager. Cheap — one
    /// UserDefaults read plus a SwiftData fetch by ID.
    func loadActiveLog() {
        guard let idString = UserDefaults.standard.string(
            forKey: Self.activeLogIdKey
        ),
            let logId = UUID(uuidString: idString)
        else {
            return
        }

        let predicate = #Predicate<ActivityLog> { log in
            log.id == logId
        }
        let descriptor = FetchDescriptor<ActivityLog>(predicate: predicate)

        do {
            let logs = try modelContext.fetch(descriptor)
            if let log = logs.first, log.isActive {
                activeLog = log
                // Today stats deferred to first refreshTodayStats() call
                // to avoid an expensive SwiftData query during init.
            } else {
                clearActiveLogId()
            }
        } catch {
            clearActiveLogId()
        }
    }

    func saveActiveLogId(_ id: UUID) {
        UserDefaults.standard.set(id.uuidString, forKey: Self.activeLogIdKey)
    }

    func clearActiveLogId() {
        UserDefaults.standard.removeObject(forKey: Self.activeLogIdKey)
    }
}
