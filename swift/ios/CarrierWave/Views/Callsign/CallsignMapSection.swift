import CarrierWaveCore
import CarrierWaveData
import CoreLocation
import MapKit
import SwiftUI

// MARK: - CallsignMapSection

/// Compact map showing the other station's grid square location with distance/bearing.
struct CallsignMapSection: View {
    // MARK: Internal

    let grid: String
    let callsign: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let ffiCenter = maidenheadCoordinate(grid: grid) {
                let center = CLLocationCoordinate2D(
                    latitude: ffiCenter.latitude, longitude: ffiCenter.longitude
                )
                mapView(center: center)
                distanceBearingLabel
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Private

    @AppStorage("myGrid") private var myGrid = ""
    @AppStorage("shareMapStyle") private var shareMapStyleRaw = "adaptive"

    @ScaledMetric(relativeTo: .caption) private var mapHeight: CGFloat = 150

    @ViewBuilder
    private var distanceBearingLabel: some View {
        if !myGrid.isEmpty,
           let distanceKm = maidenheadDistanceKm(grid1: myGrid, grid2: grid),
           let bearing = maidenheadBearing(grid1: myGrid, grid2: grid)
        {
            let distanceMi = distanceKm * 0.621371
            let cardinal = cardinalDirection(bearing)
            HStack(spacing: 4) {
                Image(systemName: "location.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text("~\(Int(distanceMi)) mi · \(Int(bearing))° \(cardinal) from \(myGrid)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func mapView(center: CLLocationCoordinate2D) -> some View {
        let style = ShareMapStyle(rawValue: shareMapStyleRaw) ?? .adaptive
        if style.usesCustomRenderer {
            let myCoord = maidenheadCoordinate(grid: myGrid).map {
                CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
            }
            ThemedMapImage(
                coordinates: [center], myCoordinate: myCoord,
                style: style
            )
            .frame(height: mapHeight)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .allowsHitTesting(false)
        } else {
            let region = MKCoordinateRegion(
                center: center,
                span: MKCoordinateSpan(latitudeDelta: 2, longitudeDelta: 2)
            )
            Map(initialPosition: .region(region)) {
                Annotation(callsign, coordinate: center) {
                    Image(systemName: "mappin.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.red)
                }
            }
            .standardMapStyle()
            .frame(height: mapHeight)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .allowsHitTesting(false)
        }
    }

    private func cardinalDirection(_ degrees: Double) -> String {
        let directions = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let index = Int((degrees + 22.5) / 45.0) % 8
        return directions[index]
    }
}
