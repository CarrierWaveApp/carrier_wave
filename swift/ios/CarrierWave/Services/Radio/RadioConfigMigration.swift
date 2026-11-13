import CarrierWaveData
import Foundation
import SwiftData

// MARK: - RadioConfigMigration

/// Migrates the singleton `RadioService` configuration (stored in
/// `UserDefaults` + Keychain) to a `RadioConnectionProfile` on the
/// matching `EquipmentItem`, and back-fills `LoggingSession.radioItemID`
/// from `myRig` name matches.
///
/// Runs once on launch after the equipment migration has populated the
/// inventory. Idempotent — the `migrationKey` UserDefaults flag short
/// circuits a second pass.
@MainActor
enum RadioConfigMigration {
    // MARK: Internal

    static var isMigrated: Bool {
        UserDefaults.standard.bool(forKey: migrationKey)
    }

    /// Run the migration. Caller passes the shared container so a fresh
    /// `ModelContext` can be used.
    static func run(container: ModelContainer) {
        guard !isMigrated else {
            return
        }

        let context = ModelContext(container)
        let service = RadioService.shared

        attachCurrentProfileToMatchingRadio(context: context, service: service)
        backfillSessionRadioItemIDs(context: context)

        try? context.save()
        UserDefaults.standard.set(true, forKey: migrationKey)
    }

    /// Reset the flag so the migration runs again on next launch.
    /// Exposed for the Equipment Browser's "Re-run Migration" action.
    static func resetMigration() {
        UserDefaults.standard.removeObject(forKey: migrationKey)
    }

    // MARK: Private

    private static let migrationKey = "radioConfigMigration.completed"

    private static func attachCurrentProfileToMatchingRadio(
        context: ModelContext,
        service: RadioService
    ) {
        guard let profile = service.currentProfileSnapshot() else {
            return
        }

        let radioCategoryRaw = EquipmentCategory.radio.rawValue
        var descriptor = FetchDescriptor<EquipmentItem>()
        descriptor.fetchLimit = 200
        descriptor.predicate = #Predicate<EquipmentItem> { item in
            item.categoryRawValue == radioCategoryRaw
        }
        guard let radios = try? context.fetch(descriptor) else {
            return
        }

        let matched = pickRadioForProfile(radios, savedName: service.savedDeviceName)
        if let target = matched {
            // Don't overwrite a profile the user already configured
            // through the new UI before this migration runs.
            if target.connectionProfileJSON == nil {
                target.connectionProfile = profile
            }
        } else {
            // Synthesise an unlinked custom radio so the user's existing
            // connection settings survive the move to per-item profiles.
            let fallbackName = service.savedDeviceName
                ?? service.wifiIPAddress
                ?? service.flexIPAddress
                ?? "Radio"
            let custom = EquipmentItem.custom(
                name: fallbackName,
                category: .radio
            )
            custom.connectionProfile = profile
            context.insert(custom)
        }
    }

    private static func pickRadioForProfile(
        _ radios: [EquipmentItem],
        savedName: String?
    ) -> EquipmentItem? {
        // Exact name match wins
        if let savedName, !savedName.isEmpty {
            let lower = savedName.lowercased()
            if let hit = radios.first(where: {
                $0.displayName.lowercased() == lower
                    || $0.catalogName.lowercased() == lower
            }) {
                return hit
            }
            // Substring match
            if let hit = radios.first(where: {
                $0.displayName.lowercased().contains(lower)
                    || $0.catalogName.lowercased().contains(lower)
            }) {
                return hit
            }
        }
        // No name to match against — fall back to the single radio
        // if there's only one, otherwise leave unmatched.
        return radios.count == 1 ? radios.first : nil
    }

    private static func backfillSessionRadioItemIDs(context: ModelContext) {
        var radioDescriptor = FetchDescriptor<EquipmentItem>()
        radioDescriptor.fetchLimit = 200
        let radioRaw = EquipmentCategory.radio.rawValue
        radioDescriptor.predicate = #Predicate<EquipmentItem> { item in
            item.categoryRawValue == radioRaw
        }
        guard let radios = try? context.fetch(radioDescriptor) else {
            return
        }
        let nameIndex = buildNameIndex(radios)
        guard !nameIndex.isEmpty else {
            return
        }

        var sessionDescriptor = FetchDescriptor<LoggingSession>()
        sessionDescriptor.fetchLimit = 1_000
        guard let sessions = try? context.fetch(sessionDescriptor) else {
            return
        }

        for session in sessions where session.radioItemID == nil {
            guard let rig = session.myRig, !rig.isEmpty else {
                continue
            }
            if let match = lookupRadio(rig, in: nameIndex) {
                session.radioItemID = match
            }
        }
    }

    private static func buildNameIndex(
        _ radios: [EquipmentItem]
    ) -> [String: UUID] {
        var index: [String: UUID] = [:]
        for radio in radios {
            index[radio.displayName.lowercased()] = radio.id
            if !radio.catalogName.isEmpty {
                index[radio.catalogName.lowercased()] = radio.id
            }
            if let nickname = radio.nickname, !nickname.isEmpty {
                index[nickname.lowercased()] = radio.id
            }
        }
        return index
    }

    private static func lookupRadio(
        _ rigString: String,
        in index: [String: UUID]
    ) -> UUID? {
        let lower = rigString.lowercased()
        if let hit = index[lower] {
            return hit
        }
        // Fuzzy: any indexed name contained in or containing the rig string
        if let key = index.keys.first(where: { lower.contains($0) || $0.contains(lower) }) {
            return index[key]
        }
        return nil
    }
}
