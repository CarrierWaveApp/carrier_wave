// Activation Share Card View
//
// A branded card view for sharing POTA activation summaries with a map.

import CarrierWaveData
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
            if !clubMembers.isEmpty {
                ActivationShareCardClubMembers(members: clubMembers)
            }
            ShareCardTimelineView(qsos: activation.qsos)
                .padding(.top, 8)
                .padding(.horizontal, 16)
            footer
        }
        .frame(width: 400, height: cardHeight)
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

    static func buildClubMembers(
        from qsos: [QSO]
    ) -> [(callsign: String, clubs: [String])] {
        var seen = Set<String>()
        var results: [(callsign: String, clubs: [String])] = []
        for qso in qsos {
            let key = qso.callsign.uppercased()
            guard seen.insert(key).inserted else {
                continue
            }
            let clubs = ClubsSyncService.shared.clubs(for: qso.callsign)
            guard !clubs.isEmpty else {
                continue
            }
            results.append((callsign: qso.callsign, clubs: clubs))
        }
        return results
    }

    // MARK: Private

    private var cardHeight: CGFloat {
        var height: CGFloat = statisticianStats != nil ? 880 : 640
        if !clubMembers.isEmpty {
            height += 30
        }
        return height
    }

    private var clubMembers: [(callsign: String, clubs: [String])] {
        Self.buildClubMembers(from: activation.qsos)
    }

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
        ActivationMapHelpers.mapCameraPosition(
            qsoCoordinates: mappableQSOs.map(\.coordinate),
            myCoordinate: myCoordinate
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

    private var isWideSpan: Bool {
        ActivationMapHelpers.requiresGlobeView(
            qsoCoordinates: mappableQSOs.map(\.coordinate),
            myCoordinate: myCoordinate
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
                    MapPinMarker(
                        color: RSTColorHelper.color(
                            rstSent: item.qso.rstSent,
                            rstReceived: item.qso.rstReceived
                        )
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
                    .stroke(.white.opacity(0.5), lineWidth: 2.5)
                }
            }
        }
        .mapStyle(isWideSpan
            ? .imagery(elevation: .realistic)
            : .standard(elevation: .realistic))
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
            if !exportClubMembers.isEmpty {
                ActivationShareCardClubMembers(members: exportClubMembers)
            }
            ShareCardTimelineView(qsos: activation.qsos)
                .padding(.top, 8)
                .padding(.horizontal, 16)
            ActivationShareCardFooter(callsign: activation.callsign)
        }
        .frame(width: 400, height: exportCardHeight)
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

    private var exportClubMembers: [(callsign: String, clubs: [String])] {
        ActivationShareCardView.buildClubMembers(from: activation.qsos)
    }

    private var exportCardHeight: CGFloat {
        var height: CGFloat = statisticianStats != nil ? 880 : 640
        if !exportClubMembers.isEmpty {
            height += 30
        }
        return height
    }

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
