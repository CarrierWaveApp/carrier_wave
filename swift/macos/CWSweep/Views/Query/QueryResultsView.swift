import AppKit
import CarrierWaveData
import SwiftUI

struct QueryResultsView: View {
    // MARK: Internal

    let result: QueryResultSet
    let columnHints: [String: String]?
    var onShowMore: (() -> Void)?
    var visibleLimit: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerStrip
            Divider()
            resultsTable
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(NSColor.textBackgroundColor))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: Private

    @AppStorage("autoXITEnabled") private var autoXITEnabled = false
    @AppStorage("autoXITOffsetHz") private var autoXITOffsetHz = 0
    @State private var didCopyRecently = false
    @State private var sortColumn: Int?
    @State private var sortAscending = true
    @Environment(RadioManager.self) private var radioManager
    @Environment(SpotAggregator.self) private var spotAggregator

    /// Apply the current header click-sort to the rows. Sort is stable —
    /// SQL's intentional ordering is preserved within ties — and NULL
    /// values always sink to the end regardless of direction so they
    /// don't dominate `ORDER BY ... ASC` clicks.
    private var displayRows: [[QueryValue]] {
        guard let col = sortColumn, col < result.columns.count else {
            return result.rows
        }
        let ascending = sortAscending
        return result.rows.enumerated().sorted { lhs, rhs -> Bool in
            let lvalue = col < lhs.element.count ? lhs.element[col] : .null
            let rvalue = col < rhs.element.count ? rhs.element[col] : .null
            let order = Self.compare(lvalue, rvalue)
            // Stable across equal keys: preserve original index order.
            if order == 0 {
                return lhs.offset < rhs.offset
            }
            // NULLs always last.
            if case .null = lvalue, case .null = rvalue {
                return lhs.offset < rhs.offset
            }
            if case .null = lvalue {
                return false
            }
            if case .null = rvalue {
                return true
            }
            return ascending ? order < 0 : order > 0
        }.map(\.element)
    }

    /// Sum of every column's width — used as the natural width of the
    /// table content so the ScrollView's leading edge anchor and our
    /// per-row backgrounds line up.
    private var contentWidth: CGFloat {
        (0 ..< result.columns.count).reduce(0) { $0 + columnWidth(idx: $1) }
    }

    /// Top strip: row count + show-more + copy-csv button. Stays
    /// outside the scroll view so the action is always reachable.
    private var headerStrip: some View {
        HStack(spacing: 12) {
            if result.truncated, let visibleLimit {
                Text("Showing \(visibleLimit) of \(result.rowCount)")
            } else {
                Text("\(result.rowCount) row\(result.rowCount == 1 ? "" : "s")")
            }
            if result.truncated, let onShowMore {
                Button("Show more") { onShowMore() }
                    .buttonStyle(.borderless)
                    .foregroundStyle(Color.accentColor)
            }
            Spacer()
            Button {
                copyAsCSV()
            } label: {
                Label(
                    didCopyRecently ? "Copied" : "Copy CSV",
                    systemImage: didCopyRecently ? "checkmark" : "doc.on.doc"
                )
                .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.borderless)
            .help("Copy the entire result set to the clipboard as CSV (RFC 4180)")
            .disabled(result.rowCount == 0)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    /// Body table — content is sized to AT LEAST the viewport's
    /// dimensions via `GeometryReader`, with `topLeading` alignment,
    /// so when the table is smaller than the pane the rows pin to
    /// the top-left corner. (SwiftUI's macOS `ScrollView` centers
    /// small content along both axes by default; the `minWidth/
    /// minHeight` from the geometry proxy is what overrides that.)
    /// When content exceeds the viewport, the `min*` constraints are
    /// satisfied trivially and scroll bars engage as expected.
    private var resultsTable: some View {
        GeometryReader { proxy in
            ScrollView([.horizontal, .vertical]) {
                VStack(alignment: .leading, spacing: 0) {
                    headerRow
                    ForEach(Array(displayRows.enumerated()), id: \.offset) { rowIdx, row in
                        rowView(row: row, rowIdx: rowIdx)
                    }
                }
                .frame(
                    minWidth: proxy.size.width,
                    minHeight: proxy.size.height,
                    alignment: .topLeading
                )
            }
        }
    }

    private var headerRow: some View {
        HStack(spacing: 0) {
            ForEach(Array(result.columns.enumerated()), id: \.offset) { idx, col in
                Button {
                    cycleSort(column: idx)
                } label: {
                    HStack(spacing: 4) {
                        Text(col.name)
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        sortIndicator(for: idx)
                    }
                    .frame(width: columnWidth(idx: idx), alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Click to sort by \(col.name) — click again to reverse, again to clear.")
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    @ViewBuilder
    private func sortIndicator(for idx: Int) -> some View {
        if sortColumn == idx {
            Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                .font(.caption2.bold())
                .foregroundStyle(Color.accentColor)
        }
    }

    private func rowView(row: [QueryValue], rowIdx: Int) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(row.enumerated()), id: \.offset) { idx, value in
                cell(value: value, idx: idx)
                    .frame(width: columnWidth(idx: idx), alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
            }
        }
        .background(
            rowIdx.isMultiple(of: 2)
                ? Color.clear
                : Color.secondary.opacity(0.06)
        )
    }

    /// Wraps a single result cell with a context menu offering Copy
    /// for any column, plus column-specific actions: `spot_id` →
    /// "Tune to spot" via RadioManager (resolves the spot via
    /// SpotAggregator); `callsign`-shaped columns → "Lookup on QRZ"
    /// (opens the default browser).
    @ViewBuilder
    private func cell(value: QueryValue, idx: Int) -> some View {
        let formatted = formatted(value: value, atIndex: idx)
        let columnName = idx < result.columns.count ? result.columns[idx].name : ""
        Text(formatted)
            .font(.system(.caption, design: .monospaced))
            .lineLimit(1)
            .truncationMode(.tail)
            .help(formatted)
            .contextMenu {
                Button("Copy") { copy(formatted) }
                if Self.isCallsignColumn(columnName), case let .text(call) = value {
                    Button("Lookup \(call) on QRZ") {
                        if let url = URL(string: "https://www.qrz.com/db/\(call)") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
                if columnName == "spot_id", case let .text(spotID) = value {
                    Button("Tune to spot") { tuneToSpot(id: spotID) }
                }
            }
    }

    private static func isCallsignColumn(_ name: String) -> Bool {
        let lowered = name.lowercased()
        return lowered == "callsign" || lowered.hasSuffix("_callsign")
    }

    /// Total ordering across `QueryValue` cases for the click-sort.
    /// Numeric values compare numerically (int↔double), text uses
    /// `localizedStandardCompare` so "Z2" sorts after "Z10", and mixed
    /// types fall back to formatted-string comparison so the column
    /// always has a consistent order even when SQL mixed numerics with
    /// strings via COALESCE / CASE.
    private static func compare(_ lhs: QueryValue, _ rhs: QueryValue) -> Int {
        switch (lhs, rhs) {
        case (.null, .null):
            return 0
        case let (.integer(left), .integer(right)):
            return left == right ? 0 : (left < right ? -1 : 1)
        case let (.double(left), .double(right)):
            return left == right ? 0 : (left < right ? -1 : 1)
        case let (.integer(left), .double(right)):
            return Double(left) == right ? 0 : (Double(left) < right ? -1 : 1)
        case let (.double(left), .integer(right)):
            return left == Double(right) ? 0 : (left < Double(right) ? -1 : 1)
        case let (.text(left), .text(right)):
            switch left.localizedStandardCompare(right) {
            case .orderedAscending: return -1
            case .orderedSame: return 0
            case .orderedDescending: return 1
            }
        case let (.blob(left), .blob(right)):
            return left.count == right.count ? 0 : (left.count < right.count ? -1 : 1)
        default:
            // Mixed cases (text vs numeric, blob vs anything): fall
            // back to a stable lexicographic ordering on the SQLite
            // value's string form.
            let leftDesc = describe(lhs)
            let rightDesc = describe(rhs)
            switch leftDesc.localizedStandardCompare(rightDesc) {
            case .orderedAscending: return -1
            case .orderedSame: return 0
            case .orderedDescending: return 1
            }
        }
    }

    private static func describe(_ value: QueryValue) -> String {
        switch value {
        case .null: ""
        case let .integer(int): String(int)
        case let .double(dbl): String(dbl)
        case let .text(str): str
        case let .blob(data): "<blob \(data.count)B>"
        }
    }

    private static func csvEscape(_ value: String) -> String {
        let needsQuote = value.contains(",")
            || value.contains("\"")
            || value.contains("\n")
            || value.contains("\r")
        guard needsQuote else {
            return value
        }
        let doubled = value.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(doubled)\""
    }

    /// Three-state cycle: unsorted → ascending → descending → unsorted.
    /// Clicking a different column always lands on ascending so the
    /// most common case is one click away.
    private func cycleSort(column idx: Int) {
        if sortColumn != idx {
            sortColumn = idx
            sortAscending = true
        } else if sortAscending {
            sortAscending = false
        } else {
            sortColumn = nil
            sortAscending = true
        }
    }

    /// Per-column width: max of header label and any cell content
    /// (formatted), clamped to a sane range. Cached per body update —
    /// the result set is immutable for a given run so recomputing
    /// inside a `body` is cheap relative to scroll work.
    private func columnWidth(idx: Int) -> CGFloat {
        guard idx < result.columns.count else {
            return 80
        }
        let header = result.columns[idx].name
        var maxChars = header.count
        // Sample at most 200 rows so wide result sets don't pay an
        // O(n) cost on every scroll tick.
        for row in result.rows.prefix(200) where idx < row.count {
            let formatted = QueryColumnFormatters.format(
                value: row[idx],
                columnName: header,
                hint: columnHints?[header]
            )
            maxChars = max(maxChars, formatted.count)
        }
        // ~7.5 px per monospaced char @ caption + 20 px padding,
        // clamped to [80, 360].
        let width = CGFloat(maxChars) * 7.5 + 20
        return min(max(width, 80), 360)
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// Build an RFC 4180 CSV from the entire result set (not just the
    /// visible row cap) and put it on the pasteboard.
    private func copyAsCSV() {
        var lines: [String] = []
        lines.reserveCapacity(result.rows.count + 1)
        lines.append(result.columns.map(\.name).map(Self.csvEscape).joined(separator: ","))
        for row in result.rows {
            let cells: [String] = row.enumerated().map { idx, value in
                Self.csvEscape(formatted(value: value, atIndex: idx))
            }
            lines.append(cells.joined(separator: ","))
        }
        let csv = lines.joined(separator: "\r\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(csv, forType: .string)
        didCopyRecently = true
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await MainActor.run { didCopyRecently = false }
        }
    }

    /// Resolve the spot_id back to an EnrichedSpot via the in-memory
    /// SpotAggregator and tune the radio. We can't call the spot's
    /// frequency directly from SQL — the saved query may not include
    /// it — so the aggregator stays the source of truth for current
    /// frequency/mode.
    private func tuneToSpot(id: String) {
        guard let spot = spotAggregator.spots.first(where: { $0.spot.id == id }) else {
            return
        }
        Task {
            await radioManager.tuneToSpot(
                frequencyMHz: spot.spot.frequencyMHz,
                mode: spot.spot.mode,
                autoXITEnabled: autoXITEnabled,
                autoXITOffsetHz: autoXITOffsetHz
            )
        }
    }

    private func formatted(value: QueryValue, atIndex idx: Int) -> String {
        guard idx < result.columns.count else {
            return "?"
        }
        let name = result.columns[idx].name
        let hint = columnHints?[name]
        return QueryColumnFormatters.format(value: value, columnName: name, hint: hint)
    }
}
