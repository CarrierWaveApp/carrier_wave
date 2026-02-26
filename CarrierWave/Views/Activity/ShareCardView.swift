import CarrierWaveCore
import SwiftUI

// MARK: - ShareCardView

/// A branded card view for sharing activity items or summaries
struct ShareCardView: View {
    // MARK: Internal

    let content: ShareCardContent

    var body: some View {
        VStack(spacing: 0) {
            header
            Spacer()
            mainContent
            Spacer()
            footer
        }
        .frame(width: 400, height: 500)
        .background(
            LinearGradient(
                colors: [Color.accentColor, Color.accentColor.opacity(0.7)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }

    // MARK: Private

    private var header: some View {
        HStack {
            Image(systemName: content.iconName)
                .font(.title2)
            Text("CARRIER WAVE")
                .font(.headline)
                .fontWeight(.bold)
        }
        .foregroundStyle(.white)
        .padding(.top, 24)
    }

    private var mainContent: some View {
        VStack(spacing: 16) {
            Text(content.headline)
                .font(.title)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            if let subheadline = content.subheadline {
                Text(subheadline)
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
            }

            if !content.stats.isEmpty {
                statsGrid
            }
        }
        .padding(.horizontal, 32)
    }

    private var statsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
            ForEach(content.stats, id: \.label) { stat in
                VStack(spacing: 4) {
                    Text(stat.value)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                    Text(stat.label)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
        }
        .padding(.top, 8)
    }

    private var footer: some View {
        VStack(spacing: 4) {
            Text(content.callsign)
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
            if let dateRange = content.dateRange {
                Text(dateRange)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
        .padding(.bottom, 24)
    }
}

// MARK: - ShareCardContent

struct ShareCardContent {
    var iconName: String
    var headline: String
    var subheadline: String?
    var stats: [ShareCardStat]
    var callsign: String
    var dateRange: String?
}

// MARK: - ShareCardStat

struct ShareCardStat {
    var label: String
    var value: String
}

// MARK: - ShareCardContent Builders

extension ShareCardContent {
    /// Create a share card for an individual activity item
    static func forActivityItem(_ item: ActivityItem) -> ShareCardContent {
        switch item.activityType {
        case .newDXCCEntity,
             .dxContact,
             .newBand,
             .newMode,
             .workedFriend:
            forContactActivity(item)
        case .potaActivation,
             .sotaActivation:
            forActivationActivity(item)
        case .dailyStreak,
             .potaDailyStreak,
             .challengeTierUnlock,
             .challengeCompletion,
             .personalBest:
            forAchievementActivity(item)
        case .sessionCompleted:
            forSessionActivity(item)
        }
    }

    // MARK: - Contact Activities

    private static func forContactActivity(_ item: ActivityItem) -> ShareCardContent {
        let det = item.details
        let date = item.timestamp.formatted(date: .abbreviated, time: .omitted)
        switch item.activityType {
        case .newDXCCEntity:
            return ShareCardContent(
                iconName: "globe", headline: "Worked \(det?.entityName ?? "a new country")",
                subheadline: "for the first time!",
                stats: [
                    ShareCardStat(label: "Band", value: det?.band ?? ""),
                    ShareCardStat(label: "Mode", value: det?.mode ?? ""),
                ],
                callsign: item.callsign, dateRange: date
            )
        case .dxContact:
            let dist = Int(det?.distanceKm ?? 0)
            return ShareCardContent(
                iconName: "antenna.radiowaves.left.and.right", headline: "Long Distance QSO!",
                subheadline: det?.workedCallsign,
                stats: [
                    ShareCardStat(label: "Distance", value: "\(dist.formatted()) km"),
                    ShareCardStat(label: "Band", value: det?.band ?? ""),
                ],
                callsign: item.callsign, dateRange: date
            )
        case .newBand:
            return ShareCardContent(
                iconName: "waveform", headline: "First \(det?.band ?? "") Contact!",
                subheadline: "Exploring new frequencies",
                stats: [ShareCardStat(label: "Mode", value: det?.mode ?? "")],
                callsign: item.callsign, dateRange: date
            )
        case .newMode:
            return ShareCardContent(
                iconName: "waveform.badge.plus", headline: "First \(det?.mode ?? "") Contact!",
                subheadline: "Trying new modes",
                stats: [ShareCardStat(label: "Band", value: det?.band ?? "")],
                callsign: item.callsign, dateRange: date
            )
        default:
            return ShareCardContent(
                iconName: "radio", headline: "Activity", subheadline: nil,
                stats: [], callsign: item.callsign, dateRange: date
            )
        }
    }

    // MARK: - Activation Activities

    private static func forActivationActivity(_ item: ActivityItem) -> ShareCardContent {
        let details = item.details
        let dateString = item.timestamp.formatted(date: .abbreviated, time: .omitted)
        let qsoCount = details?.qsoCount ?? 0

        switch item.activityType {
        case .potaActivation:
            return ShareCardContent(
                iconName: "tree.fill",
                headline: "POTA Activation",
                subheadline: details?.parkName ?? "a park",
                stats: [ShareCardStat(label: "QSOs", value: "\(qsoCount)")],
                callsign: item.callsign,
                dateRange: dateString
            )
        case .sotaActivation:
            return ShareCardContent(
                iconName: "mountain.2.fill",
                headline: "SOTA Activation",
                subheadline: details?.parkName ?? "a summit",
                stats: [ShareCardStat(label: "QSOs", value: "\(qsoCount)")],
                callsign: item.callsign,
                dateRange: dateString
            )
        default:
            return ShareCardContent(
                iconName: "radio", headline: "Activation", subheadline: nil,
                stats: [], callsign: item.callsign, dateRange: dateString
            )
        }
    }

    // MARK: - Achievement Activities

    private static func forAchievementActivity(_ item: ActivityItem) -> ShareCardContent {
        let details = item.details
        let dateString = item.timestamp.formatted(date: .abbreviated, time: .omitted)

        switch item.activityType {
        case .dailyStreak,
             .potaDailyStreak:
            let days = details?.streakDays ?? 0
            let streakType = item.activityType == .potaDailyStreak ? "POTA" : "QSO"
            return ShareCardContent(
                iconName: "flame.fill",
                headline: "\(days)-Day \(streakType) Streak!",
                subheadline: "Keeping the radio active",
                stats: [],
                callsign: item.callsign,
                dateRange: dateString
            )
        case .challengeTierUnlock:
            return ShareCardContent(
                iconName: "trophy.fill",
                headline: "Reached \(details?.tierName ?? "") Tier!",
                subheadline: details?.challengeName ?? "",
                stats: [],
                callsign: item.callsign,
                dateRange: dateString
            )
        case .challengeCompletion:
            return ShareCardContent(
                iconName: "checkmark.seal.fill",
                headline: "Challenge Complete!",
                subheadline: details?.challengeName ?? "Challenge",
                stats: [],
                callsign: item.callsign,
                dateRange: dateString
            )
        case .personalBest:
            return ShareCardContent(
                iconName: "star.fill",
                headline: "New Personal Best!",
                subheadline: details?.recordType ?? "",
                stats: [ShareCardStat(label: "Record", value: details?.recordValue ?? "")],
                callsign: item.callsign,
                dateRange: dateString
            )
        default:
            return ShareCardContent(
                iconName: "star", headline: "Achievement", subheadline: nil,
                stats: [], callsign: item.callsign, dateRange: dateString
            )
        }
    }

    // MARK: - Session Activities

    private static func forSessionActivity(_ item: ActivityItem) -> ShareCardContent {
        let details = item.details
        let dateString = item.timestamp.formatted(date: .abbreviated, time: .omitted)
        let qsoCount = details?.qsoCount ?? 0
        var stats: [ShareCardStat] = [
            ShareCardStat(label: "QSOs", value: "\(qsoCount)"),
        ]
        if let duration = details?.sessionDurationMinutes, duration > 0 {
            let hours = duration / 60
            let mins = duration % 60
            let formatted = hours > 0 ? "\(hours)h \(mins)m" : "\(mins)m"
            stats.append(ShareCardStat(label: "Duration", value: formatted))
        }
        if let bands = details?.sessionBands, !bands.isEmpty {
            stats.append(ShareCardStat(label: "Bands", value: bands.joined(separator: ", ")))
        }
        return ShareCardContent(
            iconName: "checkmark.circle.fill",
            headline: "Session Complete!",
            subheadline: details?.sessionActivationType,
            stats: stats,
            callsign: item.callsign,
            dateRange: dateString
        )
    }

    /// Create a share card for brag sheet stats
    static func forBragSheet(
        result: BragSheetComputedResult,
        config: BragSheetPeriodConfig,
        period: BragSheetPeriod,
        callsign: String
    ) -> ShareCardContent {
        let headline = switch period {
        case .weekly: "My Week in Radio"
        case .monthly: "My Month in Radio"
        case .allTime: "All-Time Stats"
        }

        let stats: [ShareCardStat] = config.heroStats.prefix(4).compactMap { stat in
            let value = result.value(for: stat)
            guard value.hasData else {
                return nil
            }
            return ShareCardStat(label: stat.displayName, value: value.heroValue)
        }

        return ShareCardContent(
            iconName: "rosette",
            headline: headline,
            subheadline: nil,
            stats: stats,
            callsign: callsign,
            dateRange: period.periodLabel()
        )
    }

    /// Create a summary card for a date range
    static func forSummary(_ data: SummaryCardData) -> ShareCardContent {
        var stats: [ShareCardStat] = [
            ShareCardStat(label: "QSOs", value: "\(data.qsoCount)"),
            ShareCardStat(label: "Countries", value: "\(data.countriesWorked)"),
        ]

        if let distance = data.furthestDistance, distance > 0 {
            stats.append(ShareCardStat(label: "Furthest", value: "\(distance.formatted()) km"))
        }

        if let streak = data.streakDays, streak > 0 {
            stats.append(ShareCardStat(label: "Streak", value: "\(streak) days"))
        }

        return ShareCardContent(
            iconName: "radio",
            headline: data.title,
            subheadline: nil,
            stats: stats,
            callsign: data.callsign,
            dateRange: data.dateRange
        )
    }
}

// MARK: - SummaryCardData

struct SummaryCardData {
    var callsign: String
    var title: String
    var dateRange: String
    var qsoCount: Int
    var countriesWorked: Int
    var furthestDistance: Int?
    var streakDays: Int?
}

// MARK: - Preview

#Preview("Activity Item Card") {
    let item: ActivityItem = {
        let item = ActivityItem(
            callsign: "W1ABC",
            activityType: .newDXCCEntity,
            timestamp: Date(),
            isOwn: true
        )
        item.details = ActivityDetails(
            entityName: "Japan",
            band: "20m",
            mode: "SSB"
        )
        return item
    }()

    return ShareCardView(content: .forActivityItem(item))
        .padding()
        .background(Color(.systemBackground))
}

#Preview("Summary Card") {
    ShareCardView(
        content: .forSummary(
            SummaryCardData(
                callsign: "W1ABC",
                title: "My Week in Radio",
                dateRange: "Jan 21-28, 2026",
                qsoCount: 47,
                countriesWorked: 12,
                furthestDistance: 14_231,
                streakDays: 7
            )
        )
    )
    .padding()
    .background(Color(.systemBackground))
}
