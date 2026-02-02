// Activation Share Card View
//
// A branded card view for sharing POTA activation summaries with a map.

import MapKit
import SwiftUI

// MARK: - ActivationShareCardView

/// A shareable card showing activation map, stats, and branding
struct ActivationShareCardView: View {
    // MARK: Internal

    let activation: POTAActivation
    let parkName: String?
    let myGrid: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            mapSection
            parkInfoSection
            statsSection
            footer
        }
        .frame(width: 400, height: 600)
        .background(
            LinearGradient(
                colors: [Color.accentColor, Color.accentColor.opacity(0.7)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }

    // MARK: Private

    /// My coordinate from grid
    private var myCoordinate: CLLocationCoordinate2D? {
        guard let grid = myGrid, grid.count >= 4 else {
            return nil
        }
        return MaidenheadConverter.coordinate(from: grid)
    }

    /// QSOs with valid coordinates
    private var mappableQSOs: [(qso: QSO, coordinate: CLLocationCoordinate2D)] {
        activation.mappableQSOs.compactMap { qso in
            guard let grid = qso.theirGrid,
                  let coordinate = MaidenheadConverter.coordinate(from: grid)
            else {
                return nil
            }
            return (qso, coordinate)
        }
    }

    private var mapCameraPosition: MapCameraPosition {
        var allCoordinates = mappableQSOs.map(\.coordinate)
        if let myCoord = myCoordinate {
            allCoordinates.append(myCoord)
        }

        guard !allCoordinates.isEmpty else {
            return .automatic
        }

        // Calculate bounding region
        let lats = allCoordinates.map(\.latitude)
        let lons = allCoordinates.map(\.longitude)

        guard let minLat = lats.min(),
              let maxLat = lats.max(),
              let minLon = lons.min(),
              let maxLon = lons.max()
        else {
            return .automatic
        }

        let centerLat = (minLat + maxLat) / 2
        let centerLon = (minLon + maxLon) / 2
        let latSpan = max(maxLat - minLat, 5) * 1.3 // Add 30% padding
        let lonSpan = max(maxLon - minLon, 5) * 1.3

        return .region(
            MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon),
                span: MKCoordinateSpan(latitudeDelta: latSpan, longitudeDelta: lonSpan)
            )
        )
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Image(systemName: "tree.fill")
                .font(.title2)
            Text("CARRIER WAVE")
                .font(.headline)
                .fontWeight(.bold)
        }
        .foregroundStyle(.white)
        .padding(.top, 20)
        .padding(.bottom, 12)
    }

    // MARK: - Map Section

    private var mapSection: some View {
        Group {
            if mappableQSOs.isEmpty {
                emptyMapPlaceholder
            } else {
                activationMap
            }
        }
        .frame(height: 200)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
    }

    private var emptyMapPlaceholder: some View {
        ZStack {
            Color.white.opacity(0.2)
            VStack(spacing: 8) {
                Image(systemName: "map")
                    .font(.title)
                Text("No grid data available")
                    .font(.caption)
            }
            .foregroundStyle(.white.opacity(0.7))
        }
    }

    private var activationMap: some View {
        Map(initialPosition: mapCameraPosition) {
            // Show markers for each QSO with a grid
            ForEach(mappableQSOs, id: \.qso.id) { item in
                Annotation(
                    item.qso.callsign,
                    coordinate: item.coordinate,
                    anchor: .bottom
                ) {
                    Image(systemName: "antenna.radiowaves.left.and.right.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.green)
                        .background(
                            Circle()
                                .fill(.white)
                                .frame(width: 20, height: 20)
                        )
                }
            }

            // Draw geodesic paths from my location to each QSO
            if let myCoord = myCoordinate {
                ForEach(mappableQSOs, id: \.qso.id) { item in
                    MapPolyline(coordinates: geodesicPath(from: myCoord, to: item.coordinate))
                        .stroke(.blue.opacity(0.6), lineWidth: 1.5)
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic))
        .allowsHitTesting(false)
    }

    // MARK: - Park Info Section

    private var parkInfoSection: some View {
        VStack(spacing: 4) {
            Text(activation.parkReference)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(.white)

            if let name = parkName {
                Text(name)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }

            Text(activation.displayDate)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.8))
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 24)
    }

    // MARK: - Stats Section

    private var statsSection: some View {
        HStack(spacing: 24) {
            StatItem(value: "\(activation.qsoCount)", label: "QSOs")
            StatItem(value: activation.formattedDuration, label: "Duration")
            StatItem(value: "\(activation.uniqueBands.count)", label: "Bands")
            StatItem(value: "\(activation.uniqueModes.count)", label: "Modes")
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 16)
        .background(.white.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
    }

    // MARK: - Footer

    private var footer: some View {
        Text(activation.callsign)
            .font(.headline)
            .fontWeight(.semibold)
            .foregroundStyle(.white)
            .padding(.top, 16)
            .padding(.bottom, 20)
    }

    /// Generate a geodesic (great circle) path between two coordinates
    private func geodesicPath(
        from start: CLLocationCoordinate2D,
        to end: CLLocationCoordinate2D,
        segments: Int = 50
    ) -> [CLLocationCoordinate2D] {
        var path: [CLLocationCoordinate2D] = []

        let lat1 = start.latitude * .pi / 180
        let lon1 = start.longitude * .pi / 180
        let lat2 = end.latitude * .pi / 180
        let lon2 = end.longitude * .pi / 180

        let angularDistance =
            2
                * asin(
                    sqrt(
                        pow(sin((lat2 - lat1) / 2), 2) + cos(lat1) * cos(lat2)
                            * pow(sin((lon2 - lon1) / 2), 2)
                    )
                )

        guard angularDistance > 0 else {
            return [start, end]
        }

        for i in 0 ... segments {
            let fraction = Double(i) / Double(segments)
            let coeffA = sin((1 - fraction) * angularDistance) / sin(angularDistance)
            let coeffB = sin(fraction * angularDistance) / sin(angularDistance)

            let x = coeffA * cos(lat1) * cos(lon1) + coeffB * cos(lat2) * cos(lon2)
            let y = coeffA * cos(lat1) * sin(lon1) + coeffB * cos(lat2) * sin(lon2)
            let z = coeffA * sin(lat1) + coeffB * sin(lat2)

            let lat = atan2(z, sqrt(x * x + y * y)) * 180 / .pi
            let lon = atan2(y, x) * 180 / .pi

            path.append(CLLocationCoordinate2D(latitude: lat, longitude: lon))
        }

        return path
    }
}

