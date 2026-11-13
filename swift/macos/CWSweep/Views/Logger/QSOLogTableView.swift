import CarrierWaveCore
import CarrierWaveCwFfi
import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - QSOLogTableView

/// Compact QSO log table with consolidated columns and date separators.
struct QSOLogTableView: View {
    var sessionId: UUID?

    var body: some View {
        CompactQSOTable(sessionId: sessionId)
    }
}

// MARK: - CompactQSOTable

struct CompactQSOTable: View {
    // MARK: Internal

    var sessionId: UUID?

    @State var selection: Set<QSOTableRow.ID> = []

    @Environment(\.modelContext) var modelContext

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider()
            qsoTable
                .alternatingRowBackgrounds()
                .environment(\.defaultMinListRowHeight, QSOLogRowMetrics.rowHeight)
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { newWidth in
            tableWidth = newWidth
        }
        .task { loadQSOs() }
        .onChange(of: sortOrder) { _, _ in
            applyFilterAndSort()
        }
        .onChange(of: queryText) {
            applyFilterAndSort()
        }
        .task { await observeRemoteChanges() }
        .onChange(of: selectionState.logInsertedQSORow?.id) { _, newId in
            guard newId != nil, let row = selectionState.logInsertedQSORow else {
                return
            }
            selectionState.logInsertedQSORow = nil
            allRows.insert(row, at: 0)
            applyFilterAndSort()
        }
        .onChange(of: selectionState.logRemovedQSOId) { _, newId in
            guard let newId else {
                return
            }
            selectionState.logRemovedQSOId = nil
            allRows.removeAll { $0.id == newId }
            applyFilterAndSort()
        }
        .onChange(of: selectionState.logUpdatedQSORow?.id) { _, newId in
            guard newId != nil, let row = selectionState.logUpdatedQSORow else {
                return
            }
            selectionState.logUpdatedQSORow = nil
            if let idx = allRows.firstIndex(where: { $0.id == row.id }) {
                allRows[idx] = row
            }
            applyFilterAndSort()
        }
        .onChange(of: selection) { _, newSelection in
            selectionState.selectedQSOId = newSelection.first
            if newSelection.first != nil {
                selectionState.selectedSpot = nil
                selectionState.focusedPane = .qsoLog
            }
        }
        .onChange(of: selectionState.selectedQSOId) { _, newId in
            guard let newId, selection.first != newId else {
                return
            }
            selection = [newId]
        }
        .onKeyPress("/") {
            isSearchFocused = true
            return .handled
        }
        .alert(deleteAlertTitle, isPresented: showDeleteAlert, actions: {
            Button("Delete", role: .destructive) { hideQSOs(ids: pendingDeleteIds); pendingDeleteIds = [] }
            Button("Cancel", role: .cancel) { pendingDeleteIds = [] }
        }, message: { Text(deleteAlertMessage) })
    }

    // MARK: Private

    /// Maximum deduplicated rows to display — keeps scroll performance smooth.
    private static let maxDisplayRows = 500

    /// All loaded rows before query filtering
    @State private var allRows: [QSOTableRow] = []
    /// Filtered + sorted rows for display
    @State private var displayRows: [QSOTableRow] = []
    @State private var sortOrder = [KeyPathComparator(\QSOTableRow.timestamp, order: .reverse)]
    @State private var pendingDeleteIds: [UUID] = []
    @State private var queryText = ""
    /// Whether the active session is a rove (multi-park) — drives park column visibility
    @State private var isRove = false
    /// Tracked width for progressive column hiding
    @State private var tableWidth: CGFloat = 800
    @FocusState private var isSearchFocused: Bool
    @Environment(SelectionState.self) private var selectionState

    private var showName: Bool {
        tableWidth >= 500
    }

    private var showRST: Bool {
        tableWidth >= 500
    }

    private var showMode: Bool {
        tableWidth >= 380
    }

    private var timeColumn: some TableColumnContent<QSOTableRow, KeyPathComparator<QSOTableRow>> {
        TableColumn("Time", value: \.timestamp) { row in
            VStack(alignment: .leading, spacing: 0) {
                Text(row.isFirstOfDate ? row.dateKey : " ")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(height: QSOLogRowMetrics.dateLineHeight)
                Text(row.timeDisplay)
                    .font(.caption.monospacedDigit())
                    .frame(height: QSOLogRowMetrics.timeLineHeight)
            }
            .qsoLogCell()
        }
        .width(min: 40, ideal: 60)
    }

    private var callsignColumn: some TableColumnContent<QSOTableRow, KeyPathComparator<QSOTableRow>> {
        TableColumn("Callsign", value: \.callsign) { row in
            HStack(spacing: 4) {
                Text(row.callsign).fontWeight(.medium)
                if row.hasParkReference {
                    Image(systemName: "tree.fill")
                        .font(.caption2)
                        .foregroundStyle(.green)
                        .frame(width: QSOLogRowMetrics.inlineIconSize, height: QSOLogRowMetrics.inlineIconSize)
                }
            }
            .qsoLogCell()
        }
        .width(min: 50, ideal: 80)
    }

    private var nameColumn: some TableColumnContent<QSOTableRow, Never> {
        TableColumn("Name") { (row: QSOTableRow) in
            Text(row.name ?? "\u{2014}")
                .foregroundStyle(row.name != nil ? .primary : .tertiary)
                .qsoLogCell()
        }
        .width(min: showName ? 40 : 0, ideal: showName ? 80 : 0)
    }

    private var freqBandColumn: some TableColumnContent<QSOTableRow, Never> {
        TableColumn("Freq / Band") { (row: QSOTableRow) in
            HStack(spacing: 4) {
                if let freq = row.freqDisplay {
                    Text(freq).monospacedDigit()
                } else {
                    Text("\u{2014}").foregroundStyle(.tertiary)
                }
                Text(row.band)
                    .font(.caption2)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(.quaternary)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    .fixedSize()
            }
            .qsoLogCell()
        }
        .width(min: 60, ideal: 90)
    }

    private var modeColumn: some TableColumnContent<QSOTableRow, KeyPathComparator<QSOTableRow>> {
        TableColumn("Mode", value: \.mode) { row in
            Text(row.mode)
                .font(.caption)
                .qsoLogCell()
        }
        .width(min: showMode ? 28 : 0, ideal: showMode ? 35 : 0)
    }

    private var rstColumn: some TableColumnContent<QSOTableRow, Never> {
        TableColumn("RST") { (row: QSOTableRow) in
            Text(row.rstCombined ?? "\u{2014}")
                .monospacedDigit()
                .foregroundStyle(row.rstCombined != nil ? .primary : .tertiary)
                .qsoLogCell()
        }
        .width(min: showRST ? 35 : 0, ideal: showRST ? 55 : 0)
    }

    private var parkColumn: some TableColumnContent<QSOTableRow, Never> {
        TableColumn("Park") { (row: QSOTableRow) in
            Text(row.parkReference ?? "\u{2014}")
                .foregroundStyle(row.parkReference != nil ? Color.accentColor : Color.secondary)
                .font(.caption.monospaced())
                .qsoLogCell()
        }
        .width(isRove ? 80 : 0)
    }

    private var showDeleteAlert: Binding<Bool> {
        Binding(get: { !pendingDeleteIds.isEmpty }, set: {
            if !$0 {
                pendingDeleteIds = []
            }
        })
    }

    private var deleteAlertTitle: String {
        pendingDeleteIds.count == 1 ? "Delete QSO" : "Delete \(pendingDeleteIds.count) QSOs"
    }

    private var deleteAlertMessage: String {
        if pendingDeleteIds.count == 1, let row = displayRows.first(where: { $0.id == pendingDeleteIds.first }) {
            return "Delete QSO with \(row.callsign)?"
        }
        return "Delete \(pendingDeleteIds.count) selected QSOs? This cannot be undone."
    }

    // MARK: - Table Definition (split for type-checker)

    private var qsoTable: some View {
        Table(of: QSOTableRow.self, selection: $selection, sortOrder: $sortOrder) {
            timeColumn
            callsignColumn
            nameColumn
            freqBandColumn
            modeColumn
            rstColumn
            parkColumn
        } rows: {
            ForEach(displayRows) { row in
                TableRow(row)
                    .contextMenu {
                        Button("Delete", role: .destructive) {
                            pendingDeleteIds = idsForDeletion(clickedId: row.id)
                        }
                    }
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.tertiary)
            TextField("Search (/ to focus) — call:, band:, mode:, park:, after:", text: $queryText)
                .textFieldStyle(.plain)
                .focused($isSearchFocused)
                .onSubmit { applyFilterAndSort() }
            if !queryText.isEmpty {
                Button {
                    queryText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)

                Text("\(displayRows.count) results")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
    }

    /// Project a table row onto the query-addressable field set. Sweep's rows
    /// only carry a subset of QSO fields (no grid/state/freq-as-number/etc.), so
    /// unavailable fields are `nil` and terms over them simply don't match.
    private static func ffiQueryQso(from row: QSOTableRow) -> FfiQueryQso {
        FfiQueryQso(
            callsign: row.callsign,
            band: row.band,
            mode: row.mode,
            myCallsign: nil,
            park: row.parkReference,
            sotaRef: nil,
            theirGrid: nil,
            state: nil,
            country: nil,
            name: row.name,
            qth: nil,
            notes: nil,
            myGrid: nil,
            frequencyKhz: nil,
            dxcc: nil,
            power: nil,
            qsoDate: Int64(row.timestamp.timeIntervalSince1970),
            qrzConfirmed: false,
            lotwConfirmed: false,
            importSource: ""
        )
    }

    private func idsForDeletion(clickedId: UUID) -> [UUID] {
        if selection.contains(clickedId), selection.count > 1 {
            return Array(selection)
        }
        return [clickedId]
    }

    /// Mark the first row of each date group so the time column can show the date.
    private func markFirstOfDate() {
        var lastDate = ""
        for idx in displayRows.indices {
            let isFirst = displayRows[idx].dateKey != lastDate
            displayRows[idx].isFirstOfDate = isFirst
            lastDate = displayRows[idx].dateKey
        }
    }

    /// Apply query filter to allRows and sort into displayRows. Filtering runs
    /// through the shared Rust query engine (`queryFilter`) — the same parser +
    /// in-memory evaluator the iOS app and web viewer use. On a parse error the
    /// rows are left unfiltered, matching the previous behavior.
    private func applyFilterAndSort() {
        var rows = allRows
        let trimmed = queryText.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            let ffiRows = rows.map(Self.ffiQueryQso(from:))
            if let indices = try? queryFilter(query: trimmed, qsos: ffiRows) {
                rows = indices.map { rows[Int($0)] }
            }
        }
        displayRows = rows.sorted(using: sortOrder)
        selectionState.logDisplayOrder = displayRows.map(\.id)
        markFirstOfDate()
    }
}

