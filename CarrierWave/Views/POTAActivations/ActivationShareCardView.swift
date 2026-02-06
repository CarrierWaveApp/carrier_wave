// Activation Share Card View
//
// A branded card view for sharing POTA activation summaries with a map.

import MapKit
import SwiftUI

// MARK: - ActivationShareCardView

/// A shareable card showing activation map, stats, and branding (for live preview)
struct ActivationShareCardView: View {
    // MARK: Internal

    let activation: POTAActivation
    let parkName: String?
    let myGrid: String?
    var metadata: ActivationMetadata?

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
                colors: [
                    Color(red: 0.12, green: 0.10, blue: 0.18),
                    Color(red: 0.18, green: 0.12, blue: 0.25),
                    Color(red: 0.12, green: 0.10, blue: 0.18),
                ],
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
        ActivationShareCardHeader()
    }

    // MARK: - Map Section

    private var mapSection: some View {
        Group {
            if mappableQSOs.isEmpty {
                ActivationShareCardEmptyMap()
            } else {
                activationMap
            }
        }
        .frame(height: 200)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
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
                    MapPolyline(
                        coordinates: ActivationMapHelpers.geodesicPath(
                            from: myCoord, to: item.coordinate
                        )
                    )
                    .stroke(.blue.opacity(0.6), lineWidth: 1.5)
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic))
        .allowsHitTesting(false)
    }

    // MARK: - Park Info Section

    private var parkInfoSection: some View {
        ActivationShareCardParkInfo(
            parkReference: activation.parkReference,
            parkName: parkName,
            displayDate: activation.displayDate,
            title: metadata?.title
        )
    }

    // MARK: - Stats Section

    private var statsSection: some View {
        ActivationShareCardStats(
            qsoCount: activation.qsoCount,
            duration: activation.formattedDuration,
            bandsCount: activation.uniqueBands.count,
            modesCount: activation.uniqueModes.count,
            watts: metadata?.watts
        )
    }

    // MARK: - Footer

    private var footer: some View {
        ActivationShareCardFooter(callsign: activation.callsign)
    }
}

// MARK: - ActivationShareCardForExport

/// A version of the share card that uses a pre-rendered map image (for export)
struct ActivationShareCardForExport: View {
    // MARK: Internal

    let activation: POTAActivation
    let parkName: String?
    let mapImage: UIImage?
    var metadata: ActivationMetadata?

    var body: some View {
        VStack(spacing: 0) {
            ActivationShareCardHeader()
            mapSection
            ActivationShareCardParkInfo(
                parkReference: activation.parkReference,
                parkName: parkName,
                displayDate: activation.displayDate,
                title: metadata?.title
            )
            ActivationShareCardStats(
                qsoCount: activation.qsoCount,
                duration: activation.formattedDuration,
                bandsCount: activation.uniqueBands.count,
                modesCount: activation.uniqueModes.count,
                watts: metadata?.watts
            )
            ActivationShareCardFooter(callsign: activation.callsign)
        }
        .frame(width: 400, height: 600)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.12, green: 0.10, blue: 0.18),
                    Color(red: 0.18, green: 0.12, blue: 0.25),
                    Color(red: 0.12, green: 0.10, blue: 0.18),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(Color(red: 0.12, green: 0.10, blue: 0.18), lineWidth: 2)
        )
    }

    // MARK: Private

    private let cornerRadius: CGFloat = 24

    private var mapSection: some View {
        Group {
            if let mapImage {
                Image(uiImage: mapImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ActivationShareCardEmptyMap()
            }
        }
        .frame(height: 200)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
    }
}

// MARK: - ActivationShareCardHeader

private struct ActivationShareCardHeader: View {
    var body: some View {
        HStack {
            Image(systemName: "tree.fill")
                .font(.title2)
            Text("CARRIER WAVE")
                .font(.headline)
                .fontWeight(.bold)
        }
        .foregroundStyle(.white)
        .padding(.top, 24)
        .padding(.bottom, 12)
    }
}

// MARK: - ActivationShareCardEmptyMap

struct ActivationShareCardEmptyMap: View {
    var body: some View {
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
}

// MARK: - ActivationShareCardParkInfo

private struct ActivationShareCardParkInfo: View {
    let parkReference: String
    let parkName: String?
    let displayDate: String
    var title: String?

    var body: some View {
        VStack(spacing: 4) {
            Text(parkReference)
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

            if let title, !title.isEmpty {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.9))
                    .italic()
            }

            Text(displayDate)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.8))
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 24)
    }
}

// MARK: - ActivationShareCardStats

private struct ActivationShareCardStats: View {
    let qsoCount: Int
    let duration: String
    let bandsCount: Int
    let modesCount: Int
    var watts: Int?

    var body: some View {
        HStack(spacing: 24) {
            StatItem(value: "\(qsoCount)", label: "QSOs")
            StatItem(value: duration, label: "Duration")
            StatItem(value: "\(bandsCount)", label: "Bands")
            StatItem(value: "\(modesCount)", label: "Modes")
            if let watts {
                StatItem(value: "\(watts)W", label: "Power")
            }
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 16)
        .background(Color.purple.opacity(0.2))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
    }
}

// MARK: - ActivationShareCardFooter

private struct ActivationShareCardFooter: View {
    let callsign: String

    var body: some View {
        Text(callsign)
            .font(.headline)
            .fontWeight(.semibold)
            .foregroundStyle(.white)
            .padding(.top, 16)
            .padding(.bottom, 24)
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
