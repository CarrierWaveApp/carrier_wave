// Session QSO Map
//
// Shared map view for displaying QSOs from a logging session with RST-colored
// pins, geodesic arcs, and rove stop overlays. Used by both SessionMapPanelView
// (phone logger panel) and SidebarMapView (iPad sidebar).

import CarrierWaveCore
import CarrierWaveData
import CoreLocation
import MapKit
import SwiftUI

// MARK: - SessionQSOMap

struct SessionQSOMap: View {
    // MARK: Internal

    let sessionQSOs: [QSO]
    let myGrid: String?
    var roveStops: [RoveStop] = []

    var body: some View {
        if mappableQSOs.isEmpty, roveStopCoordinates.isEmpty {
            emptyView
        } else {
            mapContent
        }
    }

    // MARK: Private

    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var hasSetInitialCamera = false
    @State private var isWideSpan = false

    private var mappableQSOs: [QSO] {
        sessionQSOs.filter { qso in
            guard let grid = qso.theirGrid, grid.count >= 4 else {
                return false
            }
            return maidenheadCoordinate(grid: grid) != nil
        }
    }

    private var myCoordinate: CLLocationCoordinate2D? {
        guard let grid = myGrid, grid.count >= 4,
              let coord = maidenheadCoordinate(grid: grid)
        else {
            return nil
        }
        return CLLocationCoordinate2D(latitude: coord.latitude, longitude: coord.longitude)
    }

    private var roveStopCoordinates: [(stop: RoveStop, coordinate: CLLocationCoordinate2D)] {
        roveStops.compactMap { stop in
            let grid = stop.myGrid ?? myGrid
            guard let grid, grid.count >= 4,
                  let coord = maidenheadCoordinate(grid: grid)
            else {
                return nil
            }
            return (
                stop: stop,
                coordinate: CLLocationCoordinate2D(latitude: coord.latitude, longitude: coord.longitude)
            )
        }
    }

    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "map")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("No QSOs with grid squares")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var mapContent: some View {
        Map(position: $cameraPosition) {
            MapContentBuilders.qsoAnnotations(for: mappableQSOs)
            MapContentBuilders.roveStopOverlay(stops: roveStopCoordinates)

            if let myCoord = myCoordinate {
                MapContentBuilders.geodesicArcs(
                    from: myCoord, to: mappableQSOs
                )
            }
        }
        .standardMapStyle(isWideSpan: isWideSpan)
        .task(id: mappableQSOs.count) {
            guard !hasSetInitialCamera else {
                return
            }
            hasSetInitialCamera = true

            var allCoords = mappableQSOs.compactMap { qso -> CLLocationCoordinate2D? in
                guard let grid = qso.theirGrid, let coord = maidenheadCoordinate(grid: grid) else {
                    return nil
                }
                return CLLocationCoordinate2D(latitude: coord.latitude, longitude: coord.longitude)
            }
            allCoords.append(
                contentsOf: roveStopCoordinates.map(\.coordinate)
            )

            isWideSpan = ActivationMapHelpers.requiresGlobeView(
                qsoCoordinates: allCoords,
                myCoordinate: myCoordinate
            )
            cameraPosition = ActivationMapHelpers.mapCameraPosition(
                qsoCoordinates: allCoords,
                myCoordinate: myCoordinate
            )

            // Camera nudge forces MapKit to render annotations on globe style
            if isWideSpan {
                try? await Task.sleep(for: .seconds(0.5))
                nudgeCamera()
            }
        }
    }

    /// Nudge camera slightly to work around MapKit globe annotation rendering bug.
    private func nudgeCamera() {
        guard let region = cameraPosition.region else {
            return
        }
        cameraPosition = .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: region.center.latitude + 0.001,
                longitude: region.center.longitude
            ),
            span: region.span
        ))
    }
}
