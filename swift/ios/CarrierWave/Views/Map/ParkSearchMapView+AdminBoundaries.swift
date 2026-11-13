import CarrierWaveCore
import CarrierWaveData
import CoreLocation
import MapKit
import SwiftUI

// MARK: - Admin Boundary Loading

extension ParkSearchMapView {
    /// Counties only render once zoomed in tighter than this latitude span
    /// (degrees) — there are ~3,143 of them, so they'd carpet a wide view.
    static let adminCountySpanGate = 6.0
    /// Never fetch admin boundaries when zoomed out past this span.
    static let adminMaxSpan = 60.0

    /// Admin boundaries to render: viewport-culled, gated by the per-kind
    /// toggles, with counties suppressed until zoomed in.
    var adminBoundaries: [AdminBoundary] {
        guard let region = lastVisibleRegion else {
            return adminBoundariesByID.values.filter { $0.kind == .state && showStates }
        }
        let countiesVisible = showCounties
            && region.span.latitudeDelta < Self.adminCountySpanGate
        return adminBoundariesByID.values.filter { boundary in
            guard boundary.intersects(region: region) else {
                return false
            }
            switch boundary.kind {
            case .state: return showStates
            case .county: return countiesVisible
            }
        }
    }

    func fetchAdminForRegion(_ region: MKCoordinateRegion) {
        guard ExperimentalFeature.isEnabled(.activityLayers) else {
            return
        }
        let wantStates = showStates
        let wantCounties = showCounties
            && region.span.latitudeDelta < Self.adminCountySpanGate
        guard wantStates || wantCounties,
              region.span.latitudeDelta < Self.adminMaxSpan
        else {
            return
        }

        adminFetchTask?.cancel()

        let bbox = FfiBoundingBox(mapRegion: region)
        // Only one kind wanted → filter server-side; both → fetch all.
        let kind: String? = wantStates && wantCounties
            ? nil
            : (wantStates ? "state" : "county")
        let tolerance = simplifyTolerance(for: region)

        adminFetchTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else {
                return
            }
            let known = Set(adminBoundariesByID.keys)
            await loadAdmin(bbox: bbox, kind: kind, tolerance: tolerance, known: known)
        }
    }

    /// Fetch admin boundaries via `ParkMapApi.adminBoundariesInBox` (cache-through
    /// the `"admin"` GIS cache), decode into renderable boundaries off-main, and
    /// merge in the ones we don't already hold.
    private func loadAdmin(
        bbox: FfiBoundingBox,
        kind: String?,
        tolerance: Double,
        known: Set<String>
    ) async {
        do {
            let api = try await ParkMapAccess.api()
            let boundaries = try await Task.detached(priority: .userInitiated) {
                try await api.adminBoundariesInBox(
                    bbox: bbox, kind: kind, limit: 2_000, simplify: tolerance
                )
            }.value
            guard !Task.isCancelled else {
                return
            }
            let parsed = await Task.detached(priority: .userInitiated) {
                boundaries.compactMap { boundary -> AdminBoundary? in
                    guard !known.contains(boundary.reference) else {
                        return nil
                    }
                    return AdminBoundary.from(ffi: boundary)
                }
            }.value
            if !parsed.isEmpty {
                mergeAdminBoundaries(parsed)
            }
        } catch {
            RadioService.shared.addLog(.error, "Admin boundary fetch failed: \(error)")
        }
    }

    /// Merge new admin boundaries into the cache, evicting the farthest from the
    /// viewport center when over the limit (mirrors `mergeBoundaries`).
    func mergeAdminBoundaries(_ new: [AdminBoundary]) {
        var byID = adminBoundariesByID
        for boundary in new {
            byID[boundary.id] = boundary
        }
        let maxCached = 800
        if byID.count > maxCached, let region = lastVisibleRegion {
            let centerLat = region.center.latitude
            let centerLon = region.center.longitude
            let newIDs = Set(new.map(\.id))
            let others = byID.filter { !newIDs.contains($0.key) }
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
            for boundary in new {
                kept[boundary.id] = boundary
            }
            byID = kept
        }
        adminBoundariesByID = byID
    }
}
