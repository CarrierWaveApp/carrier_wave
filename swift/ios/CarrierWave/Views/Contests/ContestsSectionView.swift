import CarrierWaveCore
import CarrierWaveData
import SwiftUI

// MARK: - ContestsSectionView

/// Contests section for the On-Air sheet. Owns the state for the detail
/// sheet and the "See All" calendar navigation.
struct ContestsSectionView: View {
    // MARK: Internal

    let contestService: ContestPollingService

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if contestService.activeContests.isEmpty,
               contestService.upcomingContests.isEmpty
            {
                noDataCard
            } else {
                contestList
            }
        }
        .sheet(item: $selectedContest) { contest in
            ContestDetailSheet(contest: contest)
        }
    }

    // MARK: Private

    @State private var selectedContest: Contest?

    private var activeCount: Int {
        contestService.activeContests.count
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "trophy.fill")
                .font(.subheadline)
                .foregroundStyle(.orange)
                .accessibilityHidden(true)

            Text("Contests")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            if activeCount > 0 {
                Text("\(activeCount) active")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color(.systemBackground))
                    .badgePill(Color.green)
            }

            Spacer()
        }
    }

    private var noDataCard: some View {
        Text("No upcoming contests")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var contestList: some View {
        VStack(spacing: 0) {
            ForEach(contestService.activeContests.prefix(4)) { contest in
                contestRow(contest, isActive: true)
                if contest.id != contestService.activeContests.prefix(4).last?.id {
                    Divider().padding(.leading, 16)
                }
            }
            if !contestService.activeContests.isEmpty,
               !contestService.upcomingContests.isEmpty
            {
                Divider().padding(.leading, 16)
            }
            ForEach(contestService.upcomingContests.prefix(4)) { contest in
                contestRow(contest, isActive: false)
                if contest.id != contestService.upcomingContests.prefix(4).last?.id {
                    Divider().padding(.leading, 16)
                }
            }
        }
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func contestRow(_ contest: Contest, isActive: Bool) -> some View {
        Button {
            selectedContest = contest
        } label: {
            ContestRowContent(contest: contest, isActive: isActive)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - ContestRowContent

/// The visual content of a single contest row: title, countdown, chips,
/// optional progress bar.
struct ContestRowContent: View {
    // MARK: Internal

    let contest: Contest
    let isActive: Bool
    var showTimes: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            titleLine
            if showTimes {
                timeLine
            }
            ContestChipRow(contest: contest)
            if isActive {
                ContestProgressBar(contest: contest)
                    .padding(.top, 2)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    // MARK: Private

    private static let utcFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm'Z'"
        fmt.timeZone = TimeZone(identifier: "UTC")
        return fmt
    }()

    private static let localFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        fmt.timeZone = .current
        return fmt
    }()

    private var isSameDay: Bool {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return cal.isDate(contest.startDate, inSameDayAs: contest.endDate)
    }

    private var timeLine: some View {
        HStack(spacing: 6) {
            let utcStart = Self.utcFormatter.string(from: contest.startDate)
            let localStart = Self.localFormatter.string(from: contest.startDate)
            let localTZ = TimeZone.current.abbreviation() ?? "local"

            HStack(spacing: 2) {
                if isSameDay {
                    let utcEnd = Self.utcFormatter.string(from: contest.endDate)
                    Text("\(utcStart)–\(utcEnd)")
                        .font(.caption.monospaced().weight(.medium))
                        .foregroundStyle(.secondary)
                } else {
                    Text(utcStart)
                        .font(.caption.monospaced().weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }

            Text("\(localStart) \(localTZ)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private var titleLine: some View {
        HStack(spacing: 6) {
            if isActive {
                Circle()
                    .fill(.green)
                    .frame(width: 6, height: 6)
                    .accessibilityHidden(true)
            }

            Text(contest.title)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
                .foregroundStyle(.primary)

            Spacer()

            ContestCountdownLabel(contest: contest)

            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
    }
}
