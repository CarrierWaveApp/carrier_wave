// Spots Mini Map View
//
// Displays spotter locations on a map with arcs to the target station.
// Used in RBNPanelView to visualize RBN and POTA spot coverage.

import CarrierWaveCore
import CarrierWaveData
import CoreLocation
import MapKit
import SwiftUI

// MARK: - SpotsMiniMapView

struct SpotsMiniMapView: View {
    // MARK: Internal

    let spots: [UnifiedSpot]
    let targetCallsign: String
    let targetGrid: String?

    var body: some View {
        Map {
            // Target callsign marker (the person being spotted)
            if let targetCoord = targetCoordinate {
                Annotation(targetCallsign, coordinate: targetCoord) {
                    MapPinMarker(color: .red, size: 12)
                }

                // Geodesic arcs from target to each spotter
                ForEach(spotAnnotations) { annotation in
                    MapContentBuilders.geodesicArc(
                        from: targetCoord, to: annotation.coordinate
                    )
                }
            }

            // Spotter markers
            ForEach(spotAnnotations) { annotation in
                Annotation(annotation.title, coordinate: annotation.coordinate) {
                    MapPinMarker(color: annotation.color)
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic))
    }

    // MARK: Private

    private var targetCoordinate: CLLocationCoordinate2D? {
        guard let grid = targetGrid,
              let coord = maidenheadCoordinate(grid: grid)
        else {
            return nil
        }
        return CLLocationCoordinate2D(latitude: coord.latitude, longitude: coord.longitude)
    }

    private var spotAnnotations: [SpotMapAnnotation] {
        spots.compactMap { spot in
            guard let grid = spot.spotterGrid,
                  let coord = maidenheadCoordinate(grid: grid)
            else {
                return nil
            }

            let color: Color
            let size: CGFloat

            switch spot.source {
            case .rbn:
                if let snr = spot.snr {
                    color = snrColor(snr)
                    // Shared Rust timeline curve (10-36pt) — same size math as TimelineMapView,
                    // converged with the Android mini-map (Phase B).
                    size = CGFloat(timelineSnrMarkerSize(snr: Int64(snr)))
                } else {
                    color = .blue
                    size = 10
                }
            case .pota:
                color = .green
                size = 12
            case .sota:
                color = .orange
                size = 12
            case .wwff:
                color = .mint
                size = 12
            case .pskr:
                color = .purple
                size = 10
            case .dxSummit,
                 .dxHeat,
                 .dxWatch,
                 .cluster:
                color = spot.source.color
                size = 10
            }

            return SpotMapAnnotation(
                id: spot.id,
                title: spot.spotter ?? spot.callsign,
                coordinate: CLLocationCoordinate2D(latitude: coord.latitude, longitude: coord.longitude),
                color: color,
                size: size
            )
        }
    }

    private func snrColor(_ snr: Int) -> Color {
        switch timelineSnrColorBand(snr: Int64(snr)) {
        case 3: .green
        case 2: .blue
        case 1: .orange
        default: .red
        }
    }
}

// MARK: - SpotMapAnnotation

struct SpotMapAnnotation: Identifiable {
    let id: String
    let title: String
    let coordinate: CLLocationCoordinate2D
    let color: Color
    let size: CGFloat
}
