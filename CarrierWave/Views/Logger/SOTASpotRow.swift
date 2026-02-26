import CarrierWaveCore
import SwiftUI

// MARK: - SOTASpotRow

/// A row displaying a single SOTA spot in the unified spots panel.
/// Mirrors `POTASpotRow` layout: frequency column, callsign + summit info, time ago.
struct SOTASpotRow: View {
    // MARK: Internal

    let spot: SOTASpot
    var friendCallsigns: Set<String> = []
    var workedResult: WorkedBeforeResult = .notWorked
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                frequencyColumn
                callsignColumn
                Spacer()
                ageColumn
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .opacity(isDupe ? 0.5 : 1.0)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Private

    private var spotBand: String {
        BandUtilities.deriveBand(from: spot.frequencyKHz) ?? ""
    }

    private var isDupe: Bool {
        workedResult.isDupe(on: spotBand)
    }

    private var isFriend: Bool {
        friendCallsigns.contains(spot.activatorCallsign.uppercased())
    }

    private var ageColor: Color {
        guard let timestamp = spot.parsedTimestamp else {
            return .secondary
        }
        let seconds = Date().timeIntervalSince(timestamp)
        switch seconds {
        case ..<120:
            return .green
        case ..<600:
            return .blue
        case ..<1_800:
            return .orange
        default:
            return .secondary
        }
    }

    // MARK: - Frequency Column

    private var frequencyColumn: some View {
        VStack(alignment: .trailing, spacing: 2) {
            if let mhz = spot.frequencyMHz {
                Text(FrequencyFormatter.format(mhz))
                    .font(.subheadline.monospaced())
            } else {
                Text(spot.frequency)
                    .font(.subheadline.monospaced())
            }
            HStack(spacing: 4) {
                if let kHz = spot.frequencyKHz,
                   let band = BandUtilities.deriveBand(from: kHz)
                {
                    Text(band)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(spot.mode)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 80, alignment: .trailing)
    }

    // MARK: - Callsign Column

    private var callsignColumn: some View {
        VStack(alignment: .leading, spacing: 2) {
            callsignRow
            summitInfoRow
            workedBeforeBadges
        }
    }

    private var callsignRow: some View {
        HStack(spacing: 4) {
            Text(spot.activatorCallsign)
                .font(.subheadline.weight(.semibold).monospaced())
                .strikethrough(isDupe)

            Text("SOTA")
                .font(.caption2)
                .foregroundStyle(.brown)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Color.brown.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 3))

            if isFriend {
                Text("FRIEND")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.green)
                    .clipShape(Capsule())
            }
        }
    }

    private var summitInfoRow: some View {
        HStack(spacing: 4) {
            Image(systemName: "mountain.2.fill")
                .font(.caption2)
                .foregroundStyle(.brown)
            Text(spot.fullSummitReference)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("- \(spot.summitName)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if spot.points > 0 {
                Text("\(spot.points)pts")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.brown)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.brown.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }
        }
    }

    // MARK: - Worked Before Badges

    @ViewBuilder
    private var workedBeforeBadges: some View {
        if isDupe {
            dupeBadge
        } else if !workedResult.todayBands.isEmpty {
            todayWorkedBadge
        } else if !workedResult.previousBands.isEmpty {
            previousWorkedBadge
        }
    }

    private var dupeBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption2)
            Text("DUPE \(spotBand) \(spot.mode)")
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(.orange)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.orange.opacity(0.15))
        .clipShape(Capsule())
    }

    private var todayWorkedBadge: some View {
        HStack(spacing: 2) {
            Image(systemName: "checkmark")
                .font(.caption2)
            Text(workedResult.todayBands.sorted().joined(separator: " "))
                .font(.caption2.weight(.medium))
        }
        .foregroundStyle(.orange)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.orange.opacity(0.15))
        .clipShape(Capsule())
    }

    private var previousWorkedBadge: some View {
        HStack(spacing: 2) {
            Image(systemName: "checkmark")
                .font(.caption2)
            Text(workedResult.previousBands.sorted().joined(separator: " "))
                .font(.caption2.weight(.medium))
            Text("(prev)")
                .font(.caption2)
        }
        .foregroundStyle(.secondary)
    }

    // MARK: - Age Column

    private var ageColumn: some View {
        Text(spot.timeAgo)
            .font(.caption)
            .foregroundStyle(ageColor)
    }
}
