// TOTABragSheetView's view sub-blocks and derived helpers, lifted into an
// extension so the parent struct stays under SwiftLint's type body length
// cap. Each block is a small computed view; the parent's `body` composes
// them in order.

import CarrierWaveCore
import CarrierWaveData
import CoreLocation
import MapKit
import SwiftUI

extension TOTABragSheetView {
    // MARK: - Sections

    var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "square.grid.3x3.fill")
                .font(.subheadline)
                .foregroundStyle(.purple.opacity(0.9))
            Text("TILES ON THE AIR")
                .font(.caption.weight(.bold))
                .tracking(2)
                .foregroundStyle(.white.opacity(0.85))
            Spacer()
            Text(callsign)
                .font(.caption.monospaced().weight(.semibold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    var tileBlock: some View {
        VStack(spacing: 4) {
            Text(tilesText)
                .font(.system(size: 28, weight: .heavy, design: .rounded).monospaced())
                .foregroundStyle(.white)
            Text(dateText)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    var mapBlock: some View {
        if let image = pathMapImage {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(height: 140)
                .padding(.horizontal, 14)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        } else if trackCoords.count >= 2, let region {
            // Path map only renders when there's an actual track to draw —
            // otherwise the lone tile-boundary rectangle reads as a solid
            // colored block with no useful content.
            TOTAPathCanvas(
                trackCoords: trackCoords,
                tileBounds: session.tilesActivated.compactMap {
                    MaidenheadConverter.tileBounds(for: $0)
                }.map { ($0.sw, $0.ne) },
                fallbackRegion: region
            )
            .frame(height: 140)
            .padding(.horizontal, 14)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    var scoreBlock: some View {
        VStack(spacing: 2) {
            Text(String(format: "%.1f", displayScore))
                .font(.system(size: 44, weight: .heavy, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
            Text("\(confidenceLabel) POINTS")
                .font(.caption2.weight(.bold))
                .tracking(2)
                .foregroundStyle(.white.opacity(0.55))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    var chipsBlock: some View {
        let chips = bonusChips
        if !chips.isEmpty {
            FlowLayout(spacing: 6) {
                ForEach(chips, id: \.self) { chip in
                    Text(chip)
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.12))
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 8)
        }
    }

    var statsBlock: some View {
        VStack(spacing: 6) {
            HStack(spacing: 0) {
                statColumn(value: "\(qsos.count)", label: "QSOs")
                statColumn(value: distanceText, label: "Distance")
                statColumn(value: "\(uniqueBands.count)", label: uniqueBands.count == 1 ? "Band" : "Bands")
                statColumn(value: durationText, label: "Duration")
            }
            if dxccCount > 0 || farthestText != nil {
                Divider().background(.white.opacity(0.10))
                HStack(spacing: 0) {
                    statColumn(value: "\(dxccCount)", label: "DXCC")
                    statColumn(value: farthestText ?? "—", label: "Farthest")
                    statColumn(value: modesText, label: uniqueModes.count == 1 ? "Mode" : "Modes")
                    statColumn(value: ratePerHourText, label: "Q/hr")
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(BragSheetTheme.insetBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 14)
    }

    @ViewBuilder
    var contactMapBlock: some View {
        if let image = contactMapImage {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(height: 160)
                .padding(.horizontal, 14)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.bottom, 8)
        } else if !contactCoordinates.isEmpty {
            // Live preview path — themed renderer when the user picked one,
            // MapKit fallback otherwise.
            let style = ShareMapStyle.current
            let needsWide = ActivationMapHelpers.needsWideRenderer(
                qsoCoordinates: contactCoordinates.map(\.coord),
                myCoordinate: myCoordinate
            )
            if style.usesCustomRenderer || needsWide {
                ThemedMapImage(
                    coordinates: contactCoordinates.map(\.coord),
                    myCoordinate: myCoordinate,
                    style: style.usesCustomRenderer ? style : .midnight,
                    qthCentered: true
                )
                .allowsHitTesting(false)
                .frame(height: 160)
                .padding(.horizontal, 14)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.bottom, 8)
            } else if let myCoord = myCoordinate {
                Map(initialPosition: ActivationMapHelpers.qthCenteredRegion(
                    qsoCoordinates: contactCoordinates.map(\.coord),
                    myCoordinate: myCoord
                ).map { .region($0) } ?? .automatic) {
                    ForEach(Array(contactCoordinates.enumerated()), id: \.offset) { _, contact in
                        MapContentBuilders.geodesicArc(from: myCoord, to: contact.coord)
                    }
                    ForEach(Array(contactCoordinates.enumerated()), id: \.offset) { _, contact in
                        Annotation("", coordinate: contact.coord, anchor: .bottom) {
                            MapPinMarker(color: bandColor(contact.band))
                        }
                    }
                    Annotation("QTH", coordinate: myCoord, anchor: .center) {
                        Circle()
                            .fill(.white)
                            .frame(width: 8, height: 8)
                            .overlay(Circle().stroke(.purple, lineWidth: 2))
                    }
                }
                .standardMapStyle(isWideSpan: false)
                .allowsHitTesting(false)
                .frame(height: 160)
                .padding(.horizontal, 14)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.bottom, 8)
            }
        }
    }

    @ViewBuilder
    var equipmentBlock: some View {
        let parts = equipmentParts
        if !parts.isEmpty {
            HStack(spacing: 6) {
                ForEach(parts, id: \.label) { part in
                    BragSheetChip(label: part.label, icon: part.icon)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.top, 6)
        }
    }

    @ViewBuilder
    var timelineBlock: some View {
        let entries = timelineEntries
        if entries.count >= 2 {
            SessionTimelineView(entries: entries)
                .padding(.horizontal, 14)
                .padding(.top, 8)
                .padding(.bottom, 4)
        }
    }

    func statColumn(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .foregroundStyle(.white)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
    }

    var footer: some View {
        HStack {
            Text("CARRIER WAVE")
                .font(.caption2.weight(.bold))
                .tracking(1.5)
                .foregroundStyle(.white.opacity(0.5))
            Spacer()
            Text("tilesontheair.com")
                .font(.caption2.monospaced())
                .foregroundStyle(.white.opacity(0.5))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }
}

// MARK: - Derived

extension TOTABragSheetView {
    var inputs: TOTAScoringInputs {
        TOTAEnrichmentService.makeScoringInputs(for: session, qsos: qsos)
    }

    var result: TOTAScoringResult {
        TOTAScoringEngine.score(inputs)
    }

    var displayScore: Double {
        session.totaOfficialPoints ?? result.total
    }

    var confidenceLabel: String {
        session.totaOfficialPoints != nil ? "OFFICIAL" : "ESTIMATED"
    }

    var callsign: String {
        (session.stationCallsign ?? session.myCallsign).uppercased()
    }

    var tilesText: String {
        let tiles = session.tilesActivated
        if tiles.isEmpty {
            return "—"
        }
        return tiles.joined(separator: " · ")
    }

    var dateText: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: session.startedAt)
    }

    var distanceText: String {
        guard let miles = session.activationDistanceMiles, miles > 0 else {
            return "—"
        }
        return String(format: "%.1f mi", miles)
    }

    var uniqueBands: [String] {
        Array(Set(qsos.map(\.band))).sorted()
    }

    var durationText: String {
        let total = Int(session.duration)
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        if hours > 0 {
            return "\(hours)h\(minutes)m"
        }
        return "\(minutes)m"
    }

    var trackCoords: [CLLocationCoordinate2D] {
        session.trackPoints.map {
            CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
        }
    }

    var myCoordinate: CLLocationCoordinate2D? {
        if let lat = session.activationLatitude, let lon = session.activationLongitude {
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
        if let grid = session.myGrid,
           let coord = MaidenheadConverter.coordinate(from: grid)
        {
            return coord
        }
        return nil
    }

    var contactCoordinates: [ContactMapEntry] {
        qsos.compactMap { qso in
            guard let grid = qso.theirGrid,
                  let coord = MaidenheadConverter.coordinate(from: grid)
            else {
                return nil
            }
            return ContactMapEntry(grid: grid, band: qso.band, coord: coord)
        }
    }

    var dxccCount: Int {
        Set(qsos.compactMap(\.dxcc)).count
    }

    var farthestText: String? {
        guard let myCoord = myCoordinate else {
            return nil
        }
        let distances = contactCoordinates.map { contact -> Double in
            haversineKm(from: myCoord, to: contact.coord)
        }
        guard let max = distances.max(), max > 0 else {
            return nil
        }
        return String(format: "%.0f km", max)
    }

    func haversineKm(
        from origin: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D
    ) -> Double {
        let earthRadiusKm = 6_371.0
        let lat1 = origin.latitude * .pi / 180
        let lat2 = destination.latitude * .pi / 180
        let dLat = (destination.latitude - origin.latitude) * .pi / 180
        let dLon = (destination.longitude - origin.longitude) * .pi / 180
        let havSquared = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return earthRadiusKm * 2 * atan2(sqrt(havSquared), sqrt(1 - havSquared))
    }

    var uniqueModes: [String] {
        Array(Set(qsos.map(\.mode))).sorted()
    }

    var modesText: String {
        if uniqueModes.isEmpty {
            return "—"
        }
        return uniqueModes.joined(separator: " ")
    }

    var ratePerHourText: String {
        let hours = session.duration / 3_600
        guard hours > 0, !qsos.isEmpty else {
            return "—"
        }
        return String(format: "%.1f", Double(qsos.count) / hours)
    }

    var equipmentParts: [(icon: String, label: String)] {
        var parts: [(icon: String, label: String)] = []
        if let rig = session.myRig, !rig.isEmpty {
            parts.append((icon: "radio", label: rig))
        }
        if let antenna = session.myAntenna, !antenna.isEmpty {
            parts.append((icon: "antenna.radiowaves.left.and.right", label: antenna))
        }
        if let key = session.myKey, !key.isEmpty {
            parts.append((icon: "pianokeys", label: key))
        }
        return parts
    }

    var timelineEntries: [TimelineEntry] {
        qsos.map { TimelineEntry(timestamp: $0.timestamp, band: $0.band) }
    }

    var region: MKCoordinateRegion? {
        if !trackCoords.isEmpty {
            return Self.region(enclosing: trackCoords)
        }
        if let lat = session.activationLatitude, let lon = session.activationLongitude {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                latitudinalMeters: 4_000,
                longitudinalMeters: 4_000
            )
        }
        return nil
    }

    static func region(
        enclosing coords: [CLLocationCoordinate2D]
    ) -> MKCoordinateRegion {
        let lats = coords.map(\.latitude)
        let lons = coords.map(\.longitude)
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLon = lons.min(), let maxLon = lons.max()
        else {
            return MKCoordinateRegion()
        }
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.5, 0.005),
            longitudeDelta: max((maxLon - minLon) * 1.5, 0.005)
        )
        return MKCoordinateRegion(center: center, span: span)
    }

    var bonusChips: [String] {
        var chips: [String] = []
        if session.totaCategory == .mobile {
            chips.append("MOBILE")
        }
        if session.qrpActivation {
            chips.append("QRP ×2")
        }
        let isWinter = session.winterActivationOverride
            ?? TOTAWinterDetector.isWinter(
                latitude: session.activationLatitude,
                date: session.startedAt
            )
        if isWinter, session.totaCategory == .standard {
            chips.append("WINTER +20%")
        }
        if session.totaCategory == .standard {
            if let ruck = session.ruckWeightPounds, ruck >= 5 {
                chips.append("RUCK +\(Int(floor(ruck / 5)) * 5)%")
            }
            if let elev = session.activationElevationGainFeet, elev >= 200 {
                chips.append("ELEV +\(Int(floor(elev / 200)) * 2)%")
            }
            if session.withPets {
                chips.append("PETS +15%")
            }
            if session.withKids {
                chips.append("KIDS +20%")
            }
        }
        if session.winlinkSent {
            chips.append("WINLINK +5")
        }
        if session.aprsSent {
            chips.append("APRS +5")
        }
        if session.varacSent {
            chips.append("VARAC +5")
        }
        if let pef = session.personalEffortFactor, pef > 0 {
            chips.append("PEF \(pef)")
        }
        return chips
    }
}
