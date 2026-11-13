import CarrierWaveData
import Foundation
import OSLog

// MARK: - CustomEquipmentSubmitter

/// Fire-and-forget submitter that sends custom equipment specs to the
/// activities server for potential catalog inclusion. Deduplicates by
/// tracking which items have already been submitted.
@MainActor
final class CustomEquipmentSubmitter {
    // MARK: Internal

    static let shared = CustomEquipmentSubmitter()

    /// Submit a custom equipment item if not already submitted.
    func submitIfNeeded(_ item: EquipmentItem) {
        guard item.isCustom, !isSubmitted(item.catalogId) else {
            return
        }
        submit(item)
    }

    /// Submit (or re-submit) a custom equipment item unconditionally.
    /// Used when specs are edited after initial creation.
    func submit(_ item: EquipmentItem) {
        guard item.isCustom else {
            return
        }

        let payload = EquipmentSubmissionPayload(
            name: item.catalogName,
            manufacturer: item.manufacturer,
            category: item.categoryRawValue,
            bands: item.bands,
            modes: item.modes,
            maxPowerWatts: item.maxPowerWatts,
            portability: item.portabilityRawValue,
            weightGrams: nil
        )

        Task {
            await send(payload, catalogId: item.catalogId)
        }
    }

    /// Submit from a snapshot (for use from migration sheet).
    func submitCustomSnapshot(
        name: String,
        category: CarrierWaveData.EquipmentCategory,
        catalogId: String
    ) {
        guard catalogId.hasPrefix("custom-") else {
            return
        }
        guard !isSubmitted(catalogId) else {
            return
        }

        let payload = EquipmentSubmissionPayload(
            name: name,
            manufacturer: "",
            category: category.rawValue,
            bands: [],
            modes: [],
            maxPowerWatts: nil,
            portability: "portable",
            weightGrams: nil
        )

        Task {
            await send(payload, catalogId: catalogId)
        }
    }

    // MARK: Private

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "CarrierWave",
        category: "CustomEquipmentSubmitter"
    )

    private let client = ActivitiesClient()

    private func send(
        _ payload: EquipmentSubmissionPayload,
        catalogId: String
    ) async {
        do {
            try await client.submitCustomEquipment(payload)
            markSubmitted(catalogId)
            Self.logger.debug(
                "Submitted custom equipment: \(payload.name)"
            )
        } catch {
            Self.logger.error(
                "Failed to submit custom equipment: \(error)"
            )
        }
    }

    private func isSubmitted(_ catalogId: String) -> Bool {
        UserDefaults.standard.bool(
            forKey: "equipmentSubmitted.\(catalogId)"
        )
    }

    private func markSubmitted(_ catalogId: String) {
        UserDefaults.standard.set(
            true, forKey: "equipmentSubmitted.\(catalogId)"
        )
    }
}
