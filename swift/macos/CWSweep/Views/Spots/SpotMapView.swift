import CarrierWaveCore
import CoreLocation
import MapKit
import SwiftUI

// MARK: - SpotMapView

/// Mini map centered on the spot's location with a bearing compass overlay.
/// Full-width landscape (3:2), no geodesic — shows where they are, not the path.
struct SpotMapView: View {
    // MARK: Internal

    let spotGrid: String?
    let spotCoordinate: CLLocationCoordinate2D?
    let band: String
    let callsign: String

    var body: some View {
        if let their = theirCoord {
            ZStack(alignment: .bottomTrailing) {
                mapContent(their: their)
                    .frame(height: 140)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                bearingOverlay
                    .padding(6)
            }
            .onAppear {
                mapPosition = cameraFor(their)
            }
            .onChange(of: spotGrid) {
                mapPosition = cameraFor(their)
            }
            .onChange(of: spotCoordinate?.latitude) {
                if let coord = theirCoord {
                    mapPosition = cameraFor(coord)
                }
            }
        }
    }

    // MARK: Private

    private static let bandColors: [String: Color] = [
        "160m": .purple, "80m": .indigo,
        "60m": Color(red: 0.3, green: 0.3, blue: 0.7),
        "40m": .blue, "30m": .teal, "20m": .green, "17m": .mint,
        "15m": .yellow, "12m": .orange, "10m": .red, "6m": .pink,
        "2m": Color(red: 0.8, green: 0.4, blue: 0.8),
    ]

    @AppStorage("myGrid") private var myGrid = ""
    @State private var mapPosition: MapCameraPosition = .automatic

    private var pinColor: Color {
        Self.bandColors[band] ?? .gray
    }

    // MARK: - Coordinates

    private var theirCoord: CLLocationCoordinate2D? {
        if let grid = spotGrid,
           MaidenheadConverter.isValid(grid),
           let coord = MaidenheadConverter.coordinate(from: grid)
        {
            return CLLocationCoordinate2D(
                latitude: coord.latitude, longitude: coord.longitude
            )
        }
        return spotCoordinate
    }

    private var distanceAndBearing: (miles: Double, degrees: Double)? {
        guard !myGrid.isEmpty else {
            return nil
        }
        // Use grid-to-grid if available, otherwise grid-to-coord
        if let grid = spotGrid,
           let miles = MaidenheadConverter.distanceMiles(
               from: myGrid, to: grid
           ),
           let bearing = MaidenheadConverter.bearing(
               from: myGrid, to: grid
           )
        {
            return (miles, bearing)
        }
        // Fallback: compute from coordinates
        guard let their = spotCoordinate,
              let myCoord = MaidenheadConverter.coordinate(from: myGrid)
        else {
            return nil
        }
        let myLoc = CLLocation(latitude: myCoord.latitude, longitude: myCoord.longitude)
        let theirLoc = CLLocation(latitude: their.latitude, longitude: their.longitude)
        let meters = myLoc.distance(from: theirLoc)
        let bearing = Self.bearing(
            from: (latitude: myCoord.latitude, longitude: myCoord.longitude),
            to: their
        )
        return (meters / 1_609.344, bearing)
    }

    private var spotPin: some View {
        VStack(spacing: 0) {
            Circle()
                .fill(pinColor.opacity(0.9))
                .frame(width: 10, height: 10)
                .overlay(
                    Circle()
                        .strokeBorder(.white, lineWidth: 1.5)
                )
            Rectangle()
                .fill(pinColor.opacity(0.7))
                .frame(width: 2, height: 7)
        }
    }

    // MARK: - Bearing Overlay

    @ViewBuilder
    private var bearingOverlay: some View {
        if let info = distanceAndBearing {
            HStack(spacing: 6) {
                bearingArrow(degrees: info.degrees)
                    .frame(width: 18, height: 18)

                VStack(alignment: .leading, spacing: 0) {
                    Text(UnitFormatter.distanceFromMeters(info.miles * 1_609.344))
                        .font(.caption2.bold().monospacedDigit())
                        .foregroundStyle(.white)
                    Text("\(Int(info.degrees))\u{00B0}")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
        }
    }

    // MARK: - Map Content

    private func mapContent(
        their: CLLocationCoordinate2D
    ) -> some View {
        Map(position: $mapPosition, interactionModes: [.pan, .zoom]) {
            Annotation(callsign, coordinate: their, anchor: .bottom) {
                spotPin
            }
            .annotationTitles(.hidden)
        }
        .mapStyle(.standard(elevation: .realistic))
    }

    private func bearingArrow(degrees: Double) -> some View {
        Image(systemName: "location.north.fill")
            .font(.caption)
            .foregroundStyle(pinColor)
            .rotationEffect(.degrees(degrees))
    }

    // MARK: - Bearing Math

    private static func bearing(
        from: (latitude: Double, longitude: Double),
        to coord: CLLocationCoordinate2D
    ) -> Double {
        let lat1 = from.latitude * .pi / 180
        let lon1 = from.longitude * .pi / 180
        let lat2 = coord.latitude * .pi / 180
        let lon2 = coord.longitude * .pi / 180
        let dLon = lon2 - lon1
        let yy = sin(dLon) * cos(lat2)
        let xx = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let radians = atan2(yy, xx)
        return (radians * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }

    // MARK: - Camera

    private func cameraFor(
        _ coord: CLLocationCoordinate2D
    ) -> MapCameraPosition {
        .region(MKCoordinateRegion(
            center: coord,
            span: MKCoordinateSpan(latitudeDelta: 8, longitudeDelta: 8)
        ))
    }

    // MARK: - Formatting
}
