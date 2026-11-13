// DXCC Lookup Service
//
// Loads CTY.dat (bundled or downloaded) and provides callsign-to-DXCC entity
// resolution. Used by SpotAggregator for needed-indicator enrichment and
// by DXCCTrackingView for entity metadata.

import CarrierWaveCore
import CarrierWaveData
import Foundation
import OSLog

// MARK: - DXCCLookupService

/// Loads and caches CTY.dat data for callsign-to-DXCC resolution.
@MainActor
@Observable
final class DXCCLookupService {
    // MARK: Internal

    private(set) var isLoaded = false
    private(set) var entityCount = 0

    /// Look up the DXCC entity for a callsign.
    func lookup(_ callsign: String) -> DXCCEntity? {
        database?.lookup(callsign)
    }

    /// Load the CTY.dat database from bundle or download.
    func loadIfNeeded() async {
        guard !isLoaded else {
            return
        }
        await load()
    }

    // MARK: Private

    private static let ctyURL = URL(
        string: "https://www.country-files.com/bigcty/cty.dat"
    )!

    private static var cachedFilePath: URL {
        let cacheDir = FileManager.default.urls(
            for: .cachesDirectory, in: .userDomainMask
        ).first!
        return cacheDir.appendingPathComponent("cty.dat")
    }

    private var database: CTYDatabase?

    private func load() async {
        // Try bundled file first
        if let bundledURL = Bundle.main.url(
            forResource: "cty", withExtension: "dat"
        ) {
            if let content = try? String(contentsOf: bundledURL, encoding: .ascii) {
                parseAndStore(content)
                return
            }
        }

        // Try cached file (less than 30 days old)
        let cachedFile = Self.cachedFilePath
        if FileManager.default.fileExists(atPath: cachedFile.path) {
            let attrs = try? FileManager.default.attributesOfItem(
                atPath: cachedFile.path
            )
            let modDate = attrs?[.modificationDate] as? Date ?? .distantPast
            let age = Date().timeIntervalSince(modDate)

            if age < 30 * 86_400 {
                if let content = try? String(
                    contentsOf: cachedFile, encoding: .ascii
                ) {
                    parseAndStore(content)
                    return
                }
            }
        }

        // Download fresh copy
        await downloadAndCache()
    }

    private func downloadAndCache() async {
        do {
            let (data, _) = try await URLSession.shared.data(
                from: Self.ctyURL
            )
            guard let content = String(data: data, encoding: .ascii) else {
                return
            }
            try? data.write(to: Self.cachedFilePath)
            parseAndStore(content)
        } catch {
            // Silently fail — entity lookup will return nil
        }
    }

    private func parseAndStore(_ content: String) {
        let db = CTYParser.parse(content)
        database = db
        entityCount = db.entities.count
        isLoaded = true
        seedQueryStore(from: db)
    }

    /// Push parsed DXCC entities into the SQL mirror so the Query Workbench
    /// can resolve `dxcc.entity` joins and the `dxcc_status` view returns
    /// real rows. Fire-and-forget; failures are logged but never block the
    /// in-memory lookup that the rest of the app depends on.
    private func seedQueryStore(from db: CTYDatabase) {
        guard let store = QueryFacade.current else {
            return
        }
        let rows = db.entities.map { entity in
            DXCCRow(
                entity: entity.name,
                prefix: entity.primaryPrefix,
                continent: entity.continent,
                cqZone: entity.cqZone,
                ituZone: entity.ituZone,
                lat: entity.latitude,
                lon: entity.longitude
            )
        }
        Task.detached(priority: .utility) {
            do {
                try await store.seedDXCC(rows)
            } catch {
                Logger(subsystem: "com.jsvana.CWSweep", category: "DXCCLookupService")
                    .error("seedDXCC failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
