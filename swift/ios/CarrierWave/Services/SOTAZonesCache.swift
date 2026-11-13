// SOTA Zones Cache
//
// In-memory query surface over the Rust reference-data core's SOTA
// activation-zone table. The chunked download, pending-tail tracking, and
// persistence live in `ReferenceDataApi` (`refreshSotaZones` reads summit
// inputs from the cw-store `sota_summit` table and only requests codes
// without a cached zone); this actor hydrates the stored GeoJSON geometry
// strings into renderable polygons for the map.

import CarrierWaveData
import CoreLocation
import Foundation

// MARK: - SOTAZonesCache

actor SOTAZonesCache {
    // MARK: Lifecycle

    private init() {}

    // MARK: Internal

    static let shared = SOTAZonesCache()

    var zoneCount: Int {
        zonesByCode.count
    }

    /// Snapshot of cached zones for the map renderer.
    func zonesSnapshot() -> [String: SOTAZone] {
        zonesByCode
    }

    func getStatus() -> ReferenceCacheStatus {
        status
    }

    func getPendingCount() -> Int {
        pendingCount
    }

    /// Hydrate the in-memory zones from the Rust store. No network.
    func ensureLoaded() async {
        guard !isLoaded else {
            return
        }
        status = .loading
        do {
            try await hydrate()
            isLoaded = true
            status = zonesByCode.isEmpty
                ? .notLoaded
                : .loaded(recordCount: zonesByCode.count, downloadedAt: fetchedAt)
        } catch {
            isLoaded = true
            status = .notLoaded
        }
    }

    /// Bulk-fetch zones via the Rust core, then re-hydrate. Rust only
    /// requests summits without a cached zone, so repeat refreshes chase
    /// the pending tail; codes the server hasn't computed yet come back in
    /// `pendingCount` — invoke again later to pick those up.
    func forceRefresh() async throws {
        status = .downloading
        do {
            let api = try await ReferenceData.api()
            let outcome = try await api.refreshSotaZones()
            pendingCount = Int(outcome.pending)
            try await hydrate()
            isLoaded = true
            status = .loaded(recordCount: zonesByCode.count, downloadedAt: fetchedAt)
        } catch {
            status = .failed(error.localizedDescription)
            throw error
        }
    }

    // MARK: Private

    private var zonesByCode: [String: SOTAZone] = [:]
    private var status: ReferenceCacheStatus = .notLoaded
    private var pendingCount = 0
    private var fetchedAt: Date?
    private var isLoaded = false

    /// Decode one stored GeoJSON geometry (Polygon or MultiPolygon,
    /// `[lon, lat]` order) into the shared polygon + bbox representation.
    nonisolated private static func zone(from ffi: FfiSotaZone) -> SOTAZone? {
        guard let geometry = try? JSONDecoder().decode(
            GeoJSONGeometry.self, from: Data(ffi.geometryGeojson.utf8)
        ) else {
            return nil
        }
        let polygons = geometry.polygonRingGroups.compactMap { group -> ZonePolygon? in
            guard let exteriorRaw = group.first else {
                return nil
            }
            let exterior = toCoordinates(exteriorRaw)
            guard exterior.count >= 3 else {
                return nil
            }
            let holes = group.dropFirst()
                .map { toCoordinates($0) }
                .filter { $0.count >= 3 }
            return ZonePolygon(exterior: exterior, holes: holes)
        }
        guard !polygons.isEmpty else {
            return nil
        }
        return SOTAZone(
            code: ffi.code,
            altitudeM: Double(ffi.altitudeM),
            polygons: polygons,
            bbox: ringBoundingBox(polygons.flatMap(\.exterior))
        )
    }

    nonisolated private static func toCoordinates(
        _ ring: [[Double]]
    ) -> [CLLocationCoordinate2D] {
        ring.compactMap { pair -> CLLocationCoordinate2D? in
            guard pair.count >= 2 else {
                return nil
            }
            return CLLocationCoordinate2D(latitude: pair[1], longitude: pair[0])
        }
    }

    /// Page every stored zone out of the Rust core and decode the geometry
    /// strings off this actor (the full set is large).
    private func hydrate() async throws {
        let api = try await ReferenceData.api()
        let hydrated = try await Task.detached(priority: .userInitiated) {
            var zones: [String: SOTAZone] = [:]
            var offset: Int64 = 0
            while true {
                let page = try api.sotaZonesPage(
                    limit: ReferenceData.pageSize, offset: offset
                )
                for ffi in page {
                    if let zone = Self.zone(from: ffi) {
                        zones[zone.code] = zone
                    }
                }
                if Int64(page.count) < ReferenceData.pageSize {
                    break
                }
                offset += Int64(page.count)
            }
            return zones
        }.value
        let dataStatus = try api.status()
        zonesByCode = hydrated
        pendingCount = Int(dataStatus.sotaZonesPending)
        fetchedAt = dataStatus.sotaZones.fetchedAt.map {
            Date(timeIntervalSince1970: TimeInterval($0))
        }
    }
}
