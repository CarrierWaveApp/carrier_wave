import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - QSOTableRow

/// Lightweight display-only snapshot of a QSO for table rendering.
/// Using plain structs instead of @Model objects avoids SwiftData observation
/// overhead that causes scroll jank with thousands of rows.
struct QSOTableRow: Identifiable, Sendable {
    // MARK: Lifecycle

    init(from qso: QSO) {
        id = qso.id
        timestamp = qso.timestamp
        callsign = qso.callsign
        frequency = qso.frequency
        band = qso.band
        mode = qso.mode
        rstSent = qso.rstSent
        rstReceived = qso.rstReceived
        parkReference = qso.parkReference
        theirParkReference = qso.theirParkReference
        theirGrid = qso.theirGrid
        name = qso.name
        contestSerialSent = qso.contestSerialSent
        contestSerialReceived = qso.contestSerialReceived
        contestExchangeSent = qso.contestExchangeSent
        contestExchangeReceived = qso.contestExchangeReceived
    }

    // MARK: Internal

    let id: UUID
    let timestamp: Date
    let callsign: String
    let frequency: Double?
    let band: String
    let mode: String
    let rstSent: String?
    let rstReceived: String?
    let parkReference: String?
    let theirParkReference: String?
    let theirGrid: String?
    let name: String?
    let contestSerialSent: Int?
    let contestSerialReceived: Int?
    let contestExchangeSent: String?
    let contestExchangeReceived: String?
}

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
        Table(of: QSOTableRow.self, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Date/Time", value: \.timestamp) { row in
                Text(row.timestamp, format: .dateTime
                    .month(.abbreviated).day()
                    .hour().minute())
                    .font(.caption.monospacedDigit())
            }
            .width(min: 100, ideal: 130)

            TableColumn("Callsign", value: \.callsign) { row in
                Text(row.callsign).fontWeight(.medium)
            }
            .width(min: 80, ideal: 100)

            TableColumn("Freq") { row in
                if let freq = row.frequency {
                    Text(String(format: "%.3f", freq)).monospacedDigit()
                } else {
                    Text("\u{2014}").foregroundStyle(.tertiary)
                }
            }
            .width(min: 70, ideal: 80)

            TableColumn("Band", value: \.band) { row in Text(row.band) }
                .width(min: 40, ideal: 50)
            TableColumn("Mode", value: \.mode) { row in Text(row.mode) }
                .width(min: 40, ideal: 50)

            TableColumn("RST S") { row in
                Text(row.rstSent ?? "\u{2014}").monospacedDigit()
            }
            .width(min: 40, ideal: 50)

            TableColumn("RST R") { row in
                Text(row.rstReceived ?? "\u{2014}").monospacedDigit()
            }
            .width(min: 40, ideal: 50)

            TableColumn("Park") { row in
                Text(row.theirParkReference ?? row.parkReference ?? "\u{2014}")
                    .foregroundStyle(
                        row.parkReference != nil ? .primary : .tertiary
                    )
            }
            .width(min: 60, ideal: 80)

            TableColumn("Grid") { row in
                Text(row.theirGrid ?? "\u{2014}")
                    .foregroundStyle(row.theirGrid != nil ? .primary : .tertiary)
            }
            .width(min: 50, ideal: 60)

            TableColumn("Name") { row in
                Text(row.name ?? "\u{2014}")
                    .foregroundStyle(row.name != nil ? .primary : .tertiary)
            }
            .width(min: 80, ideal: 120)
        } rows: {
            ForEach(displayRows) { row in
                TableRow(row)
                    .contextMenu {
                        Button("Delete", role: .destructive) {
                            hideQSO(id: row.id)
                        }
                    }
            }
        }
        .alternatingRowBackgrounds()
        .task { loadQSOs() }
        .onChange(of: sortOrder) { _, _ in
            displayRows.sort(using: sortOrder)
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

    @State private var displayRows: [QSOTableRow] = []
    @State private var selection: Set<QSOTableRow.ID> = []
    @State private var sortOrder = [KeyPathComparator(\QSOTableRow.timestamp, order: .reverse)]
    @Environment(\.modelContext) private var modelContext
    @Environment(SelectionState.self) private var selectionState

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
        descriptor.fetchLimit = 10_000
        let fetched = (try? modelContext.fetch(descriptor)) ?? []
        var seen = Set<UUID>()
        displayRows = fetched
            .filter {
                seen.insert($0.id).inserted
                    && !Self.metadataModes.contains($0.mode.uppercased())
            }
            .map { QSOTableRow(from: $0) }
            .sorted(using: sortOrder)
    }

    private func hideQSO(id: UUID) {
        let targetId = id
        var descriptor = FetchDescriptor<QSO>(
            predicate: #Predicate { $0.id == targetId }
        )
        descriptor.fetchLimit = 1
        if let qso = try? modelContext.fetch(descriptor).first {
            qso.isHidden = true
        }
        loadQSOs()
    }
}

