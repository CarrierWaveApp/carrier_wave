import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - ConditionsDateRange

enum ConditionsDateRange: String, CaseIterable, Identifiable {
    case week = "7d"
    case month = "30d"
    case quarter = "90d"
    case all = "All"

    // MARK: Internal

    var id: String {
        rawValue
    }

    var startDate: Date? {
        let calendar = Calendar.current
        switch self {
        case .week:
            return calendar.date(byAdding: .day, value: -7, to: Date())
        case .month:
            return calendar.date(byAdding: .day, value: -30, to: Date())
        case .quarter:
            return calendar.date(byAdding: .day, value: -90, to: Date())
        case .all:
            return nil
        }
    }
}

// MARK: - ConditionsTab

private enum ConditionsTab: String, CaseIterable, Identifiable {
    case timeline = "Timeline"
    case location = "By Location"

    // MARK: Internal

    var id: String {
        rawValue
    }
}

// MARK: - ConditionsHistoryView

/// Full-screen conditions history with timeline and location tabs.
struct ConditionsHistoryView: View {
    // MARK: Internal

    let tourState: TourState

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                dateRangePicker
                tabPicker

                if isLoading {
                    loadingView
                } else if snapshots.isEmpty {
                    emptyState
                } else {
                    switch selectedTab {
                    case .timeline:
                        ConditionsHistoryChartView(
                            snapshots: snapshots,
                            title: "Conditions Over Time"
                        )
                        .padding(.horizontal)

                    case .location:
                        ConditionsByLocationView(
                            groupedSnapshots: groupedSnapshots
                        )
                        .padding(.horizontal)
                    }
                }
            }
            .padding(.vertical)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Conditions")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: selectedRange) {
            await loadData()
        }
    }

    // MARK: Private

    @Environment(\.modelContext) private var modelContext

    @State private var selectedTab: ConditionsTab = .timeline
    @State private var selectedRange: ConditionsDateRange = .month
    @State private var snapshots: [EnvironmentalSnapshot] = []
    @State private var groupedSnapshots: [String: [EnvironmentalSnapshot]] = [:]
    @State private var isLoading = true

    private let dataActor = EnvironmentalDataActor()

    private var dateRangePicker: some View {
        HStack(spacing: 8) {
            ForEach(ConditionsDateRange.allCases) { range in
                Button {
                    selectedRange = range
                } label: {
                    Text(range.rawValue)
                        .font(.caption)
                        .fontWeight(selectedRange == range ? .semibold : .regular)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            selectedRange == range
                                ? Color.blue.opacity(0.2)
                                : Color(.systemGray5)
                        )
                        .foregroundStyle(
                            selectedRange == range ? .blue : .secondary
                        )
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }

            Spacer()

            Text("\(snapshots.count) samples")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal)
    }

    private var tabPicker: some View {
        Picker("View", selection: $selectedTab) {
            ForEach(ConditionsTab.allCases) { tab in
                Text(tab.rawValue).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading conditions data...")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "sun.max.trianglebadge.exclamationmark")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text("No Conditions Data")
                .font(.headline)
            Text("Start a logging session with auto-record conditions enabled to collect data.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }

    private func loadData() async {
        isLoading = true

        let start = selectedRange.startDate ?? Date.distantPast
        let end = Date()

        let container = modelContext.container

        do {
            snapshots = try await dataActor.fetchSnapshots(
                from: start, to: end, container: container
            )
            groupedSnapshots = try await dataActor.fetchSnapshotsGroupedByGrid(
                from: start, to: end, container: container
            )
        } catch {
            snapshots = []
            groupedSnapshots = [:]
        }

        isLoading = false
    }
}