// MARK: - CompactQSOTable + Data

extension CompactQSOTable {
    func observeRemoteChanges() async {
        for await _ in NotificationCenter.default.notifications(named: .NSPersistentStoreRemoteChange) {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else {
                return
            }
            loadQSOs()
        }
    }

    func loadQSOs() {
        // Fetch isRove flag for the active session to drive park column visibility
        if let filterSessionId = sessionId {
            let sessionDesc = FetchDescriptor<LoggingSession>(
                predicate: #Predicate { $0.id == filterSessionId }
            )
            isRove = (try? modelContext.fetch(sessionDesc).first?.isRove) ?? false
        } else {
            isRove = false
        }

        let predicate = qsoPredicate()
        let sortBy = [SortDescriptor(\QSO.timestamp, order: .reverse)]
        var seen = Set<String>()
        var rows: [QSOTableRow] = []
        var offset = 0

        while rows.count < Self.maxDisplayRows {
            let descriptor = BoundedDescriptor<QSO>(
                predicate: predicate,
                sortBy: sortBy,
                limit: BoundedDescriptor<QSO>.maxLimit,
                offset: offset
            )
            let batch = (try? modelContext.boundedFetch(descriptor)) ?? []
            if batch.isEmpty {
                break
            }
            for qso in batch {
                guard rows.count < Self.maxDisplayRows else {
                    break
                }
                if seen.insert(qso.deduplicationKey).inserted,
                   !QSOMode.isMetadata(qso.mode)
                {
                    rows.append(QSOTableRow(from: qso))
                }
            }
            offset += batch.count
        }
        allRows = rows
        applyFilterAndSort()
    }

    func qsoPredicate() -> Predicate<QSO> {
        if let filterSessionId = sessionId {
            return #Predicate<QSO> {
                !$0.isHidden && !$0.callsign.isEmpty && $0.loggingSessionId == filterSessionId
            }
        }
        return #Predicate<QSO> { !$0.isHidden && !$0.callsign.isEmpty }
    }
}

// MARK: - QSO Log Cell Modifier

private extension View {
    /// Pins a QSO log cell to the shared fixed row height and forces its text
    /// onto one truncated line. Every column applies this so optional badges,
    /// long callsigns, or hidden (zero-width) columns can never change the
    /// row height (CAR-193).
    func qsoLogCell() -> some View {
        lineLimit(1)
            .truncationMode(.tail)
            .frame(height: QSOLogRowMetrics.rowHeight, alignment: .leading)
    }
}
