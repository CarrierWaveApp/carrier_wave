import CarrierWaveCore
import SwiftUI

// MARK: - ActivityItemRow

struct ActivityItemRow: View {
    // MARK: Internal

    let item: ActivityItem
    var onShare: (() -> Void)?
    var onCallsignTap: ((String) -> Void)?

    var body: some View {
        if item.activityType == .sessionCompleted {
            SessionBragSheetCard(
                item: item,
                onCallsignTap: onCallsignTap,
                onShare: onShare
            )
        } else {
            standardRow
        }
    }

    // MARK: Private

    @AppStorage("useMetricUnits") private var useMetricUnits = false

    private var iconColor: Color {
        switch item.activityType {
        case .challengeTierUnlock,
             .challengeCompletion:
            .yellow
        case .newDXCCEntity:
            .blue
        case .newBand,
             .newMode:
            .purple
        case .dxContact:
            .green
        case .potaActivation:
            .green
        case .sotaActivation:
            .orange
        case .dailyStreak,
             .potaDailyStreak:
            .orange
        case .personalBest:
            .red
        case .workedFriend:
            .cyan
        case .sessionCompleted:
            .indigo
        }
    }

    private var activityDescription: String {
        let details = item.details

        switch item.activityType {
        case .challengeTierUnlock:
            if let tier = details?.tierName, let challenge = details?.challengeName {
                return "Reached \(tier) in \(challenge)"
            }
            return "Unlocked a new tier"

        case .challengeCompletion:
            if let challenge = details?.challengeName {
                return "Completed \(challenge)"
            }
            return "Completed a challenge"

        case .newDXCCEntity:
            if let entity = details?.entityName {
                return "Worked \(entity) for the first time"
            }
            return "Worked a new DXCC entity"

        case .newBand:
            if let band = details?.band {
                return "Made first \(band) contact"
            }
            return "Made contact on a new band"

        case .newMode:
            if let mode = details?.mode {
                return "Made first \(mode) contact"
            }
            return "Made contact with a new mode"

        case .dxContact:
            if let callsign = details?.workedCallsign, let distance = details?.distanceKm {
                let distanceStr = formatDistance(distance)
                return "Worked \(callsign) (\(distanceStr))"
            }
            return "Made a DX contact"

        case .potaActivation:
            if let park = details?.parkReference, let count = details?.qsoCount {
                return "Activated \(park) (\(count) QSOs)"
            }
            return "Completed a POTA activation"

        case .sotaActivation:
            if let summit = details?.parkReference, let count = details?.qsoCount {
                return "Activated \(summit) (\(count) QSOs)"
            }
            return "Completed a SOTA activation"

        case .dailyStreak:
            if let days = details?.streakDays {
                return "Hit a \(days)-day QSO streak"
            }
            return "Extended daily streak"

        case .potaDailyStreak:
            if let days = details?.streakDays {
                return "Hit a \(days)-day POTA streak"
            }
            return "Extended POTA streak"

        case .personalBest:
            if let recordType = details?.recordType, let value = details?.recordValue {
                return "New \(recordType) record: \(value)"
            }
            return "Set a new personal best"

        case .workedFriend:
            if let callsign = details?.workedCallsign {
                return "Worked friend \(callsign)"
            }
            return "Worked a friend"

        case .sessionCompleted:
            if let count = details?.qsoCount {
                return "Completed a session (\(count) QSOs)"
            }
            return "Completed a session"
        }
    }

    private var detailText: String? {
        let details = item.details

        var parts: [String] = []

        if let band = details?.band {
            parts.append(band)
        }
        if let mode = details?.mode {
            parts.append(mode)
        }

        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var standardRow: some View {
        // swiftlint:disable:next redundant_discardable_let
        let _ = useMetricUnits // Trigger re-render when unit preference changes
        return VStack(alignment: .leading, spacing: 8) {
            // Top row: icon, callsign, timestamp
            HStack(alignment: .top) {
                Image(systemName: item.activityType.icon)
                    .font(.title3)
                    .foregroundStyle(iconColor)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        if item.isOwn {
                            Text(item.callsign)
                                .font(.subheadline)
                                .fontWeight(.semibold)

                            Text("You")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.2))
                                .clipShape(Capsule())
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

                        Spacer()

                        Text(item.timestamp, style: .relative)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    // Activity description
                    Text(activityDescription)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            // Bottom row: details and share button
            HStack {
                if let detailText {
                    Text(detailText)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                if let onShare {
                    Button {
                        onShare()
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
    }

    private func formatDistance(_ km: Double) -> String {
        UnitFormatter.distance(km)
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 12) {
        ActivityItemRow(
            item: ActivityItem(
                callsign: "W1AW",
                activityType: .newDXCCEntity,
                timestamp: Date().addingTimeInterval(-7_200)
            )
        )

        ActivityItemRow(
            item: ActivityItem(
                callsign: "K2XYZ",
                activityType: .dailyStreak,
                timestamp: Date().addingTimeInterval(-3_600),
                isOwn: true
            ),
            onShare: { print("Share tapped") }
        )
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}
