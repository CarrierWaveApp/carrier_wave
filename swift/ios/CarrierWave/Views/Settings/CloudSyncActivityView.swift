import CarrierWaveData
import SwiftUI

// MARK: - CloudSyncActivityView

/// Timeline of recent sync events, grouped by date, newest first.
struct CloudSyncActivityView: View {
    // MARK: Internal

    var body: some View {
        List {
            if groupedEvents.isEmpty {
                ContentUnavailableView(
                    "No Sync Activity",
                    systemImage: "icloud",
                    description: Text("Sync events will appear here.")
                )
            } else {
                ForEach(groupedEvents, id: \.date) { group in
                    Section {
                        ForEach(group.events) { event in
                            eventRow(event)
                        }
                    } header: {
                        Text(sectionHeader(for: group.date))
                    }
                }
            }
        }
        .navigationTitle("Sync Log")
        .onAppear {
            Task { await syncService.refreshSyncEvents() }
        }
    }

    // MARK: Private

    private var syncService = CloudSyncService.shared

    private var groupedEvents: [DateGroup] {
        let calendar = Calendar.current
        let sorted = syncService.syncEvents.sorted {
            $0.timestamp > $1.timestamp
        }
        let grouped = Dictionary(grouping: sorted) {
            calendar.startOfDay(for: $0.timestamp)
        }
        return grouped
            .map { DateGroup(date: $0.key, events: $0.value) }
            .sorted { $0.date > $1.date }
    }

    private func eventRow(
        _ event: CloudSyncEvent
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: iconName(for: event.category))
                .foregroundStyle(iconColor(for: event.category))
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.detail)
                    .font(.subheadline)
                Text(
                    event.timestamp,
                    format: .dateTime.hour().minute().second()
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                if let count = event.recordCount {
                    Text("\(count)")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                if let dur = event.duration {
                    Text(String(format: "%.1fs", dur))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func iconName(
        for category: CloudSyncEvent.Category
    ) -> String {
        switch category {
        case .fetch: "arrow.down.circle"
        case .upload: "arrow.up.circle"
        case .conflict: "arrow.2.squarepath"
        case .error: "exclamationmark.triangle"
        case .accountChange: "person.circle"
        case .processing: "gearshape"
        }
    }

    private func iconColor(
        for category: CloudSyncEvent.Category
    ) -> Color {
        switch category {
        case .fetch: .primary
        case .upload: .blue
        case .conflict: .orange
        case .error: .red
        case .accountChange: .primary
        case .processing: .secondary
        }
    }

    private func sectionHeader(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            return date.formatted(date: .abbreviated, time: .omitted)
        }
    }
}

// MARK: - DateGroup

private struct DateGroup {
    let date: Date
    let events: [CloudSyncEvent]
}
