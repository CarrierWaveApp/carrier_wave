import CarrierWaveData
import SwiftUI

// MARK: - ConsolidatedActivityRow

struct ConsolidatedActivityRow: View {
    // MARK: Internal

    let group: ActivityGroup
    var onShare: ((ActivityItem) -> Void)?
    var onHide: ((ActivityItem) -> Void)?
    var onDeleteFromServer: ((ActivityItem) -> Void)?
    var onCallsignTap: ((String) -> Void)?

    var body: some View {
        if group.isConsolidated {
            consolidatedView
        } else {
            ActivityItemRow(
                item: group.primaryItem,
                onShare: onShare.map { cb in { cb(group.primaryItem) } },
                onHide: onHide.map { cb in { cb(group.primaryItem) } },
                onDeleteFromServer: deleteHandler(for: group.primaryItem),
                onCallsignTap: onCallsignTap
            )
        }
    }

    // MARK: Private

    @State private var isExpanded = false
    @AppStorage("useMetricUnits") private var useMetricUnits = false

    private var summaryText: String {
        switch group.activityType {
        case .dxContact:
            group.dxContactSummary
        case .workedFriend:
            group.workedFriendSummary
        case .newDXCCEntity,
             .newBand,
             .newMode:
            group.milestoneSummary
        default:
            "\(group.count) activities"
        }
    }

    private var iconColor: Color {
        switch group.activityType {
        case .challengeTierUnlock,
             .challengeCompletion: .yellow
        case .newDXCCEntity: .blue
        case .newBand,
             .newMode: .purple
        case .dxContact: .green
        case .potaActivation: .green
        case .sotaActivation: .orange
        case .dailyStreak,
             .potaDailyStreak: .orange
        case .personalBest: .red
        case .workedFriend: .cyan
        case .sessionCompleted: .indigo
        }
    }

    private var consolidatedView: some View {
        let _ = useMetricUnits
        return VStack(alignment: .leading, spacing: 0) {
            // Header: consolidated summary
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                consolidatedHeader
            }
            .buttonStyle(.plain)

            // Expanded: individual items
            if isExpanded {
                expandedItems
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
    }

    private var consolidatedHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Image(systemName: group.activityType.icon)
                    .font(.title3)
                    .foregroundStyle(iconColor)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        callsignLabel
                        clubBadge
                        Spacer()
                        Text(group.latestTimestamp, style: .relative)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text(summaryText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            // Bottom: bands + expand indicator
            HStack {
                bandTags
                Spacer()
                expandIndicator
            }
        }
    }

    @ViewBuilder
    private var callsignLabel: some View {
        let item = group.primaryItem
        if item.isOwn {
            HStack(spacing: 4) {
                Text(item.callsign)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text("You")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.2))
                    .clipShape(Capsule())
            }
        } else if let onCallsignTap {
            Button {
                onCallsignTap(item.callsign)
            } label: {
                Text(item.callsign)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)
        } else {
            Text(item.callsign)
                .font(.subheadline)
                .fontWeight(.semibold)
        }
    }

    @ViewBuilder
    private var clubBadge: some View {
        if let clubName = ClubsSyncService.shared
            .clubs(for: group.callsign).first
        {
            Text(clubName)
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.blue.opacity(0.15))
                .clipShape(Capsule())
        }
    }

    private var bandTags: some View {
        HStack(spacing: 4) {
            ForEach(group.uniqueBands, id: \.self) { band in
                Text(band)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(.tertiarySystemFill))
                    .clipShape(Capsule())
            }
        }
    }

    private var expandIndicator: some View {
        HStack(spacing: 4) {
            Text("\(group.count)")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private var expandedItems: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider()
                .padding(.top, 8)

            ForEach(group.items) { item in
                expandedItemRow(item)
                if item.id != group.items.last?.id {
                    Divider()
                        .padding(.leading, 40)
                }
            }
        }
    }

    private func expandedItemRow(_ item: ActivityItem) -> some View {
        let details = item.details
        return HStack(alignment: .top, spacing: 8) {
            Color.clear.frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    contactLabel(details)
                    Spacer()
                    Text(item.timestamp, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                detailLine(details)
            }
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func contactLabel(_ details: ActivityDetails?) -> some View {
        switch group.activityType {
        case .dxContact:
            dxContactLabel(details)
        case .workedFriend:
            friendContactLabel(details)
        case .newDXCCEntity:
            if let entity = details?.entityName {
                Text(entity)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
        case .newBand:
            if let band = details?.band {
                Text("First \(band) contact")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
        case .newMode:
            if let mode = details?.mode {
                Text("First \(mode) contact")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
        default:
            EmptyView()
        }
    }

    private func dxContactLabel(_ details: ActivityDetails?) -> some View {
        HStack(spacing: 4) {
            if let callsign = details?.workedCallsign {
                Text(callsign)
                    .font(.subheadline.monospaced())
                    .fontWeight(.medium)
            }
            if let name = details?.workedName, !name.isEmpty {
                Text(name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func friendContactLabel(_ details: ActivityDetails?) -> some View {
        HStack(spacing: 4) {
            if let callsign = details?.workedCallsign {
                Text(callsign)
                    .font(.subheadline.monospaced())
                    .fontWeight(.medium)
            }
            if let name = details?.workedName, !name.isEmpty {
                Text(name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func detailLine(_ details: ActivityDetails?) -> some View {
        let parts = detailParts(details)
        if !parts.isEmpty {
            Text(parts.joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private func deleteHandler(for item: ActivityItem) -> (() -> Void)? {
        guard item.isOwn, item.serverId != nil, let onDelete = onDeleteFromServer else {
            return nil
        }
        return { onDelete(item) }
    }

    private func detailParts(_ details: ActivityDetails?) -> [String] {
        var parts: [String] = []

        if let entity = details?.workedEntity, !entity.isEmpty {
            parts.append(entity)
        }
        if let distance = details?.distanceKm {
            parts.append(UnitFormatter.distance(distance))
        }
        if let band = details?.band {
            parts.append(band)
        }
        if let mode = details?.mode {
            parts.append(mode)
        }

        return parts
    }
}
