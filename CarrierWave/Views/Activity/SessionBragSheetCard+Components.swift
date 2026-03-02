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

    var mapSection: some View {
        let cameraPosition = mapCameraPosition
        return Map(initialPosition: cameraPosition) {
            // Trace lines first (drawn behind pins)
            if let myCoord = myCoordinate {
                ForEach(Array(contactCoordinates.enumerated()), id: \.offset) { _, contact in
                    MapPolyline(
                        coordinates: ActivationMapHelpers.geodesicPath(
                            from: myCoord, to: contact.coord
                        )
                    )
                    .stroke(.white.opacity(0.5), lineWidth: 2.5)
                }
            }

            // Traditional pin markers
            ForEach(Array(contactCoordinates.enumerated()), id: \.offset) { _, contact in
                Annotation(contact.grid, coordinate: contact.coord, anchor: .bottom) {
                    MapPinMarker(color: bandColor(contact.band))
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic))
        .allowsHitTesting(false)
        .frame(height: 180)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
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

    var statsSection: some View {
        let details = item.details
        let qsoCount = details?.qsoCount ?? 0
        let bandsCount = details?.sessionBands?.count ?? 0
        let modes = details?.sessionModes ?? []
        let duration = formatDuration(details?.sessionDurationMinutes)

        return VStack(spacing: 8) {
            HStack(spacing: 16) {
                ShareCardStatItem(value: "\(qsoCount)", label: "QSOs")
                ShareCardStatItem(value: duration, label: "Duration")
                ShareCardStatItem(
                    value: "\(bandsCount)",
                    label: bandsCount == 1 ? "Band" : "Bands"
                )
                ShareCardStatItem(
                    value: modes.joined(separator: " "),
                    label: modes.count == 1 ? "Mode" : "Modes"
                )
            }

            if hasDetailStats {
                detailStatsRow
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(Color.purple.opacity(0.2))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
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
        var allCoords = contactCoordinates.map(\.coord)
        if let myCoord = myCoordinate {
            allCoords.append(myCoord)
        }
        guard let region = ActivationMapHelpers.mapRegion(
            qsoCoordinates: allCoords,
            myCoordinate: myCoordinate
        ) else {
            return .automatic
        }
        return .region(region)
    }

    func sessionTypeDisplay(_ type: String) -> (icon: String, label: String) {
        switch type {
        case "pota": ("tree", "POTA Activation")
        case "sota": ("mountain.2", "SOTA Activation")
        default: ("radio", "Casual Session")
        }
    }
}
