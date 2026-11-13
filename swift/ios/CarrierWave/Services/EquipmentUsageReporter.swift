import CarrierWaveData
import Foundation
import OSLog
import SwiftData

// MARK: - EquipmentUsageReporter

/// Reports anonymous equipment usage to the activities server at session end.
/// Follows the PerfUploader pattern: fire-and-forget with retry queue.
actor EquipmentUsageReporter {
    // MARK: Internal

    static let shared = EquipmentUsageReporter()

    /// Record equipment usage from a completed session.
    /// Looks up EquipmentItems by display name to get catalog IDs.
    func recordUsage(
        session: SessionEquipmentInfo,
        container: ModelContainer
    ) async {
        let items = await resolveEquipment(
            radio: session.radio, antenna: session.antenna,
            key: session.key, mic: session.mic, container: container
        )
        let mode = session.mode
        let band = session.band
        let program = session.program

        guard !items.isEmpty else {
            return
        }

        // Collect all catalog IDs for pairing
        let allIds = items.map(\.catalogId)

        var entries: [UsageEntry] = []
        for item in items {
            let pairedIds = allIds.filter { $0 != item.catalogId }
            entries.append(UsageEntry(
                catalogId: item.catalogId,
                category: item.categoryRawValue,
                isCustom: item.isCustom,
                customName: item.isCustom ? item.catalogName : nil,
                customManufacturer: item.isCustom ? item.manufacturer : nil,
                customBands: item.isCustom ? item.bands : [],
                customModes: item.isCustom ? item.modes : [],
                customMaxPowerWatts: item.isCustom ? item.maxPowerWatts : nil,
                customPortability: item.isCustom ? item.portabilityRawValue : nil,
                sessionMode: mode,
                sessionBand: band,
                sessionProgram: program,
                pairedWith: pairedIds
            ))
        }

        await send(entries)
    }

    // MARK: Private

    nonisolated private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "CarrierWave",
        category: "EquipmentUsageReporter"
    )

    private var baseURL: String {
        ActivitiesClient.resolvedBaseURL
    }

    private func send(_ entries: [UsageEntry]) async {
        let appVersion = Bundle.main.infoDictionary?[
            "CFBundleShortVersionString"
        ] as? String

        let payload = UsagePayload(
            metadata: UsageMetadata(appVersion: appVersion),
            usage: entries
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let body = try? encoder.encode(payload)
        else {
            return
        }

        let urlString = ActivitiesClient.normalizeBase(baseURL)
            + "/v1/telemetry/equipment-usage"
        guard let url = URL(string: urlString) else {
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("CarrierWave/1.0", forHTTPHeaderField: "User-Agent")
        request.httpBody = body

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse,
               (200 ... 299).contains(http.statusCode)
            {
                Self.logger.debug(
                    "Reported \(entries.count) equipment usage entries"
                )
            }
        } catch {
            Self.logger.error("Equipment usage report failed: \(error)")
        }
    }

    @MainActor
    private func resolveEquipment(
        radio: String?,
        antenna: String?,
        key: String?,
        mic: String?,
        container: ModelContainer
    ) -> [EquipmentSnapshot] {
        let context = ModelContext(container)
        var results: [EquipmentSnapshot] = []

        let names: [(String, String)] = [
            (radio ?? "", "radio"),
            (antenna ?? "", "antenna"),
            (key ?? "", "key"),
            (mic ?? "", "microphone"),
        ]

        for (name, categoryRaw) in names where !name.isEmpty {
            var descriptor = FetchDescriptor<EquipmentItem>()
            descriptor.fetchLimit = 1
            descriptor.predicate = #Predicate<EquipmentItem> { item in
                item.categoryRawValue == categoryRaw
                    && item.catalogName == name
            }

            if let item = try? context.fetch(descriptor).first {
                results.append(EquipmentSnapshot(item: item))
                continue
            }

            // Try nickname match
            let nickName = name
            descriptor.predicate = #Predicate<EquipmentItem> { item in
                item.categoryRawValue == categoryRaw
                    && item.nickname == nickName
            }
            if let item = try? context.fetch(descriptor).first {
                results.append(EquipmentSnapshot(item: item))
            }
        }

        return results
    }
}

// MARK: - SessionEquipmentInfo

/// Sendable snapshot of session equipment fields for the usage reporter.
nonisolated struct SessionEquipmentInfo {
    let radio: String?
    let antenna: String?
    let key: String?
    let mic: String?
    let mode: String?
    let band: String?
    let program: String?
}

// MARK: - EquipmentSnapshot

nonisolated private struct EquipmentSnapshot {
    // MARK: Lifecycle

    @MainActor
    init(item: EquipmentItem) {
        catalogId = item.catalogId
        catalogName = item.catalogName
        categoryRawValue = item.categoryRawValue
        isCustom = item.isCustom
        manufacturer = item.manufacturer
        bands = item.bands
        modes = item.modes
        maxPowerWatts = item.maxPowerWatts
        portabilityRawValue = item.portabilityRawValue
    }

    // MARK: Internal

    let catalogId: String
    let catalogName: String
    let categoryRawValue: String
    let isCustom: Bool
    let manufacturer: String
    let bands: [String]
    let modes: [String]
    let maxPowerWatts: Int?
    let portabilityRawValue: String
}

// MARK: - UsagePayload

nonisolated private struct UsagePayload: Codable {
    let metadata: UsageMetadata
    let usage: [UsageEntry]
}

// MARK: - UsageMetadata

nonisolated private struct UsageMetadata: Codable {
    enum CodingKeys: String, CodingKey {
        case appVersion = "app_version"
    }

    let appVersion: String?
}

// MARK: - UsageEntry

nonisolated private struct UsageEntry: Codable {
    enum CodingKeys: String, CodingKey {
        case catalogId = "catalog_id"
        case category
        case isCustom = "is_custom"
        case customName = "custom_name"
        case customManufacturer = "custom_manufacturer"
        case customBands = "custom_bands"
        case customModes = "custom_modes"
        case customMaxPowerWatts = "custom_max_power_watts"
        case customPortability = "custom_portability"
        case sessionMode = "session_mode"
        case sessionBand = "session_band"
        case sessionProgram = "session_program"
        case pairedWith = "paired_with"
    }

    let catalogId: String
    let category: String
    let isCustom: Bool
    let customName: String?
    let customManufacturer: String?
    let customBands: [String]
    let customModes: [String]
    let customMaxPowerWatts: Int?
    let customPortability: String?
    let sessionMode: String?
    let sessionBand: String?
    let sessionProgram: String?
    let pairedWith: [String]
}
