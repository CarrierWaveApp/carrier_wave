import CloudKit
import Foundation
import os

// MARK: - Zone Management & State Persistence

extension CloudSyncEngine {
    func ensureZoneExists() async throws {
        guard let engine = syncEngine else {
            return
        }

        let zone = CKRecordZone(zoneID: CKRecordMapper.zoneID)
        let pendingZone = CKSyncEngine.PendingDatabaseChange.saveZone(zone)
        engine.state.add(pendingDatabaseChanges: [pendingZone])
    }

    func loadSyncState() async throws -> CKSyncEngine.State.Serialization? {
        guard let data = UserDefaults.standard.data(forKey: stateKey) else {
            return nil
        }
        return try JSONDecoder().decode(
            CKSyncEngine.State.Serialization.self,
            from: data
        )
    }

    func saveSyncState(_ state: CKSyncEngine.State.Serialization) {
        do {
            let data = try JSONEncoder().encode(state)
            UserDefaults.standard.set(data, forKey: stateKey)
        } catch {
            logger.error("Failed to save sync state: \(error)")
        }
    }
}
