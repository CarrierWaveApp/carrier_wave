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
    var equipment: [ShareCardEquipmentItem] = []
    var statisticianStats: ActivationStatistics?

    var body: some View {
        VStack(spacing: 0) {
            header
            mapSection
            parkInfoSection
            statsSection
            if let advancedStats = statisticianStats {
                ShareCardStatisticianSection(stats: advancedStats)
                    .padding(.top, 6)
            }
            ShareCardTimelineView(qsos: activation.qsos)
                .padding(.top, 8)
                .padding(.horizontal, 16)
            footer
        }
        .frame(width: 400, height: statisticianStats != nil ? 880 : 640)
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
        .clipShape(Rectangle())
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

    // MARK: - Stats Section

    private var activationStats: MapStatistics {
        ActivationStatsHelper.statistics(for: activation)
    }

    private var activationRadio: String? {
        activation.qsos.compactMap(\.myRig).first
    }

    /// Metadata watts, falling back to most common QSO-level power
    private var activationWatts: Int? {
        metadata?.watts ?? activation.qsos.compactMap(\.power).first
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
                    Circle()
                        .fill(
                            RSTColorHelper.color(
                                rstSent: item.qso.rstSent,
                                rstReceived: item.qso.rstReceived
                            )
                        )
                        .frame(width: 12, height: 12)
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

    private var statsSection: some View {
        let stats = activationStats
        return ActivationShareCardStats(
            qsoCount: activation.qsoCount,
            duration: activation.formattedDuration,
            bandsCount: activation.uniqueBands.count,
            modes: activation.uniqueModes.sorted(),
            qsoRate: stats.qsoRate,
            watts: activationWatts,
            avgDistanceKm: stats.averageDistanceKm,
            medianDistanceKm: statisticianStats?.distance?.median,
            maxDistanceKm: stats.longestDistanceKm,
            wattsPerMile: stats.wattsPerMile,
            radio: activationRadio,
            equipment: equipment
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
    var equipment: [ShareCardEquipmentItem] = []
    var statisticianStats: ActivationStatistics?

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
            exportStatsSection
            if let advancedStats = statisticianStats {
                ShareCardStatisticianSection(stats: advancedStats)
                    .padding(.top, 6)
            }
            ShareCardTimelineView(qsos: activation.qsos)
                .padding(.top, 8)
                .padding(.horizontal, 16)
            ActivationShareCardFooter(callsign: activation.callsign)
        }
        .frame(width: 400, height: statisticianStats != nil ? 880 : 640)
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
        .clipShape(Rectangle())
        .overlay(
            Rectangle()
                .stroke(Color(red: 0.12, green: 0.10, blue: 0.18), lineWidth: 2)
        )
    }

    // MARK: Private

    private var exportStatsSection: some View {
        let stats = ActivationStatsHelper.statistics(for: activation)
        let radio = activation.qsos.compactMap(\.myRig).first
        let watts = metadata?.watts ?? activation.qsos.compactMap(\.power).first
        return ActivationShareCardStats(
            qsoCount: activation.qsoCount,
            duration: activation.formattedDuration,
            bandsCount: activation.uniqueBands.count,
            modes: activation.uniqueModes.sorted(),
            qsoRate: stats.qsoRate,
            watts: watts,
            avgDistanceKm: stats.averageDistanceKm,
            medianDistanceKm: statisticianStats?.distance?.median,
            maxDistanceKm: stats.longestDistanceKm,
            wattsPerMile: stats.wattsPerMile,
            radio: radio,
            equipment: equipment
        )
    }

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
