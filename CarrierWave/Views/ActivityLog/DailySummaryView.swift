import SwiftData
import SwiftUI
import UIKit

// MARK: - DailySummaryView

/// Full day's activity with band timeline and complete QSO list.
/// Navigated to from "See All" in RecentQSOsSection.
struct DailySummaryView: View {
    // MARK: Internal

    let manager: ActivityLogManager

    @Environment(\.modelContext) var modelContext

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                dateHeader
                statsCard

                if !dayQSOs.isEmpty {
                    BandTimelineView(qsos: dayQSOs)
                    qsoList
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Daily Activity")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 12) {
                    shareButton
                    dayNavigationButtons
                }
            }
        }
        .sheet(isPresented: $showingShareSheet) {
            if let image = shareCardImage {
                ShareActivitySheet(image: image)
            }
        }
        .sheet(item: $editingQSO) { qso in
            QSOEditSheet(qso: qso) {
                loadDayQSOs()
            }
        }
        .alert(
            "Delete QSO",
            isPresented: Binding(
                get: { qsoToDelete != nil },
                set: { newValue in
                    if !newValue {
                        qsoToDelete = nil
                    }
                }
            )
        ) {
            Button("Delete", role: .destructive) {
                if let qso = qsoToDelete {
                    deleteQSO(qso)
                }
                qsoToDelete = nil
            }
            Button("Cancel", role: .cancel) {
                qsoToDelete = nil
            }
        } message: {
            if let qso = qsoToDelete {
                Text("Delete QSO with \(qso.callsign)?")
            }
        }
        .task {
            loadDayQSOs()
        }
        .onChange(of: selectedDate) {
            loadDayQSOs()
        }
    }

    // MARK: Private

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    @State private var selectedDate = Date()
    @State private var dayQSOs: [QSO] = []
    @State private var showingShareSheet = false
    @State private var editingQSO: QSO?
    @State private var qsoToDelete: QSO?

    @ScaledMetric(relativeTo: .caption) private var timeColumnWidth: CGFloat = 44
    @ScaledMetric(relativeTo: .subheadline) private var rowHeight: CGFloat = 44
    @ScaledMetric(relativeTo: .caption) private var dividerHeight: CGFloat = 28

    private var dividerCount: Int {
        dayQSOs.indices.filter { shouldShowDivider(at: $0) }.count
    }

    private var shareCardImage: UIImage? {
        let callsign = manager.activeLog?.myCallsign ?? ""
        let bands = Set(dayQSOs.map(\.band))
        let modes = Set(dayQSOs.map(\.mode))
        let content = ShareCardContent.forDailyActivity(
            callsign: callsign,
            date: selectedDate,
            qsoCount: dayQSOs.count,
            bands: bands,
            modes: modes
        )
        return ShareCardRenderer.render(content: content)
    }

    private var dateHeader: some View {
        Text(Self.dateFormatter.string(from: selectedDate))
            .font(.headline)
    }

    private var statsCard: some View {
        let bands = Set(dayQSOs.map(\.band))
        let modes = Set(dayQSOs.map(\.mode))

        return VStack(alignment: .leading, spacing: 4) {
            Text("\(dayQSOs.count) QSO\(dayQSOs.count == 1 ? "" : "s")")
                .font(.subheadline.weight(.semibold))

            HStack(spacing: 8) {
                Text("\(bands.count) band\(bands.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\u{00B7}")
                    .foregroundStyle(.secondary)
                Text("\(modes.count) mode\(modes.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var qsoList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("QSOs")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

            List {
                ForEach(Array(dayQSOs.enumerated()), id: \.element.id) { index, qso in
                    Button {
                        editingQSO = qso
                    } label: {
                        VStack(alignment: .leading, spacing: 0) {
                            if shouldShowDivider(at: index) {
                                stationGridDivider(for: qso)
                            }
                            dailyQSORow(qso)
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparatorTint(.secondary.opacity(0.3))
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            qsoToDelete = qso
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollDisabled(true)
            .scrollContentBackground(.hidden)
            .frame(
                height: rowHeight * CGFloat(dayQSOs.count)
                    + dividerHeight * CGFloat(dividerCount)
            )
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var dayNavigationButtons: some View {
        HStack(spacing: 12) {
            Button {
                selectedDate = Calendar.current.date(
                    byAdding: .day, value: -1, to: selectedDate
                ) ?? selectedDate
            } label: {
                Image(systemName: "chevron.left")
            }
            .accessibilityLabel("Previous day")

            Button {
                selectedDate = Calendar.current.date(
                    byAdding: .day, value: 1, to: selectedDate
                ) ?? selectedDate
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(Calendar.current.isDateInToday(selectedDate))
            .accessibilityLabel("Next day")
        }
    }

    @ViewBuilder
    private var shareButton: some View {
        if !dayQSOs.isEmpty {
            Button {
                showingShareSheet = true
            } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .accessibilityLabel("Share daily activity")
        }
    }

    private func dailyQSORow(_ qso: QSO) -> some View {
        HStack(spacing: 8) {
            Text(formatTime(qso.timestamp))
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .frame(width: timeColumnWidth, alignment: .trailing)

            Text(qso.callsign)
                .font(.subheadline.weight(.semibold).monospaced())

            bandModeBadge(band: qso.band, mode: qso.mode)

            if let park = qso.theirParkReference {
                Text(park)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(qso.rstSent ?? "599")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: rowHeight)
        .contentShape(Rectangle())
    }

    private func bandModeBadge(band: String, mode: String) -> some View {
        Text("\(band) \(mode)")
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(bandColor(band))
            .background(bandColor(band).opacity(0.15))
            .clipShape(Capsule())
    }
}

// MARK: - DailySummaryView + Helpers

extension DailySummaryView {
    func stationGridDivider(for qso: QSO) -> some View {
        let profileName = qso.stationProfileName ?? manager.currentProfile?.name
        return HStack(spacing: 4) {
            Image(systemName: "location.fill")
                .font(.caption2)
                .foregroundStyle(.secondary)
            if let name = profileName {
                Text(name)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            if profileName != nil, qso.myGrid != nil {
                Text("\u{00B7}")
                    .foregroundStyle(.tertiary)
            }
            if let grid = qso.myGrid {
                Text(grid)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .frame(height: dividerHeight)
        .accessibilityElement(children: .combine)
    }

    func formatTime(_ date: Date) -> String {
        Self.timeFormatter.string(from: date)
    }

    func shouldShowDivider(at index: Int) -> Bool {
        let qso = dayQSOs[index]
        guard qso.stationProfileName != nil || qso.myGrid != nil else {
            return false
        }
        // Always show for newest (top) and oldest (bottom) QSO
        if index == 0 || index == dayQSOs.count - 1 {
            return true
        }
        let prev = dayQSOs[index - 1]
        return qso.stationProfileName != prev.stationProfileName
            || qso.myGrid != prev.myGrid
    }

    func deleteQSO(_ qso: QSO) {
        qso.isHidden = true
        try? modelContext.save()
        loadDayQSOs()
    }

    func loadDayQSOs() {
        guard let log = manager.activeLog else {
            dayQSOs = []
            return
        }

        var calendar = Calendar.current
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let startOfDay = calendar.startOfDay(for: selectedDate)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        let logId = log.id
        let predicate = #Predicate<QSO> { qso in
            qso.loggingSessionId == logId
                && !qso.isHidden
                && qso.timestamp >= startOfDay
                && qso.timestamp < endOfDay
        }

        var descriptor = FetchDescriptor<QSO>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = 500

        dayQSOs = (try? modelContext.fetch(descriptor)) ?? []
    }
}

// MARK: - ShareActivitySheet

/// UIActivityViewController wrapper for sharing a rendered image
private struct ShareActivitySheet: UIViewControllerRepresentable {
    let image: UIImage

    func makeUIViewController(context _: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [image], applicationActivities: nil)
    }

    func updateUIViewController(_: UIActivityViewController, context _: Context) {}
}
