// Session Detail View - Map
//
// Map preview for the session detail header. Uses shared MapContentBuilders
// for annotations and arcs. Falls back to ThemedMapImage for custom styles.

import CarrierWaveData
import CoreLocation
import MapKit
import SwiftUI

extension SessionDetailView {
    func mapPreviewContent(
        mappable: [QSO], myCoord: CLLocationCoordinate2D?
    ) -> some View {
        let qsoCoords = mappable.compactMap { qso -> CLLocationCoordinate2D? in
            guard let grid = qso.theirGrid else {
                return nil
            }
            return MaidenheadConverter.coordinate(from: grid)
        }
        let isWide = ActivationMapHelpers.requiresGlobeView(
            qsoCoordinates: qsoCoords, myCoordinate: myCoord
        )
        let style = ShareMapStyle(rawValue: shareMapStyleRaw) ?? .adaptive
        if style.usesCustomRenderer {
            return AnyView(
                ThemedMapImage(
                    coordinates: qsoCoords, myCoordinate: myCoord,
                    style: style
                )
                .allowsHitTesting(false)
            )
        }
        return AnyView(sessionMapView(
            mappable: mappable, myCoord: myCoord,
            isWideSpan: isWide, qsoCoords: qsoCoords
        ))
    }

    private func sessionMapView(
        mappable: [QSO], myCoord: CLLocationCoordinate2D?,
        isWideSpan: Bool, qsoCoords: [CLLocationCoordinate2D]
    ) -> some View {
        Map(position: $mapCamera) {
            MapContentBuilders.qsoAnnotations(for: mappable)

            if let myCoord {
                MapContentBuilders.myLocationMarker(at: myCoord)
                MapContentBuilders.geodesicArcs(
                    from: myCoord, to: mappable
                )
            }
        }
        .standardMapStyle(isWideSpan: isWideSpan)
        .allowsHitTesting(false)
        // Keyed on the QSO count so the preview re-frames when the session's
        // QSOs change underneath it (e.g. after a session merge).
        .task(id: mappable.count) {
            mapCamera = ActivationMapHelpers.mapCameraPosition(
                qsoCoordinates: qsoCoords, myCoordinate: myCoord
            )
            // Camera nudge forces MapKit to render annotations on globe style
            if isWideSpan {
                try? await Task.sleep(for: .seconds(0.5))
                nudgeMapCamera()
            }
        }
    }

    private func nudgeMapCamera() {
        guard let region = mapCamera.region else {
            return
        }
        mapCamera = .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: region.center.latitude + 0.001,
                longitude: region.center.longitude
            ),
            span: region.span
        ))
    }
}
