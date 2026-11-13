import CarrierWaveData
import UIKit

// MARK: - EquipmentCatalogService

/// Serves the equipment catalog from the shared Rust reference-data core.
/// Download, ETag handling, and 24-hour freshness live in `ReferenceDataApi`;
/// this service keeps the in-memory `CatalogEntry` surface for fuzzy search
/// and inventory matching.
@MainActor
@Observable
final class EquipmentCatalogService {
    // MARK: Lifecycle

    init() {}

    // MARK: Internal

    static let shared = EquipmentCatalogService()

    /// The loaded catalog entries. Empty until `loadAndRefresh()` completes.
    private(set) var catalog: [CatalogEntry] = []

    /// Whether a download is in progress.
    private(set) var isLoading = false

    /// When the remote catalog was last checked (not necessarily updated).
    private(set) var lastChecked: Date?

    /// Load cached entries from the store, then let the core check remote
    /// if stale (>24 hours). Store reads run off the main thread — only the
    /// final assignments hop back for the @Observable mutations.
    func loadAndRefresh() async {
        guard let api = try? await ReferenceData.api() else {
            return
        }

        if let cached = await Self.readEntries(api), !cached.isEmpty {
            catalog = cached
            lastChecked = await Self.readLastChecked(api)
        }

        await refresh(api: api, force: false)
    }

    /// Force re-download from remote, ignoring cache freshness.
    func forceRefresh() async {
        guard let api = try? await ReferenceData.api() else {
            return
        }
        await refresh(api: api, force: true)
    }

    // MARK: Private

    /// Read cached catalog entries from the encrypted store off main.
    nonisolated private static func readEntries(
        _ api: ReferenceDataApi
    ) async -> [CatalogEntry]? {
        await Task.detached {
            guard let entries = try? api.equipmentEntries() else {
                return nil
            }
            return entries.map(Self.catalogEntry(from:))
        }.value
    }

    /// Read the last successful fetch time from the store off main.
    nonisolated private static func readLastChecked(
        _ api: ReferenceDataApi
    ) async -> Date? {
        await Task.detached {
            guard let fetchedAt = try? api.status().equipmentEntries.fetchedAt else {
                return nil
            }
            return Date(timeIntervalSince1970: TimeInterval(fetchedAt))
        }.value
    }

    nonisolated private static func catalogEntry(
        from entry: FfiEquipmentCatalogEntry
    ) -> CatalogEntry {
        CatalogEntry(
            id: entry.id,
            name: entry.name,
            manufacturer: entry.manufacturer ?? "",
            category: CarrierWaveData.EquipmentCategory(
                rawValue: entry.category ?? ""
            ) ?? .accessory,
            bands: entry.bands,
            modes: entry.modes.compactMap { OperatingMode(rawValue: $0) },
            maxPowerWatts: entry.maxPowerWatts.map { Int($0) },
            portability: PortabilityClass(rawValue: entry.portability ?? "") ?? .portable,
            weightGrams: entry.weightGrams.map { Int($0) },
            description: entry.description,
            aliases: entry.aliases,
            imageURL: entry.imageUrl,
            antennaConnector: entry.antennaConnector,
            powerConnector: entry.powerConnector,
            keyJack: entry.keyJack,
            micJack: entry.micJack
        )
    }

    private func refresh(api: ReferenceDataApi, force: Bool) async {
        guard !isLoading else {
            return
        }
        isLoading = true
        defer { isLoading = false }

        // The catalog endpoint is unauthenticated; the core handles the
        // ETag-conditional request and TTL (`refreshed == false` on 304
        // or TTL-fresh).
        guard let outcome = try? await api.refreshEquipmentCatalog(bearer: nil, force: force) else {
            return
        }

        if outcome.refreshed, let entries = await Self.readEntries(api) {
            catalog = entries
        }
        lastChecked = await Self.readLastChecked(api)
    }
}
