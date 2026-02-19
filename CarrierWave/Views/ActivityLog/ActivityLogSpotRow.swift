import CarrierWaveCore
import SwiftUI

// MARK: - ActivityLogSpotRow

/// Individual spot row for the hunter spot list.
/// Shows frequency, callsign, source info, age indicator, and worked-before badges.
struct ActivityLogSpotRow: View {
    // MARK: Internal

    let spot: EnrichedSpot
    let workedResult: WorkedBeforeResult
    let huntedBehavior: HuntedSpotBehavior
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
            .opacity(isHunted ? 0.5 : 1.0)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Private

    // MARK: - Frequency Column

    @ScaledMetric(relativeTo: .subheadline) private var frequencyColumnWidth: CGFloat = 80

    private var isHunted: Bool {
        huntedBehavior == .crossOut && workedResult.isDupe(on: spot.spot.band)
    }

    private var frequencyColumn: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(FrequencyFormatter.format(spot.spot.frequencyMHz))
                .font(.subheadline.monospaced())
            HStack(spacing: 4) {
                Text(spot.spot.band)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(spot.spot.mode)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: frequencyColumnWidth, alignment: .trailing)
    }

    // MARK: - Callsign Column

    private var callsignColumn: some View {
        VStack(alignment: .leading, spacing: 2) {
            callsignRow
            sourceInfoRow
            workedBeforeBadges
        }
    }

    private var callsignRow: some View {
        HStack(spacing: 4) {
            Text(spot.spot.callsign)
                .font(.subheadline.weight(.semibold).monospaced())

            if spot.spot.source == .rbn {
                Text("RBN")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color(.tertiarySystemFill))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }
        }
    }

    @ViewBuilder
    private var sourceInfoRow: some View {
        if let parkRef = spot.spot.parkRef {
            HStack(spacing: 4) {
                Image(systemName: "tree.fill")
                    .font(.caption2)
                    .foregroundStyle(.green)
                Text(parkRef)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let parkName = spot.spot.parkName {
                    Text("- \(parkName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let state = spot.spot.stateAbbr {
                    statePill(state)
                }
            }
        } else if let snr = spot.spot.snr {
            HStack(spacing: 4) {
                Text("RBN")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("·")
                    .foregroundStyle(.secondary)
                Text("\(snr) dB")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let wpm = spot.spot.wpm {
                    Text("·")
                        .foregroundStyle(.secondary)
                    Text("\(wpm) WPM")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let state = spot.spot.stateAbbr {
                    Text("·")
                        .foregroundStyle(.secondary)
                    statePill(state)
                }
            }
        }
    }

    @ViewBuilder
    private var workedBeforeBadges: some View {
        let band = spot.spot.band

        if workedResult.isDupe(on: band) {
            dupeBadge(band: band, mode: spot.spot.mode)
        } else if !workedResult.todayBands.isEmpty {
            todayWorkedBadge(bands: workedResult.todayBands)
        } else if !workedResult.previousBands.isEmpty {
            previousWorkedBadge(bands: workedResult.previousBands)
        } else if workedResult.isNewDXCC {
            newDXCCBadge
        }
    }

    // MARK: - Age Column

    private var ageColumn: some View {
        HStack(spacing: 4) {
            Text(spot.spot.timeAgo)
                .font(.caption)
                .foregroundStyle(spot.spot.ageColor)
            Circle()
                .fill(spot.spot.ageColor)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Spotted \(spot.spot.timeAgo) ago")
    }

    private var newDXCCBadge: some View {
        Text("\u{2605} NEW DXCC")
            .font(.caption2.weight(.bold))
            .foregroundStyle(Color(.systemBackground))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.blue)
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .accessibilityLabel("New DXCC entity")
    }

    private func statePill(_ state: String) -> some View {
        Text(state)
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(Color(.tertiarySystemFill))
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    // MARK: - Badge Views

    private func dupeBadge(band: String, mode: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption2)
            Text("DUPE \(band) \(mode)")
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(.orange)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.orange.opacity(0.15))
        .clipShape(Capsule())
    }

    private func todayWorkedBadge(bands: Set<String>) -> some View {
        HStack(spacing: 2) {
            Image(systemName: "checkmark")
                .font(.caption2)
            Text(bands.sorted().joined(separator: " "))
                .font(.caption2.weight(.medium))
        }
        .foregroundStyle(.orange)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.orange.opacity(0.15))
        .clipShape(Capsule())
    }

    private func previousWorkedBadge(bands: Set<String>) -> some View {
        HStack(spacing: 2) {
            Image(systemName: "checkmark")
                .font(.caption2)
            Text(bands.sorted().joined(separator: " "))
                .font(.caption2.weight(.medium))
            Text("(prev)")
                .font(.caption2)
        }
        .foregroundStyle(.secondary)
    }
}
