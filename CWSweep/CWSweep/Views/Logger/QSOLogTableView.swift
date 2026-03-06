import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - QSOLogTableView

/// SwiftUI Table for QSO log display with sortable columns.
/// Contest-specific columns are shown when `showContestColumns` is true.
struct QSOLogTableView: View {
    var showContestColumns: Bool = false

    var body: some View {
        if showContestColumns {
            ContestQSOTable()
        } else {
            StandardQSOTable()
        }
    }
}

// MARK: - StandardQSOTable

private struct StandardQSOTable: View {
    // MARK: Internal

    var body: some View {
        Table(of: QSO.self, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Date/Time", value: \.timestamp) { qso in
                Text(qso.timestamp, format: .dateTime
                    .month(.abbreviated).day()
                    .hour().minute())
                    .font(.caption.monospacedDigit())
            }
            .width(min: 100, ideal: 130)

            TableColumn("Callsign", value: \.callsign) { qso in
                Text(qso.callsign).fontWeight(.medium)
            }
            .width(min: 80, ideal: 100)

            TableColumn("Freq") { qso in
                if let freq = qso.frequency {
                    Text(String(format: "%.3f", freq)).monospacedDigit()
                } else {
                    Text("\u{2014}").foregroundStyle(.tertiary)
                }
            }
            .width(min: 70, ideal: 80)

            TableColumn("Band", value: \.band) { qso in Text(qso.band) }
                .width(min: 40, ideal: 50)
            TableColumn("Mode", value: \.mode) { qso in Text(qso.mode) }
                .width(min: 40, ideal: 50)

            TableColumn("RST S") { qso in
                Text(qso.rstSent ?? "\u{2014}").monospacedDigit()
            }
            .width(min: 40, ideal: 50)

            TableColumn("RST R") { qso in
                Text(qso.rstReceived ?? "\u{2014}").monospacedDigit()
            }
            .width(min: 40, ideal: 50)

            TableColumn("Park") { qso in
                Text(qso.theirParkReference ?? qso.parkReference ?? "\u{2014}")
                    .foregroundStyle(qso.parkReference != nil ? .primary : .tertiary)
            }
            .width(min: 60, ideal: 80)

            TableColumn("Grid") { qso in
                Text(qso.theirGrid ?? "\u{2014}")
                    .foregroundStyle(qso.theirGrid != nil ? .primary : .tertiary)
            }
            .width(min: 50, ideal: 60)

            TableColumn("Name") { qso in
                Text(qso.name ?? "\u{2014}")
                    .foregroundStyle(qso.name != nil ? .primary : .tertiary)
            }
            .width(min: 80, ideal: 120)
        } rows: {
            ForEach(displayQSOs) { qso in
                TableRow(qso)
                    .contextMenu {
                        Button("Delete", role: .destructive) {
                            qso.isHidden = true
                            loadQSOs()
                        }
                    }
            }
        }
        .alternatingRowBackgrounds()
        .task { loadQSOs() }
        .onChange(of: sortOrder) { _, _ in
            displayQSOs.sort(using: sortOrder)
        }
        .task { await observeStoreChanges(.NSPersistentStoreRemoteChange) }
        .task { await observeStoreChanges(ModelContext.didSave) }
        .onChange(of: selection) { _, newSelection in
            selectionState.selectedQSOId = newSelection.first
            if newSelection.first != nil {
                selectionState.selectedSpot = nil
            }
        }
    }

    // MARK: Private

    private static let metadataModes: Set<String> = ["WEATHER", "SOLAR", "NOTE"]

    @State private var displayQSOs: [QSO] = []
    @State private var selection: Set<QSO.ID> = []
    @State private var sortOrder = [KeyPathComparator(\QSO.timestamp, order: .reverse)]
    @Environment(\.modelContext) private var modelContext
    @Environment(SelectionState.self) private var selectionState

    /// Observe a notification and re-fetch QSOs with debounce.
    /// Runs on MainActor (inherited from .task) so loadQSOs() is main-thread safe.
    private func observeStoreChanges(_ name: Notification.Name) async {
        for await _ in NotificationCenter.default.notifications(named: name) {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else {
                return
            }
            loadQSOs()
        }
    }

    private func loadQSOs() {
        var descriptor = FetchDescriptor<QSO>(
            predicate: #Predicate { !$0.isHidden && !$0.callsign.isEmpty },
            sortBy: [SortDescriptor(\QSO.timestamp, order: .reverse)]
        )
        // Fetch generously to compensate for CloudKit mirror duplicates (~3x),
        // then dedup and show all unique QSOs.
        descriptor.fetchLimit = 10_000
        let fetched = (try? modelContext.fetch(descriptor)) ?? []
        var seen = Set<UUID>()
        displayQSOs = fetched.filter {
            seen.insert($0.id).inserted && !Self.metadataModes.contains($0.mode.uppercased())
        }.sorted(using: sortOrder)
    }
}

