import CarrierWaveCore
import CarrierWaveData
import CoreLocation
import MapKit
import SwiftUI

// MARK: - WWFF Loading

extension ParkSearchMapView {
    /// WWFF borrows POTA polygons; only meaningful zoomed in.
    static let wwffSpanGate = 1.0
    /// Max WWFF references to resolve per fetch (nearest to viewport center).
    static let maxWWFFPerFetch = 40

    /// WWFF items to render: viewport-culled, only when toggled on and zoomed in.
    var wwffItems: [WWFFRenderItem] {
        guard showWWFF,
              let region = lastVisibleRegion,
              region.span.latitudeDelta < Self.wwffSpanGate
        else {
            return []
        }
        return wwffByCode.values.filter { $0.intersects(region: region) }
    }

    /// Load the US WWFF (KFF) reference set once (points + names).
    func loadWWFFReferences() async {
        await WWFFReferencesCache.shared.ensureLoaded()
        let refs = await Task.detached(priority: .userInitiated) {
            WWFFReferencesCache.shared.referencesSnapshot().values.filter { ref in
                ref.program.uppercased() == "KFF" && ref.latitude != nil && ref.longitude != nil
            }
        }.value
        wwffReferences = Array(refs)
    }

    func fetchWWFFForRegion(_ region: MKCoordinateRegion) {
        guard ExperimentalFeature.isEnabled(.activityLayers),
              showWWFF,
              region.span.latitudeDelta < Self.wwffSpanGate
        else {
            return
        }
        wwffFetchTask?.cancel()
        wwffFetchTask = Task {
            if wwffReferences.isEmpty {
                await loadWWFFReferences()
            }
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else {
                return
            }
            let refs = wwffReferences
            let visible = Self.visibleWWFF(refs: refs, region: region)
            let known = Set(wwffByCode.keys)
            let pending = visible.filter { !known.contains($0.reference) }
            guard !pending.isEmpty else {
                return
            }
            await loadWWFFItems(for: pending)
        }
    }

    /// Visible KFF references within the viewport, nearest to center, capped.
    private static func visibleWWFF(
        refs: [WWFFReference],
        region: MKCoordinateRegion
    ) -> [WWFFReference] {
        let west = region.center.longitude - region.span.longitudeDelta / 2
        let east = region.center.longitude + region.span.longitudeDelta / 2
        let south = region.center.latitude - region.span.latitudeDelta / 2
        let north = region.center.latitude + region.span.latitudeDelta / 2
        let centerLat = region.center.latitude
        let centerLon = region.center.longitude

        return refs.compactMap { ref -> (WWFFReference, Double)? in
            guard let lat = ref.latitude, let lon = ref.longitude,
                  lon >= west, lon <= east, lat >= south, lat <= north
            else {
                return nil
            }
            return (ref, abs(lat - centerLat) + abs(lon - centerLon))
        }
        .sorted { $0.1 < $1.1 }
        .prefix(maxWWFFPerFetch)
        .map(\.0)
    }

    /// Resolve borrowed POTA boundaries (or markers) for the given WWFF refs via
    /// `ParkMapApi.wwffBorrowedBoundaries` — the KFF-####→US-#### borrow +
    /// cache-first POTA resolution now lives in Rust. Refs whose POTA park has no
    /// boundary are absent from the result; those render as a bare marker at the
    /// WWFF reference's own coordinate.
    private func loadWWFFItems(for refs: [WWFFReference]) async {
        let wwffRefs = refs.map(\.reference)
        let boundaries: [String: FfiGeoBoundary]
        do {
            let api = try await ParkMapAccess.api()
            let fetched = try await Task.detached(priority: .userInitiated) {
                try await api.wwffBorrowedBoundaries(wwffRefs: wwffRefs)
            }.value
            boundaries = Dictionary(
                fetched.map { ($0.reference, $0) },
                uniquingKeysWith: { first, _ in first }
            )
        } catch {
            RadioService.shared.addLog(.error, "WWFF boundary fetch failed: \(error)")
            boundaries = [:]
        }
        guard !Task.isCancelled else {
            return
        }

        let items: [WWFFRenderItem] = refs.compactMap { ref in
            guard let lat = ref.latitude, let lon = ref.longitude else {
                return nil
            }
            let center = CLLocationCoordinate2D(latitude: lat, longitude: lon)
            if let boundary = boundaries[ref.reference],
               let parkBoundary = ParkBoundary.from(ffi: boundary)
            {
                let polygons = parkBoundary.mergedPolygons.map {
                    ZonePolygon(exterior: $0.exterior, holes: $0.holes)
                }
                return WWFFRenderItem(
                    code: ref.reference, name: ref.name, center: center,
                    polygons: polygons, bbox: parkBoundary.bbox
                )
            }
            return WWFFRenderItem(
                code: ref.reference, name: ref.name, center: center,
                polygons: [], bbox: markerBBox(around: center)
            )
        }
        if !items.isEmpty {
            mergeWWFF(items)
        }
    }

    /// Merge new WWFF items, evicting the farthest from the viewport over the cap.
    func mergeWWFF(_ new: [WWFFRenderItem]) {
        var byCode = wwffByCode
        for item in new {
            byCode[item.code] = item
        }
        let maxCached = 300
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
            for item in new {
                kept[item.code] = item
            }
            byCode = kept
        }
        wwffByCode = byCode
    }

    private func markerBBox(around center: CLLocationCoordinate2D) -> RingBBox {
        let pad = 0.004
        return RingBBox(
            minLat: center.latitude - pad, maxLat: center.latitude + pad,
            minLon: center.longitude - pad, maxLon: center.longitude + pad
        )
    }
}
