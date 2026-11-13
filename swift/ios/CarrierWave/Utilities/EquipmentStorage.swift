import CarrierWaveData
import Foundation
import SwiftData

// MARK: - EquipmentStorage + iOS

/// iOS-specific extensions for equipment storage.
extension EquipmentStorage {
    /// Migrate equipment lists from local UserDefaults to iCloud KVS.
    /// Checks both .standard and the App Group (prior migration target).
    static func migrateToiCloudKVS() {
        let migrationKey = "equipmentMigratedToiCloudKVS_v2"
        let standard = UserDefaults.standard
        guard !standard.bool(forKey: migrationKey) else {
            return
        }

        let appGroup = UserDefaults(suiteName: "group.com.jsvana.FullDuplex")
        let sources = [standard, appGroup].compactMap { $0 }
        let types: [EquipmentType] = [.antenna, .key, .mic]

        for source in sources {
            for type in types {
                if let items = source.stringArray(forKey: type.rawValue), !items.isEmpty {
                    for item in items {
                        add(item, for: type)
                    }
                    source.removeObject(forKey: type.rawValue)
                }
            }
        }

        standard.set(true, forKey: migrationKey)
    }

    /// Recover equipment lists from past session history.
    @MainActor
    static func recoverFromSessions(container: ModelContainer) {
        let context = ModelContext(container)
        context.autosaveEnabled = false

        var descriptor = FetchDescriptor<LoggingSession>()
        descriptor.fetchLimit = 500
        guard let sessions = try? context.fetch(descriptor) else {
            return
        }

        var radios = Set(RadioStorage.load())
        var antennas = Set(load(for: .antenna))
        var keys = Set(load(for: .key))
        var mics = Set(load(for: .mic))
        var changed = false

        for session in sessions {
            if let rig = session.myRig, !rig.isEmpty, radios.insert(rig).inserted {
                RadioStorage.add(rig)
                changed = true
            }
            if let ant = session.myAntenna, !ant.isEmpty, antennas.insert(ant).inserted {
                add(ant, for: .antenna)
                changed = true
            }
            if let key = session.myKey, !key.isEmpty, keys.insert(key).inserted {
                add(key, for: .key)
                changed = true
            }
            if let mic = session.myMic, !mic.isEmpty, mics.insert(mic).inserted {
                add(mic, for: .mic)
                changed = true
            }
        }

        if changed {
            SyncDebugLog.shared.info("Equipment recovery: merged equipment from session history")
        }
    }
}
