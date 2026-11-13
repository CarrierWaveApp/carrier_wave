import CarrierWaveData
import SwiftUI

// MARK: - ActivityLogSpotRow

/// Individual spot row for the hunter spot list.
/// Shows frequency, callsign, source info, age indicator, and worked-before badges.
struct ActivityLogSpotRow: View {
    // MARK: Internal

    let spot: EnrichedSpot
    let workedResult: WorkedBeforeResult
    let huntedBehavior: HuntedSpotBehavior
    var isFriend: Bool = false
    let onTap: () -> Void
    var onTuneIn: (() -> Void)?
    var onRecall: (() -> Void)?
    var onSpot: (() -> Void)?

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
        .contextMenu {
            Button {
                onRecall?()
            } label: {
                Label("Recall", systemImage: "arrow.counterclockwise")
            }

            if canSpot, let onSpot {
                Button {
                    onSpot()
                } label: {
                    Label(
                        "Spot \(spot.spot.callsign)",
                        systemImage: "antenna.radiowaves.left.and.right"
                    )
                }
            }

            Button {
                onTuneIn?()
            } label: {
                Label(
                    "Tune In to \(spot.spot.callsign)",
                    systemImage: "radio"
                )
            }
        }
    }

    // MARK: Private

    // MARK: - Frequency Column

    @ScaledMetric(relativeTo: .subheadline) private var frequencyColumnWidth: CGFloat = 80

    private var isHunted: Bool {
        huntedBehavior == .crossOut
            && workedResult.isDupe(on: spot.spot.band, mode: spot.spot.mode, park: spot.spot.parkRef)
    }

    /// Only POTA spots with a park reference can be reposted via POTA's spot API.
    private var canSpot: Bool {
        spot.spot.source == .pota && spot.spot.parkRef != nil
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
        VStack(alignment: .leading, spacing: 4) {
            callsignRow
            sourceInfoRow
            membershipsRow
            workedBeforeBadges
        }
    }

    private var callsignRow: some View {
        HStack(spacing: 6) {
            Text(spot.spot.callsign)
                .font(.subheadline.weight(.semibold).monospaced())
                .strikethrough(isHunted)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)

            sourceTagPill

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var sourceTagPill: some View {
        switch spot.spot.source {
        case .rbn:
            sourceTag("RBN", foreground: .secondary, background: Color(.tertiarySystemFill))
        case .sota:
            sourceTag("SOTA", foreground: .brown, background: Color.brown.opacity(0.15))
        case .wwff:
            sourceTag("WWFF", foreground: .mint, background: Color.mint.opacity(0.15))
        case .pskr:
            sourceTag("PSKR", foreground: .purple, background: Color.purple.opacity(0.15))
        default:
            EmptyView()
        }
    }

    // MARK: - Memberships Row (FRIEND, clubs, SKCC)

    @ViewBuilder
    private var membershipsRow: some View {
        let clubNames = ClubsSyncService.shared.clubs(for: spot.spot.callsign)
        let hasClubs = !clubNames.isEmpty
        let hasSKCC = spot.skccMember != nil

        if isFriend || hasClubs || hasSKCC {
            HStack(spacing: 6) {
                if isFriend {
                    Text("FRIEND")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .badgePill(Color.green)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }

                if hasClubs {
                    HStack(spacing: 2) {
                        Image(systemName: "person.3.fill")
                            .font(.caption2)
                        Text(clubNames.joined(separator: ", "))
                            .font(.caption2)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.blue.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                }

                if let member = spot.skccMember {
                    Text("SKCC \(member.badge)")
                        .font(.caption2.weight(.medium).monospaced())
                        .foregroundStyle(.orange)
                        .badgePill(Color.orange.opacity(0.15))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .accessibilityLabel("SKCC \(member.award.displayName) number \(member.number)")
                }

                Spacer(minLength: 0)
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
        } else if let summitCode = spot.spot.summitCode {
            HStack(spacing: 4) {
                Image(systemName: "mountain.2.fill")
                    .font(.caption2)
                    .foregroundStyle(.brown)
                Text(summitCode)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let summitName = spot.spot.summitName {
                    Text("- \(summitName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let pts = spot.spot.summitPoints, pts > 0 {
                    Text("\(pts)pts")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.brown)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.brown.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
            }
        } else if let wwffRef = spot.spot.wwffRef {
            HStack(spacing: 4) {
                Image(systemName: "leaf.fill")
                    .font(.caption2)
                    .foregroundStyle(.mint)
                Text(wwffRef)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let wwffName = spot.spot.wwffName {
                    Text("- \(wwffName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
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
                        .accessibilityHidden(true)
                    statePill(state)
                }
            }
        }
    }

    @ViewBuilder
    private var workedBeforeBadges: some View {
        let band = spot.spot.band

        if workedResult.isDupe(on: band, mode: spot.spot.mode, park: spot.spot.parkRef), !isHunted {
            dupeBadge(band: band, mode: spot.spot.mode)
        } else if !workedResult.todayBands.isEmpty {
            todayWorkedBadge(bands: workedResult.todayBands)
        } else if !workedResult.previousBands.isEmpty {
            previousWorkedBadge(bands: workedResult.previousBands)
        } else if workedResult.isNewDXCC {
            newDXCCBadge
        }

        // Show need badges below worked-before badges
        if spot.hasNeeds {
            NeedBadgeRow(needs: spot.matchedNeeds)
        }
    }

    private func sourceTag(_ label: String, foreground: Color, background: Color) -> some View {
        Text(label)
            .font(.caption2)
            .foregroundStyle(foreground)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }
}
