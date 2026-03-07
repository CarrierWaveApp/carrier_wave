// Session Detail View - Map
//
// Map preview for the session detail header. Uses a camera nudge
// on globe (.imagery) style to force MapKit to render annotations.

import CarrierWaveData
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
        return sessionMapView(
            mappable: mappable, myCoord: myCoord, isWide: isWide,
            qsoCoords: qsoCoords
        )
    }

    private func sessionMapView(
        mappable: [QSO], myCoord: CLLocationCoordinate2D?,
        isWide: Bool, qsoCoords: [CLLocationCoordinate2D]
    ) -> some View {
        Map(position: $mapCamera) {
            ForEach(mappable) { qso in
                if let grid = qso.theirGrid,
                   let coord = MaidenheadConverter.coordinate(from: grid)
                {
                    Annotation(qso.callsign, coordinate: coord, anchor: .bottom) {
                        MapPinMarker(
                            color: RSTColorHelper.color(
                                rstSent: qso.rstSent,
                                rstReceived: qso.rstReceived
                            )
                        )
                    }
                }
            }
            if let myCoord {
                Annotation("Me", coordinate: myCoord, anchor: .bottom) {
                    MapPinMarker(color: .blue, size: 12)
                }
                ForEach(mappable) { qso in
                    if let grid = qso.theirGrid,
                       let theirCoord = MaidenheadConverter.coordinate(from: grid)
                    {
                        MapPolyline(
                            coordinates: ActivationMapHelpers.geodesicPath(
                                from: myCoord, to: theirCoord, segments: 20
                            )
                        )
                        .stroke(.white.opacity(0.5), lineWidth: 2.5)
                    }
                }
            }
        }
        .mapStyle(isWide
            ? .imagery(elevation: .realistic)
            : .standard(elevation: .realistic))
        .allowsHitTesting(false)
        .task {
            mapCamera = ActivationMapHelpers.mapCameraPosition(
                qsoCoordinates: qsoCoords, myCoordinate: myCoord
            )
            if isWide {
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
