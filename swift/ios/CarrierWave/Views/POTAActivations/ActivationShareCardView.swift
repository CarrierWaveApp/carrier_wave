// Activation Share Card View
//
// A branded card view for sharing POTA activation summaries with a map.

import CarrierWaveData
import CoreLocation
import MapKit
import SwiftUI

// MARK: - ActivationShareCardView

/// A shareable card showing activation map, stats, and branding (for live preview)
struct ActivationShareCardView: View {
    // MARK: Internal

    let source: BragSheetSource
    let myGrid: String?
    var metadata: ActivationMetadata?
    var equipment: [ShareCardEquipmentItem] = []
    var statisticianStats: ActivationStatistics?

    /// Bound camera for globe maps — nudged after load to force annotation render
    @State var mapCamera: MapCameraPosition = .automatic

    var body: some View {
        VStack(spacing: 0) {
            header
            mapSection
            referenceInfoSection
            statsSection
            if let advancedStats = statisticianStats {
                ShareCardStatisticianSection(stats: advancedStats)
                    .padding(.top, 6)
            }
            if !clubMembers.isEmpty {
                ActivationShareCardClubMembers(members: clubMembers)
            }
            ShareCardTimelineView(qsos: source.qsos)
                .padding(.top, 8)
                .padding(.horizontal, 16)
            footer
        }
        .frame(width: 400, height: cardHeight)
        .background(BragSheetTheme.cardBackground)
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

    @AppStorage("shareMapStyle") private var shareMapStyleRaw = "adaptive"

    private var cardHeight: CGFloat {
        var height: CGFloat = statisticianStats != nil ? 880 : 640
        if !clubMembers.isEmpty {
            height += 30
        }
        return height
    }

    private var clubMembers: [(callsign: String, clubs: [String])] {
        Self.buildClubMembers(from: source.qsos)
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
        source.mappableQSOs.compactMap { qso in
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
        ActivationStatsHelper.statistics(forQSOs: source.qsos)
    }

    private var activationRadio: String? {
        source.qsos.compactMap(\.myRig).first
    }

    /// Metadata watts, falling back to most common QSO-level power
    private var activationWatts: Int? {
        metadata?.watts ?? source.qsos.compactMap(\.power).first
    }

    private var isWideSpan: Bool {
        ActivationMapHelpers.requiresGlobeView(
            qsoCoordinates: mappableQSOs.map(\.coordinate),
            myCoordinate: myCoordinate
        )
    }

    private var useGlobeStyle: Bool {
        let style = ShareMapStyle(rawValue: shareMapStyleRaw) ?? .adaptive
        return style.shouldUseGlobe(isWideSpan: isWideSpan)
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
        Map(position: $mapCamera) {
            ForEach(mappableQSOs, id: \.qso.id) { item in
                Annotation(
                    "",
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

            if let myCoord = myCoordinate {
                ForEach(mappableQSOs, id: \.qso.id) { item in
                    MapContentBuilders.geodesicArc(
                        from: myCoord, to: item.coordinate
                    )
                }
            }
        }
        .mapStyle(useGlobeStyle
            ? .imagery(elevation: .realistic)
            : .standard(elevation: .realistic))
        .allowsHitTesting(false)
        .task {
            mapCamera = mapCameraPosition
            if useGlobeStyle {
                try? await Task.sleep(for: .seconds(0.5))
                nudgeShareCamera()
            }
        }
    }

    // MARK: - Reference Info Section

    private var referenceInfoSection: some View {
        ActivationShareCardReferenceInfo(
            referenceCode: source.referenceCode,
            referenceName: source.referenceName,
            referenceIcon: source.referenceIcon,
            displayDate: source.displayDate,
            title: metadata?.title ?? source.title
        )
    }

    private var statsSection: some View {
        let stats = activationStats
        return ActivationShareCardStats(
            qsoCount: source.qsoCount,
            duration: source.formattedDuration,
            bandsCount: source.uniqueBands.count,
            modes: source.uniqueModes.sorted(),
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
        ActivationShareCardFooter(callsign: source.callsign)
    }

    private func nudgeShareCamera() {
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

// MARK: - ActivationShareCardForExport

/// A version of the share card that uses a pre-rendered map image (for export)
struct ActivationShareCardForExport: View {
    // MARK: Internal

    let source: BragSheetSource
    let mapImage: UIImage?
    var metadata: ActivationMetadata?
    var equipment: [ShareCardEquipmentItem] = []
    var statisticianStats: ActivationStatistics?
    /// Contacts the renderer could not place (shown in the empty-map state).
    var withoutLocationCount = 0

    var body: some View {
        VStack(spacing: 0) {
            ActivationShareCardHeader()
            mapSection
            ActivationShareCardReferenceInfo(
                referenceCode: source.referenceCode,
                referenceName: source.referenceName,
                referenceIcon: source.referenceIcon,
                displayDate: source.displayDate,
                title: metadata?.title ?? source.title
            )
            exportStatsSection
            if let advancedStats = statisticianStats {
                ShareCardStatisticianSection(stats: advancedStats)
                    .padding(.top, 6)
            }
            if !exportClubMembers.isEmpty {
                ActivationShareCardClubMembers(members: exportClubMembers)
            }
            ShareCardTimelineView(qsos: source.qsos)
                .padding(.top, 8)
                .padding(.horizontal, 16)
            ActivationShareCardFooter(callsign: source.callsign)
        }
        .frame(width: 400, height: exportCardHeight)
        .background(BragSheetTheme.cardBackground)
        .clipShape(Rectangle())
        .overlay(
            Rectangle()
                .stroke(Color.black.opacity(0.4), lineWidth: 2)
        )
    }

    // MARK: Private

    private var exportClubMembers: [(callsign: String, clubs: [String])] {
        ActivationShareCardView.buildClubMembers(from: source.qsos)
    }

    private var exportCardHeight: CGFloat {
        var height: CGFloat = statisticianStats != nil ? 880 : 640
        if !exportClubMembers.isEmpty {
            height += 30
        }
        return height
    }

    private var exportStatsSection: some View {
        let stats = ActivationStatsHelper.statistics(forQSOs: source.qsos)
        let radio = source.qsos.compactMap(\.myRig).first
        let watts = metadata?.watts ?? source.qsos.compactMap(\.power).first
        return ActivationShareCardStats(
            qsoCount: source.qsoCount,
            duration: source.formattedDuration,
            bandsCount: source.uniqueBands.count,
            modes: source.uniqueModes.sorted(),
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
                ActivationShareCardEmptyMap(withoutLocationCount: withoutLocationCount)
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
        source: .pota(
            activation: activation,
            parkName: "Gifford Pinchot National Forest"
        ),
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
        source: .pota(
            activation: activation,
            parkName: "Gifford Pinchot National Forest"
        ),
        myGrid: nil
    )
    .padding()
    .background(Color(.systemBackground))
}
