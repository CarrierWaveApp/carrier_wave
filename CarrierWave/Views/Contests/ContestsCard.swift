import SwiftUI

/// Dashboard card showing active and upcoming amateur radio contests
/// from the WA7BNM Contest Calendar.
struct ContestsCard: View {
    // MARK: Internal

    var body: some View {
        cardContent
    }

    // MARK: Private

    @State private var service = ContestPollingService.shared

    private var activeCount: Int {
        service.activeContests.count
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerRow
            mainContent
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack {
            Image(systemName: "trophy.fill")
                .foregroundStyle(.orange)
            Text("Contests")
                .font(.headline)

            if activeCount > 0 {
                Text("\(activeCount) active")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color(red: 0.18, green: 0.5, blue: 0.22), in: Capsule())
            }

            Spacer()
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var mainContent: some View {
        if service.lastFetchDate == nil, service.fetchError == nil {
            loadingState
        } else if service.activeContests.isEmpty, service.upcomingContests.isEmpty {
            emptyState
        } else {
            contestLists
            timestampFooter
        }
    }

    private var loadingState: some View {
        ProgressView()
            .frame(maxWidth: .infinity, minHeight: 40)
    }

    private var emptyState: some View {
        HStack(spacing: 8) {
            Image(systemName: "trophy")
                .foregroundStyle(.tertiary)
            Text("No upcoming contests")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 40)
    }

    @ViewBuilder
    private var contestLists: some View {
        if !service.activeContests.isEmpty {
            activeSection
        }
        if !service.upcomingContests.isEmpty {
            upcomingSection
        }
    }

    // MARK: - Active Section

    private var activeSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Active Now")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            let displayed = Array(service.activeContests.prefix(2))
            ForEach(displayed) { contest in
                contestRow(contest, isActive: true)
            }

            let overflow = service.activeContests.count - displayed.count
            if overflow > 0 {
                Text("+\(overflow) more")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Upcoming Section

    private var upcomingSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Coming Up")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            let displayed = Array(service.upcomingContests.prefix(3))
            ForEach(displayed) { contest in
                contestRow(contest, isActive: false)
            }

            let overflow = service.upcomingContests.count - displayed.count
            if overflow > 0 {
                Text("+\(overflow) more")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Footer

    private var timestampFooter: some View {
        Group {
            if let lastFetch = service.lastFetchDate {
                Text(
                    "Updated: \(lastFetch.formatted(date: .abbreviated, time: .shortened))"
                )
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Row

    private func contestRow(_ contest: Contest, isActive: Bool) -> some View {
        Group {
            if let link = contest.link {
                Link(destination: link) {
                    rowContent(contest, isActive: isActive)
                }
                .buttonStyle(.plain)
            } else {
                rowContent(contest, isActive: isActive)
            }
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    private func rowContent(
        _ contest: Contest,
        isActive: Bool
    ) -> some View {
        HStack(spacing: 8) {
            if isActive {
                Circle()
                    .fill(.green)
                    .frame(width: 6, height: 6)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(contest.title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .foregroundStyle(.primary)

                if isActive {
                    Text("Ends \(contest.formattedEnd)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                } else {
                    Text("Starts \(contest.formattedStart)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            if contest.link != nil {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
