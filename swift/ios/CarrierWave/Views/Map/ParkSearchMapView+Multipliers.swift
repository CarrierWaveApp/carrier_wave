import CarrierWaveCore
import CoreLocation
import MapKit
import SwiftUI

// MARK: - Multiplier Detection

extension ParkSearchMapView {
    /// Max summits to scan for overlaps (viewport-bounded, nearest center).
    nonisolated static let maxMultiplierSummits = 800

    /// Open the multipliers sheet and kick off the (off-main) overlap scan.
    func presentMultipliers() {
        multiplierCandidates = []
        isFindingMultipliers = true
        showMultipliersSheet = true
        Task { await computeMultipliers() }
    }

    /// Recenter the map on a chosen multiplier candidate.
    func zoomToMultiplier(_ coordinate: CLLocationCoordinate2D) {
        withAnimation {
            mapRegion = MKCoordinateRegion(
                center: coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
            )
        }
    }

    /// Scan the viewport's loaded geometry for activation multipliers via
    /// `ParkMapApi.findMultipliers`. The refs of everything currently loaded on
    /// the map (summits, park boundaries, WWFF-borrow refs, counties) are passed
    /// in; Rust resolves their rings from the GIS caches and runs the geometric
    /// detection, returning one merged candidate per source location.
    private func computeMultipliers() async {
        let region = lastVisibleRegion ?? mapRegion
        // Snapshot the viewport-relevant ref sets on the main actor.
        let summitRefs = Array(
            visibleSummits
                .filter { summit in
                    guard let lat = summit.latitude, let lon = summit.longitude else {
                        return false
                    }
                    return Self.point(lat: lat, lon: lon, inside: region)
                }
                .prefix(Self.maxMultiplierSummits)
                .map(\.code)
        )
        let parkRefs = boundaries.map(\.reference)
        let wwffRefs = wwffByCode.values
            .filter { $0.hasBoundary && $0.intersects(region: region) }
            .map(\.code)
        let countyRefs = adminBoundariesByID.values
            .filter { $0.kind == .county && $0.intersects(region: region) }
            .map(\.id)

        do {
            let api = try await ParkMapAccess.api()
            let found = try await Task.detached(priority: .userInitiated) {
                try api.findMultipliers(
                    summitRefs: summitRefs,
                    parkRefs: parkRefs,
                    wwffBorrowedRefs: wwffRefs,
                    countyRefs: countyRefs
                )
            }.value
            guard !Task.isCancelled else {
                return
            }
            multiplierCandidates = found.compactMap(MultiplierCandidate.from(ffi:))
        } catch {
            RadioService.shared.addLog(.error, "Multiplier scan failed: \(error)")
            multiplierCandidates = []
        }
        isFindingMultipliers = false
    }

    nonisolated private static func point(lat: Double, lon: Double, inside region: MKCoordinateRegion) -> Bool {
        let west = region.center.longitude - region.span.longitudeDelta / 2
        let east = region.center.longitude + region.span.longitudeDelta / 2
        let south = region.center.latitude - region.span.latitudeDelta / 2
        let north = region.center.latitude + region.span.latitudeDelta / 2
        return lon >= west && lon <= east && lat >= south && lat <= north
    }
}
