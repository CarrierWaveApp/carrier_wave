import CarrierWaveCore
import CarrierWaveData
import CoreLocation
import MapKit
import SwiftUI

// MARK: - SessionBragSheetCard Map & Stats

extension SessionBragSheetCard {
    var myCoordinate: CLLocationCoordinate2D? {
        guard let grid = item.details?.sessionMyGrid, grid.count >= 4 else {
            return nil
        }
        return MaidenheadConverter.coordinate(from: grid)
    }

    var contactCoordinates: [ContactMapEntry] {
        guard let grids = item.details?.sessionContactGrids else {
            return []
        }
        return grids.compactMap { entry in
            guard let coord = MaidenheadConverter.coordinate(from: entry.grid) else {
                return nil
            }
            return ContactMapEntry(grid: entry.grid, band: entry.band, coord: coord)
        }
    }

    @ViewBuilder
    var mapSection: some View {
        let style = ShareMapStyle(rawValue: shareMapStyleRaw) ?? .adaptive
        // MapKit can't show more than 180° of longitude, so QTH-centered
        // sessions wider than that use the Rust renderer in Midnight.
        let needsWide = ActivationMapHelpers.needsWideRenderer(
            qsoCoordinates: contactCoordinates.map(\.coord),
            myCoordinate: myCoordinate
        )
        if style.usesCustomRenderer || needsWide {
            ThemedMapImage(
                coordinates: contactCoordinates.map(\.coord),
                myCoordinate: myCoordinate,
                style: style.usesCustomRenderer ? style : .midnight,
                pinColors: contactCoordinates.map { UIColor(bandColor($0.band)) },
                qthCentered: true
            )
            .allowsHitTesting(false)
            .frame(height: 180)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 16)
        } else {
            let isWideSpan = ActivationMapHelpers.requiresGlobeView(
                qsoCoordinates: contactCoordinates.map(\.coord),
                myCoordinate: myCoordinate
            )
            Map(position: $mapCamera) {
                if let myCoord = myCoordinate {
                    ForEach(
                        Array(contactCoordinates.enumerated()), id: \.offset
                    ) { _, contact in
                        MapContentBuilders.geodesicArc(
                            from: myCoord, to: contact.coord
                        )
                    }
                }

                ForEach(
                    Array(contactCoordinates.enumerated()), id: \.offset
                ) { _, contact in
                    Annotation("", coordinate: contact.coord, anchor: .bottom) {
                        MapPinMarker(color: bandColor(contact.band))
                    }
                }
            }
            .standardMapStyle(isWideSpan: isWideSpan)
            .allowsHitTesting(false)
            .frame(height: 180)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 16)
            .task {
                mapCamera = mapCameraPosition
                if isWideSpan {
                    try? await Task.sleep(for: .seconds(0.5))
                    nudgeCamera()
                }
            }
        }
    }

    private func nudgeCamera() {
        guard let region = mapCamera.region else {
            return
        }
        let nudged = MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: region.center.latitude + 0.001,
                longitude: region.center.longitude
            ),
            span: region.span
        )
        mapCamera = .region(nudged)
    }

    var sessionInfoSection: some View {
        VStack(spacing: 4) {
            sessionTypeBadge
            if let parkRef = item.details?.parkReference {
                HStack(spacing: 6) {
                    Image(systemName: "tree.fill")
                        .font(.caption)
                    Text(parkRef)
                        .font(.subheadline)
                        .fontWeight(.bold)
                }
                .foregroundStyle(.white)

                if let parkName = item.details?.parkName {
                    Text(parkName)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
    }

    var totaSection: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "square.grid.3x3.fill")
                    .font(.caption)
                if let tiles = item.details?.totaTiles {
                    Text(tiles.joined(separator: ", "))
                        .font(.subheadline.monospaced().weight(.bold))
                }
                if let pef = item.details?.totaPersonalEffortFactor, pef > 0 {
                    Text("PEF \(pef)")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.15))
                        .clipShape(Capsule())
                }
                Spacer()
                if let score = item.details?.totaScore {
                    let confidence = item.details?.totaScoreConfidence ?? "estimated"
                    Text(String(format: "%.1f pts", score))
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.white)
                    Text(confidence == "official" ? "official" : "est.")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .foregroundStyle(.white)
            if let flags = item.details?.totaBonusFlags, !flags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(flags, id: \.self) { flag in
                            Text(flag)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.purple.opacity(0.4))
                                .foregroundStyle(.white)
                                .clipShape(Capsule())
                        }
                    }
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 16)
    }

    var statsSection: some View {
        let details = item.details
        let qsoCount = details?.qsoCount ?? 0
        let bandsCount = details?.sessionBands?.count ?? 0
        let modes = details?.sessionModes ?? []
        let duration = formatDuration(details?.sessionDurationMinutes)

        return VStack(spacing: 8) {
            HStack(spacing: 0) {
                BragSheetStatColumn(value: "\(qsoCount)", label: "QSOs")
                BragSheetStatColumn(value: duration, label: "Duration")
                BragSheetStatColumn(
                    value: "\(bandsCount)",
                    label: bandsCount == 1 ? "Band" : "Bands"
                )
                BragSheetStatColumn(
                    value: modes.joined(separator: " "),
                    label: modes.count == 1 ? "Mode" : "Modes"
                )
            }

            if hasDetailStats {
                detailStatsRow
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(BragSheetTheme.insetBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 14)
    }

    func clubMembersSection(_ members: [ClubMemberEntry]) -> some View {
        let counts = clubCounts(from: members)
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(counts, id: \.club) { entry in
                    statBadge("\(entry.count) \(entry.club)")
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.top, 4)
    }

    private func clubCounts(
        from members: [ClubMemberEntry]
    ) -> [(club: String, count: Int)] {
        var counts: [String: Int] = [:]
        for member in members {
            for club in member.clubs {
                counts[club, default: 0] += 1
            }
        }
        return counts.sorted { $0.key < $1.key }
            .map { (club: $0.key, count: $0.value) }
    }

    var equipmentSection: some View {
        HStack(spacing: 8) {
            if let rig = item.details?.sessionRig {
                equipmentBadge(icon: "radio", text: rig)
            }
            if let antenna = item.details?.sessionAntenna {
                equipmentBadge(icon: "antenna.radiowaves.left.and.right", text: antenna)
            }
        }
        .padding(.top, 8)
        .padding(.horizontal, 16)
    }

    var footerSection: some View {
        HStack {
            Text("CARRIER WAVE")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundStyle(.white.opacity(0.5))

            Spacer()

            if onShare != nil || onHide != nil || onDeleteFromServer != nil {
                footerMenu
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 16)
    }

    var footerMenu: some View {
        Menu {
            if let onShare {
                Button {
                    onShare()
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
            }
            if let onDeleteFromServer {
                Button(role: .destructive) {
                    onDeleteFromServer()
                } label: {
                    Label("Hide from everyone", systemImage: "trash")
                }
            }
            if let onHide {
                Button(role: .destructive) {
                    onHide()
                } label: {
                    Label(
                        "Hide this \(item.activityType.feedItemName)",
                        systemImage: "eye.slash"
                    )
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Internal Helpers

    var hasEquipment: Bool {
        item.details?.sessionRig != nil || item.details?.sessionAntenna != nil
    }

    var hasDetailStats: Bool {
        item.details?.sessionDXCCCount != nil || item.details?.sessionFarthestKm != nil
    }

    func formatDuration(_ minutes: Int?) -> String {
        guard let minutes, minutes > 0 else {
            return "--"
        }
        let hours = minutes / 60
        let mins = minutes % 60
        if hours > 0 {
            return "\(hours)h\(mins)m"
        }
        return "\(mins)m"
    }

    func statBadge(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .fontWeight(.medium)
            .foregroundStyle(.white.opacity(0.9))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.white.opacity(0.15))
            .clipShape(Capsule())
    }

    func equipmentBadge(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
            Text(text)
                .font(.caption2)
                .fontWeight(.medium)
                .lineLimit(1)
        }
        .foregroundStyle(.white.opacity(0.9))
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Color.white.opacity(0.15))
        .clipShape(Capsule())
    }

    // MARK: - Private Helpers

    var detailStatsRow: some View {
        HStack(spacing: 12) {
            if let dxccCount = item.details?.sessionDXCCCount, dxccCount > 0 {
                statBadge("\(dxccCount) DXCC")
            }
            if let farthest = item.details?.sessionFarthestKm {
                statBadge(UnitFormatter.distanceCompact(farthest, label: "max"))
            }
        }
    }

    var sessionTypeBadge: some View {
        let activationType = item.details?.sessionActivationType ?? "casual"
        let display = sessionTypeDisplay(activationType)
        return HStack(spacing: 4) {
            Image(systemName: display.icon)
                .font(.caption2)
            Text(display.label)
                .font(.caption)
                .fontWeight(.medium)
        }
        .foregroundStyle(.white.opacity(0.9))
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Color.white.opacity(0.15))
        .clipShape(Capsule())
    }

    var mapCameraPosition: MapCameraPosition {
        ActivationMapHelpers.qthCenteredRegion(
            qsoCoordinates: contactCoordinates.map(\.coord),
            myCoordinate: myCoordinate
        ).map { .region($0) } ?? .automatic
    }

    func sessionTypeDisplay(_ type: String) -> (icon: String, label: String) {
        switch type {
        case "pota": ("tree", "POTA Activation")
        case "sota": ("mountain.2", "SOTA Activation")
        default: ("radio", "Casual Session")
        }
    }
}
