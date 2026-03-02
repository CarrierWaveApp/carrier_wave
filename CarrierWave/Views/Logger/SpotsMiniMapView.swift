// Spots Mini Map View
//
// Displays spotter locations on a map with arcs to the target station.
// Used in RBNPanelView to visualize RBN and POTA spot coverage.

import CarrierWaveCore
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
                    ZStack {
                        Circle()
                            .fill(.red)
                            .frame(width: 16, height: 16)
                        Circle()
                            .stroke(.white, lineWidth: 2)
                            .frame(width: 16, height: 16)
                    }
                }

                // Geodesic arcs from target to each spotter
                ForEach(spotAnnotations) { annotation in
                    MapPolyline(coordinates: ActivationMapHelpers.geodesicPath(
                        from: targetCoord, to: annotation.coordinate, segments: 20
                    ))
                    .stroke(annotation.color.opacity(0.6), lineWidth: 1.5)
                }
            }

            // Spotter markers with SNR-based sizing
            ForEach(spotAnnotations) { annotation in
                Annotation(annotation.title, coordinate: annotation.coordinate) {
                    Circle()
                        .fill(annotation.color)
                        .frame(width: annotation.size, height: annotation.size)
                        .overlay(
                            Circle()
                                .stroke(.white, lineWidth: 1)
                        )
                }
            }
        }
        .mapStyle(.standard)
    }

    // MARK: Private

    private var targetCoordinate: CLLocationCoordinate2D? {
        guard let grid = targetGrid,
              let (lat, lon) = gridToCoordinates(grid)
        else {
            return nil
        }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    private var spotAnnotations: [SpotMapAnnotation] {
        spots.compactMap { spot in
            guard let grid = spot.spotterGrid,
                  let (lat, lon) = gridToCoordinates(grid)
            else {
                return nil
            }

            let color: Color
            let size: CGFloat

            switch spot.source {
            case .rbn:
                if let snr = spot.snr {
                    color = snrColor(snr)
                    // Size based on SNR: 8-20 points
                    size = CGFloat(min(max(8, 8 + snr / 3), 20))
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
            }

            return SpotMapAnnotation(
                id: spot.id,
                title: spot.spotter ?? spot.callsign,
                coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                color: color,
                size: size
            )
        }
    }

    private func snrColor(_ snr: Int) -> Color {
        switch snr {
        case 25...: .green
        case 15...: .blue
        case 5...: .orange
        default: .red
        }
    }

    /// Convert a Maidenhead grid square to approximate coordinates
    private func gridToCoordinates(_ grid: String) -> (Double, Double)? {
        let upper = grid.uppercased()
        guard upper.count >= 4 else {
            return nil
        }

        let chars = Array(upper)

        guard let lon1 = chars[0].asciiValue, let lat1 = chars[1].asciiValue,
              lon1 >= 65, lon1 <= 82, lat1 >= 65, lat1 <= 82
        else {
            return nil
        }

        guard let lon2 = chars[2].wholeNumberValue, let lat2 = chars[3].wholeNumberValue else {
            return nil
        }

        var longitude = Double(lon1 - 65) * 20 - 180
        longitude += Double(lon2) * 2 + 1

        var latitude = Double(lat1 - 65) * 10 - 90
        latitude += Double(lat2) + 0.5

        if upper.count >= 6 {
            if let lon3 = chars[4].asciiValue, let lat3 = chars[5].asciiValue,
               lon3 >= 65, lon3 <= 88, lat3 >= 65, lat3 <= 88
            {
                longitude += Double(lon3 - 65) * (2.0 / 24.0) + (1.0 / 24.0)
                latitude += Double(lat3 - 65) * (1.0 / 24.0) + (0.5 / 24.0)
            }
        }

        return (latitude, longitude)
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