// MARK: - ContestQSOTable

private struct ContestQSOTable: View {
    // MARK: Internal

    var body: some View {
        Table(of: QSO.self, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Date/Time", value: \.timestamp) { qso in
                Text(qso.timestamp, format: .dateTime
                    .month(.abbreviated).day()
                    .hour().minute())
                    .font(.caption.monospacedDigit())
            }
            .width(min: 100, ideal: 130)

            TableColumn("Callsign", value: \.callsign) { qso in
                Text(qso.callsign).fontWeight(.medium)
            }
            .width(min: 80, ideal: 100)

            TableColumn("Freq") { qso in
                if let freq = qso.frequency {
                    Text(String(format: "%.3f", freq)).monospacedDigit()
                } else {
                    Text("\u{2014}").foregroundStyle(.tertiary)
                }
            }
            .width(min: 70, ideal: 80)

            TableColumn("Band", value: \.band) { qso in Text(qso.band) }
                .width(min: 40, ideal: 50)
            TableColumn("Mode", value: \.mode) { qso in Text(qso.mode) }
                .width(min: 40, ideal: 50)

            TableColumn("RST") { qso in
                let s = qso.rstSent ?? "\u{2014}"
                let r = qso.rstReceived ?? "\u{2014}"
                Text("\(s)/\(r)").monospacedDigit()
            }
            .width(min: 60, ideal: 70)

            TableColumn("Srl S") { qso in
                if let serial = qso.contestSerialSent {
                    Text(String(format: "%04d", serial)).monospacedDigit()
                } else {
                    Text("\u{2014}").foregroundStyle(.tertiary)
                }
            }
            .width(min: 40, ideal: 50)

            TableColumn("Srl R") { qso in
                if let serial = qso.contestSerialReceived {
                    Text(String(format: "%04d", serial)).monospacedDigit()
                } else {
                    Text("\u{2014}").foregroundStyle(.tertiary)
                }
            }
            .width(min: 40, ideal: 50)

            TableColumn("Exch S") { qso in
                Text(qso.contestExchangeSent ?? "\u{2014}")
                    .foregroundStyle(qso.contestExchangeSent != nil ? .primary : .tertiary)
            }
            .width(min: 50, ideal: 70)

            TableColumn("Exch R") { qso in
                Text(qso.contestExchangeReceived ?? "\u{2014}")
                    .foregroundStyle(qso.contestExchangeReceived != nil ? .primary : .tertiary)
            }
            .width(min: 50, ideal: 70)
        } rows: {
            ForEach(displayQSOs) { qso in
                TableRow(qso)
                    .contextMenu {
                        Button("Delete", role: .destructive) {
                            qso.isHidden = true
                            loadQSOs()
                        }
                    }
            }
        }
        .alternatingRowBackgrounds()
        .task { loadQSOs() }
        .onChange(of: sortOrder) { _, _ in
            displayQSOs.sort(using: sortOrder)
        }
        .task { await observeStoreChanges(.NSPersistentStoreRemoteChange) }
        .task { await observeStoreChanges(ModelContext.didSave) }
        .onChange(of: selection) { _, newSelection in
            selectionState.selectedQSOId = newSelection.first
            if newSelection.first != nil {
                selectionState.selectedSpot = nil
            }
        }
    }

    // MARK: Private

    private static let metadataModes: Set<String> = ["WEATHER", "SOLAR", "NOTE"]

    @State private var displayQSOs: [QSO] = []
    @State private var selection: Set<QSO.ID> = []
    @State private var sortOrder = [KeyPathComparator(\QSO.timestamp, order: .reverse)]
    @Environment(\.modelContext) private var modelContext
    @Environment(SelectionState.self) private var selectionState

    /// Observe a notification and re-fetch QSOs with debounce.
    /// Runs on MainActor (inherited from .task) so loadQSOs() is main-thread safe.
    private func observeStoreChanges(_ name: Notification.Name) async {
        for await _ in NotificationCenter.default.notifications(named: name) {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else {
                return
            }
            loadQSOs()
        }
    }

    private func loadQSOs() {
        var descriptor = FetchDescriptor<QSO>(
            predicate: #Predicate { !$0.isHidden && !$0.callsign.isEmpty },
            sortBy: [SortDescriptor(\QSO.timestamp, order: .reverse)]
        )
        // Fetch generously to compensate for CloudKit mirror duplicates (~3x),
        // then dedup and show all unique QSOs.
        descriptor.fetchLimit = 10_000
        let fetched = (try? modelContext.fetch(descriptor)) ?? []
        var seen = Set<UUID>()
        displayQSOs = fetched.filter {
            seen.insert($0.id).inserted && !Self.metadataModes.contains($0.mode.uppercased())
        }.sorted(using: sortOrder)
    }
}
