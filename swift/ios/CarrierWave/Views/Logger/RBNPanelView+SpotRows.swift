import CarrierWaveData
import SwiftUI

// MARK: - RBNPanelView Spot Row Views

extension RBNPanelView {
    func spotRow(_ spot: UnifiedSpot) -> some View {
        HStack(spacing: 12) {
            sourceIndicator(spot)
            spotBadge(spot)
            spotDetails(spot)
        }
        .padding(.horizontal, displayMode == .embedded ? 0 : 16)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    func spotBadge(_ spot: UnifiedSpot) -> some View {
        if spot.isSelfSpot(userCallsign: callsign) {
            Text("SELF")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.indigo)
                .clipShape(Capsule())
        } else if !isPanel, friendCallsigns.contains(spot.callsign.uppercased()) {
            Text("FRIEND")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.green)
                .clipShape(Capsule())
        }
    }

    func spotDetails(_ spot: UnifiedSpot) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            spotHeaderRow(spot)
            spotMetadataRow(spot)
            if isPanel {
                spotComments(spot)
                spotParkName(spot)
            }
        }
    }

    func spotHeaderRow(_ spot: UnifiedSpot) -> some View {
        HStack(spacing: 6) {
            if let spotter = spot.spotter {
                Text(spotter)
                    .font(.subheadline.weight(.semibold).monospaced())
            }
            Text(spot.band)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.blue.opacity(0.2))
                .clipShape(Capsule())
            Spacer()
            Text(spot.formattedFrequency)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
        }
    }

    func spotMetadataRow(_ spot: UnifiedSpot) -> some View {
        HStack {
            if let snr = spot.snr {
                Text("\(snr) dB")
                    .font(.caption)
                    .foregroundStyle(snrColor(snr))
            }
            if let wpm = spot.wpm {
                Text("\(wpm) WPM")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let parkRef = spot.parkRef {
                Text(parkRef)
                    .font(.caption)
                    .foregroundStyle(.green)
            }
            Text(spot.mode)
                .font(.caption)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Color.blue.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 3))
            Spacer()
            Text(spot.timeAgo)
                .font(.caption2)
                .foregroundStyle(spot.ageColor)
        }
    }

    @ViewBuilder
    func spotComments(_ spot: UnifiedSpot) -> some View {
        if let comments = spot.comments, !comments.isEmpty {
            Text(comments)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    @ViewBuilder
    func spotParkName(_ spot: UnifiedSpot) -> some View {
        if let parkName = spot.parkName, !parkName.isEmpty {
            Text(parkName)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
    }

    func sourceIndicator(_ spot: UnifiedSpot) -> some View {
        ZStack {
            Circle()
                .fill(sourceColor(spot).opacity(0.2))
                .frame(width: 32, height: 32)
            Image(systemName: sourceIcon(spot))
                .font(.system(size: 14))
                .foregroundStyle(sourceColor(spot))
        }
    }
}