// MARK: - ContestQSOTable

private struct ContestQSOTable: View {
    // MARK: Internal

    var body: some View {
        Table(of: QSOTableRow.self, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Date/Time", value: \.timestamp) { row in
                Text(row.timestamp, format: .dateTime
                    .month(.abbreviated).day()
                    .hour().minute())
                    .font(.caption.monospacedDigit())
            }
            .width(min: 100, ideal: 130)

            TableColumn("Callsign", value: \.callsign) { row in
                Text(row.callsign).fontWeight(.medium)
            }
            .width(min: 80, ideal: 100)

            TableColumn("Freq") { row in
                if let freq = row.frequency {
                    Text(String(format: "%.3f", freq)).monospacedDigit()
                } else {
                    Text("\u{2014}").foregroundStyle(.tertiary)
                }
            }
            .width(min: 70, ideal: 80)

            TableColumn("Band", value: \.band) { row in Text(row.band) }
                .width(min: 40, ideal: 50)
            TableColumn("Mode", value: \.mode) { row in Text(row.mode) }
                .width(min: 40, ideal: 50)

            TableColumn("RST") { row in
                let sent = row.rstSent ?? "\u{2014}"
                let recv = row.rstReceived ?? "\u{2014}"
                Text("\(sent)/\(recv)").monospacedDigit()
            }
            .width(min: 60, ideal: 70)

            TableColumn("Srl S") { row in
                if let serial = row.contestSerialSent {
                    Text(String(format: "%04d", serial)).monospacedDigit()
                } else {
                    Text("\u{2014}").foregroundStyle(.tertiary)
                }
            }
            .width(min: 40, ideal: 50)

            TableColumn("Srl R") { row in
                if let serial = row.contestSerialReceived {
                    Text(String(format: "%04d", serial)).monospacedDigit()
                } else {
                    Text("\u{2014}").foregroundStyle(.tertiary)
                }
            }
            .width(min: 40, ideal: 50)

            TableColumn("Exch S") { row in
                Text(row.contestExchangeSent ?? "\u{2014}")
                    .foregroundStyle(
                        row.contestExchangeSent != nil ? .primary : .tertiary
                    )
            }
            .width(min: 50, ideal: 70)

            TableColumn("Exch R") { row in
                Text(row.contestExchangeReceived ?? "\u{2014}")
                    .foregroundStyle(
                        row.contestExchangeReceived != nil ? .primary : .tertiary
                    )
            }
            .width(min: 50, ideal: 70)
        } rows: {
            ForEach(displayRows) { row in
                TableRow(row)
                    .contextMenu {
                        Button("Delete", role: .destructive) {
                            hideQSO(id: row.id)
                        }
                    }
            }
        }
        .alternatingRowBackgrounds()
        .task { loadQSOs() }
        .onChange(of: sortOrder) { _, _ in
            displayRows.sort(using: sortOrder)
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

    @State private var displayRows: [QSOTableRow] = []
    @State private var selection: Set<QSOTableRow.ID> = []
    @State private var sortOrder = [KeyPathComparator(\QSOTableRow.timestamp, order: .reverse)]
    @Environment(\.modelContext) private var modelContext
    @Environment(SelectionState.self) private var selectionState

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
        descriptor.fetchLimit = 10_000
        let fetched = (try? modelContext.fetch(descriptor)) ?? []
        var seen = Set<UUID>()
        displayRows = fetched
            .filter {
                seen.insert($0.id).inserted
                    && !Self.metadataModes.contains($0.mode.uppercased())
            }
            .map { QSOTableRow(from: $0) }
            .sorted(using: sortOrder)
    }

    private func hideQSO(id: UUID) {
        let targetId = id
        var descriptor = FetchDescriptor<QSO>(
            predicate: #Predicate { $0.id == targetId }
        )
        descriptor.fetchLimit = 1
        if let qso = try? modelContext.fetch(descriptor).first {
            qso.isHidden = true
        }
        loadQSOs()
    }
}