// MARK: - StatItem

private struct StatItem: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundStyle(.white)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.8))
        }
    }
}

// MARK: - Preview

#Preview("With QSOs") {
    // Create mock QSOs with grids
    let qsos = [
        QSO(
            callsign: "K4SWL",
            band: "20m",
            mode: "CW",
            timestamp: Date().addingTimeInterval(-7_200),
            myCallsign: "W1ABC",
            myGrid: "FN31",
            theirGrid: "EM66",
            parkReference: "US-0189",
            importSource: .logger
        ),
        QSO(
            callsign: "N3ABC",
            band: "40m",
            mode: "SSB",
            timestamp: Date().addingTimeInterval(-3_600),
            myCallsign: "W1ABC",
            myGrid: "FN31",
            theirGrid: "FM19",
            parkReference: "US-0189",
            importSource: .logger
        ),
        QSO(
            callsign: "WA7DEF",
            band: "20m",
            mode: "CW",
            timestamp: Date(),
            myCallsign: "W1ABC",
            myGrid: "FN31",
            theirGrid: "CN87",
            parkReference: "US-0189",
            importSource: .logger
        ),
    ]

    let activation = POTAActivation(
        parkReference: "US-0189",
        utcDate: Date(),
        callsign: "W1ABC",
        qsos: qsos
    )

    ActivationShareCardView(
        activation: activation,
        parkName: "Gifford Pinchot National Forest",
        myGrid: "FN31"
    )
    .padding()
    .background(Color(.systemBackground))
}

#Preview("No Grid Data") {
    let qsos = [
        QSO(
            callsign: "K4SWL",
            band: "20m",
            mode: "CW",
            timestamp: Date(),
            myCallsign: "W1ABC",
            parkReference: "US-0189",
            importSource: .logger
        ),
    ]

    let activation = POTAActivation(
        parkReference: "US-0189",
        utcDate: Date(),
        callsign: "W1ABC",
        qsos: qsos
    )

    ActivationShareCardView(
        activation: activation,
        parkName: "Gifford Pinchot National Forest",
        myGrid: nil
    )
    .padding()
    .background(Color(.systemBackground))
}
