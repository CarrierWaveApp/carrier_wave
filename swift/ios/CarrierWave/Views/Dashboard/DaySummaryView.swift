import CarrierWaveData
import SwiftData
import SwiftUI
import UIKit

// MARK: - DaySummaryView

/// Unified day-of-activity screen. Reached from `ActivityGrid` tap and
/// from `RecentQSOsSection`'s "See All". Replaces the hunter-only
/// `DailySummaryView`.
struct DaySummaryView: View {
    // MARK: Lifecycle

    init(date: Date) {
        _selectedDate = State(initialValue: date)
    }

    // MARK: Internal

    @Environment(\.modelContext) var modelContext
    @Environment(\.displayScale) var displayScale

    @AppStorage("shareMapStyle") var shareMapStyleRaw = "adaptive"

    // MARK: View state (visible to extensions)

    @State var snapshot: DaySummarySnapshot?
    @State var bridgedDayQSOs: [QSO] = []
    @State var expandedCardIds: Set<String> = []

    var selectedDateValue: Date {
        selectedDate
    }

    var body: some View {
        List {
            heroSection

            if let snapshot, !snapshot.dayQSOs.isEmpty {
                insightsSection
                bandTimelineSection
                sessionsSection
            } else if isLoading {
                skeletonSection
            } else {
                emptySection
            }
        }
        .listSectionSpacing(.compact)
        .navigationTitle("Daily Activity")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .navigationBar)
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
                ShareDaySummarySheet(image: image)
            }
        }
        .navigationDestination(for: DaySessionDestination.self) { destination in
            DaySessionDestinationView(sessionId: destination.sessionId)
        }
        .task(id: selectedDate) {
            await reload()
        }
    }

    // MARK: Private

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    @State private var selectedDate: Date
    @State private var isLoading = false
    @State private var showingShareSheet = false

    private var shareCardImage: UIImage? {
        guard let snapshot, !snapshot.dayQSOs.isEmpty else {
            return nil
        }
        let callsign = bridgedDayQSOs.first?.myCallsign ?? ""
        let bands = Set(snapshot.dayQSOs.map(\.band))
        let modes = Set(snapshot.dayQSOs.map(\.mode))
        let content = ShareCardContent.forDailyActivity(
            callsign: callsign,
            date: selectedDate,
            qsoCount: snapshot.dayQSOs.count,
            bands: bands,
            modes: modes
        )
        return ShareCardRenderer.render(content: content)
    }

    /// Full UTC day [00:00, 24:00) used as the timeline anchor.
    private var dayWindow: ClosedRange<Date> {
        let (start, end) = DaySummaryDataActor.utcDayWindow(for: selectedDate)
        return start ... end
    }

    // MARK: Hero

    private var heroSection: some View {
        Section {
            heroHeader
                .listRowSeparator(.hidden)

            if let snapshot, !snapshot.dayQSOs.isEmpty {
                SessionStatStrip(cells: heroStatCells(snapshot))
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))

                heroBandModePills(snapshot)
                    .listRowSeparator(.hidden)
            }
        }
    }

    private var heroHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Self.dateFormatter.string(from: selectedDate))
                .font(.title3.weight(.semibold))
            if isLoading {
                Text("Loading…")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            } else if snapshot?.dayQSOs.isEmpty != false {
                Text("No activity")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: Skeleton / empty

    private var skeletonSection: some View {
        Section {
            ForEach(0 ..< 3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemGray6))
                    .frame(height: 110)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }
        }
    }

    private var emptySection: some View {
        Section {
            ContentUnavailableView(
                "Nothing Logged",
                systemImage: "calendar.badge.exclamationmark",
                description: Text("No QSOs were logged on this day.")
            )
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }

    // MARK: Band timeline

    private var bandTimelineSection: some View {
        Section("Band Timeline") {
            BandTimelineView(qsos: bridgedDayQSOs, dayWindow: dayWindow, unwrapped: true)
                .listRowSeparator(.hidden)
        }
    }

    // MARK: Toolbar

    @ViewBuilder
    private var shareButton: some View {
        if snapshot?.dayQSOs.isEmpty == false {
            Button {
                showingShareSheet = true
            } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .accessibilityLabel("Share daily activity")
        }
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
    private func heroBandModePills(_ snapshot: DaySummarySnapshot) -> some View {
        let bands = snapshot.bandCounts
        let modes = snapshot.modeCounts
        if !bands.isEmpty || !modes.isEmpty {
            FlowLayout(spacing: 6) {
                ForEach(bands, id: \.band) { entry in
                    CountedPill(label: entry.band, count: entry.count, color: .blue)
                }
                ForEach(modes, id: \.mode) { entry in
                    CountedPill(label: entry.mode, count: entry.count, color: .green)
                }
            }
        }
    }

    private func reload() async {
        isLoading = true
        defer { isLoading = false }

        let container = modelContext.container
        let logId = activeLogId()
        let actor = DaySummaryDataActor(container: container, activityLogId: logId)
        do {
            let result = try await actor.load(for: selectedDate)
            snapshot = result
            bridgedDayQSOs = result.dayQSOs.map { $0.makeBridgedQSO() }
        } catch {
            RadioService.shared.addLog(.error, "DaySummaryView load failed: \(error)")
            snapshot = nil
            bridgedDayQSOs = []
        }
    }

    private func activeLogId() -> UUID? {
        let predicate = #Predicate<ActivityLog> { $0.isActive }
        var descriptor = FetchDescriptor<ActivityLog>(predicate: predicate)
        descriptor.fetchLimit = 1
        return (try? modelContext.fetch(descriptor))?.first?.id
    }

    private func heroStatCells(_ snapshot: DaySummarySnapshot) -> [StatStripCell] {
        let qsoCount = snapshot.dayQSOs.count
        let sessionCount = snapshot.sessions.count
            + (snapshot.hunterCard == nil ? 0 : 1)
            + (snapshot.looseCard == nil ? 0 : 1)

        let thirdCell = thirdHeroCell(snapshot)

        return [
            StatStripCell(value: "\(qsoCount)", label: "QSOs"),
            StatStripCell(
                value: "\(sessionCount)",
                label: sessionCount == 1 ? "Session" : "Sessions"
            ),
            thirdCell,
        ]
    }

    private func thirdHeroCell(_ snapshot: DaySummarySnapshot) -> StatStripCell {
        if snapshot.dxccCount > 0 {
            return StatStripCell(
                value: "\(snapshot.dxccCount)",
                label: snapshot.dxccCount == 1 ? "DXCC" : "DXCCs"
            )
        }
        let stateCount = snapshot.stateAbbreviations.count
        if stateCount > 0 {
            return StatStripCell(
                value: "\(stateCount)",
                label: stateCount == 1 ? "State" : "States"
            )
        }
        let bandCount = snapshot.bandCounts.count
        if bandCount > 0 {
            return StatStripCell(
                value: "\(bandCount)",
                label: bandCount == 1 ? "Band" : "Bands"
            )
        }
        let modeCount = snapshot.modeCounts.count
        return StatStripCell(
            value: "\(modeCount)",
            label: modeCount == 1 ? "Mode" : "Modes"
        )
    }
}

// MARK: - DaySummaryQSO bridge (MainActor)

@MainActor
extension DaySummaryQSO {
    /// Build an in-memory `QSO` from the snapshot for legacy components
    /// (`BandTimelineView`, `SessionQSOMap`, `StatesWorkedMosaic`, `QSORow`)
    /// that still take `[QSO]`. The instance is not registered with a
    /// `ModelContext` — it lives only as long as the view body retains it.
    func makeBridgedQSO() -> QSO {
        let qso = QSO(
            id: id,
            callsign: callsign,
            band: band,
            mode: mode,
            frequency: frequency,
            timestamp: timestamp,
            myCallsign: "",
            myGrid: myGrid,
            theirGrid: theirGrid,
            importSource: .logger,
            state: state,
            stationProfileName: stationProfileName,
            dxcc: dxcc
        )
        qso.loggingSessionId = loggingSessionId
        return qso
    }
}

// MARK: - ShareDaySummarySheet

private struct ShareDaySummarySheet: UIViewControllerRepresentable {
    let image: UIImage

    func makeUIViewController(context _: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [image], applicationActivities: nil)
    }

    func updateUIViewController(_: UIActivityViewController, context _: Context) {}
}
