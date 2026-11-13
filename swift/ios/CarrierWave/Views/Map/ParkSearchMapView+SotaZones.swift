import CarrierWaveCore
import CarrierWaveData
import CoreLocation
import MapKit
import SwiftUI

// MARK: - SOTA Activation Zone Loading

extension ParkSearchMapView {
    /// Zones are tiny; only fetch/render once zoomed in tighter than this span.
    nonisolated static let sotaZoneSpanGate = 0.5
    /// Max summits to request zones for per fetch (nearest to viewport center).
    nonisolated static let maxZoneSummitsPerRequest = 250

    /// Zones to render: viewport-culled, only when the toggle is on and zoomed in.
    var sotaZones: [SOTAZone] {
        guard showSotaZones,
              let region = lastVisibleRegion,
              region.span.latitudeDelta < Self.sotaZoneSpanGate
        else {
            return []
        }
        return sotaZonesByCode.values.filter { $0.intersects(region: region) }
    }

    /// Seed the in-memory zone dictionary from the bulk SOTAZonesCache.
    /// Cheap when the cache is empty; lets the map render pre-fetched zones
    /// the instant the toggle goes on instead of waiting for the viewport
    /// fetcher to fill them in.
    func loadCachedSotaZones() async {
        await SOTAZonesCache.shared.ensureLoaded()
        let cached = await SOTAZonesCache.shared.zonesSnapshot()
        guard !cached.isEmpty else {
            return
        }
        await MainActor.run {
            for (code, zone) in cached where sotaZonesByCode[code] == nil {
                sotaZonesByCode[code] = zone
            }
        }
    }

    func fetchSotaZonesForRegion(_ region: MKCoordinateRegion) {
        guard ExperimentalFeature.isEnabled(.activityLayers),
              showSotaZones,
              region.span.latitudeDelta < Self.sotaZoneSpanGate
        else {
            return
        }
        sotaZoneFetchTask?.cancel()
        let summits = visibleSummits
        sotaZoneFetchTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else {
                return
            }
            let codes = await Self.zoneSummitCodes(summits: summits, region: region)
            guard !codes.isEmpty else {
                return
            }
            await loadZones(codes: codes)
        }
    }

    /// Codes of visible summits, nearest to the viewport center first, capped and
    /// filtered to those not already loaded. Runs off the main actor (the summit
    /// set is large).
    private static func zoneSummitCodes(
        summits: [SOTASummit],
        region: MKCoordinateRegion
    ) async -> [String] {
        await Task.detached(priority: .userInitiated) {
            let west = region.center.longitude - region.span.longitudeDelta / 2
            let east = region.center.longitude + region.span.longitudeDelta / 2
            let south = region.center.latitude - region.span.latitudeDelta / 2
            let north = region.center.latitude + region.span.latitudeDelta / 2
            let centerLat = region.center.latitude
            let centerLon = region.center.longitude

            let visible = summits.compactMap { summit -> (SOTASummit, Double)? in
                guard let lat = summit.latitude, let lon = summit.longitude,
                      lon >= west, lon <= east, lat >= south, lat <= north
                else {
                    return nil
                }
                let dist = abs(lat - centerLat) + abs(lon - centerLon)
                return (summit, dist)
            }
            .sorted { $0.1 < $1.1 }
            .prefix(maxZoneSummitsPerRequest)

            return visible.map { summit, _ in summit.code }
        }.value
    }

    /// Read cached activation zones for the given summit codes via
    /// `ParkMapApi.sotaZonesFor` — a pure cached read of the store's `sota_zone`
    /// table (populated by External Data's bulk zone refresh; no network here).
    /// Codes with no cached zone are simply absent.
    private func loadZones(codes: [String]) async {
        do {
            let known = Set(sotaZonesByCode.keys)
            let pending = codes.filter { !known.contains($0) }
            guard !pending.isEmpty else {
                return
            }
            let api = try await ParkMapAccess.api()
            let boundaries = try await Task.detached(priority: .userInitiated) {
                try api.sotaZonesFor(codes: pending)
            }.value
            guard !Task.isCancelled else {
                return
            }
            let parsed = await Task.detached(priority: .userInitiated) {
                boundaries.compactMap { SOTAZone.from(ffi: $0) }
            }.value
            if !parsed.isEmpty {
                mergeSotaZones(parsed)
            }
        } catch {
            RadioService.shared.addLog(.error, "SOTA zone read failed: \(error)")
        }
    }

    /// Merge new zones, evicting the farthest from the viewport center over the cap.
    func mergeSotaZones(_ new: [SOTAZone]) {
        var byCode = sotaZonesByCode
        for zone in new {
            byCode[zone.code] = zone
        }
        let maxCached = 400
        if byCode.count > maxCached, let region = lastVisibleRegion {
            let centerLat = region.center.latitude
            let centerLon = region.center.longitude
            let newCodes = Set(new.map(\.code))
            let others = byCode.filter { !newCodes.contains($0.key) }
            let sorted = others.sorted { lhs, rhs in
                let distA = abs(lhs.value.bbox.centerLat - centerLat)
                    + abs(lhs.value.bbox.centerLon - centerLon)
                let distB = abs(rhs.value.bbox.centerLat - centerLat)
                    + abs(rhs.value.bbox.centerLon - centerLon)
                return distA < distB
            }
            let keepCount = max(0, maxCached - new.count)
            var kept = Dictionary(
                sorted.prefix(keepCount).map { ($0.key, $0.value) },
                uniquingKeysWith: { first, _ in first }
            )
            for zone in new {
                kept[zone.code] = zone
            }
            byCode = kept
        }
        sotaZonesByCode = byCode
    }
}
