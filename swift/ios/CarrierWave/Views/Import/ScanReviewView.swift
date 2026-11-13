import CarrierWaveCore
import CarrierWaveData
import SwiftUI

// MARK: - ScanReviewView

/// Review table showing OCR-parsed QSO rows with confidence indicators.
/// Users can edit, select/deselect, and import rows.
struct ScanReviewView: View {
    // MARK: Internal

    @Binding var rows: [ScannedQSORow]

    let images: [UIImage]
    let myCallsign: String
    let rstOrder: RSTOrder
    let onImport: ([ScannedQSORow]) -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(summaryText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if !images.isEmpty {
                    Section {
                        DisclosureGroup("Scanned Pages", isExpanded: $showPages) {
                            ScannedPagePreview(images: images)
                        }
                    }
                }

                ForEach($rows) { $row in
                    HStack(spacing: 12) {
                        Button {
                            editingRow = row
                        } label: {
                            ScanReviewRowContent(row: row)
                        }
                        .buttonStyle(.plain)

                        Toggle("", isOn: $row.isSelected)
                            .labelsHidden()
                    }
                }
            }
            .navigationTitle("Review Scanned Log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import \(selectedCount)") {
                        onImport(selectedRows)
                    }
                    .disabled(selectedCount == 0)
                }
                ToolbarItem(placement: .bottomBar) {
                    HStack {
                        Button("Select All") {
                            for index in rows.indices {
                                rows[index].isSelected = true
                            }
                        }
                        Spacer()
                        Button("Deselect All") {
                            for index in rows.indices {
                                rows[index].isSelected = false
                            }
                        }
                    }
                }
            }
            .sheet(item: $editingRow) { row in
                ScanRowEditSheet(row: row, rstOrder: rstOrder) { updated in
                    if let idx = rows.firstIndex(where: { $0.id == updated.id }) {
                        rows[idx] = updated
                    }
                }
            }
        }
    }

    // MARK: Private

    @State private var editingRow: ScannedQSORow?
    @State private var showPages = false

    private var selectedRows: [ScannedQSORow] {
        rows.filter(\.isSelected)
    }

    private var selectedCount: Int {
        rows.filter(\.isSelected).count
    }

    private var summaryText: String {
        let total = rows.count
        let parsed = rows.filter { $0.parseResult != nil }.count
        let failed = total - parsed
        var parts = ["\(total) rows detected", "\(parsed) parsed"]
        if failed > 0 {
            parts.append("\(failed) failed")
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - ScanReviewRowContent

/// Display content for a single row (no toggle — that's in the parent).
struct ScanReviewRowContent: View {
    // MARK: Internal

    let row: ScannedQSORow

    var body: some View {
        HStack(spacing: 12) {
            confidenceIndicator
            VStack(alignment: .leading, spacing: 4) {
                if let result = row.parseResult {
                    parsedContent(result)
                } else {
                    failedContent
                }
            }
            Spacer()
        }
        .contentShape(Rectangle())
    }

    // MARK: Private

    private static let utcFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d HH:mm"
        fmt.timeZone = TimeZone(identifier: "UTC")
        return fmt
    }()

    private var confidenceColor: Color {
        switch row.confidence {
        case .high: .green
        case .low: .yellow
        case .failed: .red
        }
    }

    private var confidenceIndicator: some View {
        Circle()
            .fill(confidenceColor)
            .frame(width: 10, height: 10)
    }

    @ViewBuilder
    private var failedContent: some View {
        Text(row.rawText)
            .font(.caption)
            .foregroundStyle(.secondary)

        Text("Could not parse — no valid callsign found")
            .font(.caption2)
            .foregroundStyle(.red)
    }

    @ViewBuilder
    private func parsedContent(_ result: QuickEntryResult) -> some View {
        HStack(spacing: 8) {
            Text(result.callsign.isEmpty ? "No callsign — tap to edit" : result.callsign)
                .font(.body.monospaced())
                .fontWeight(.semibold)
                .foregroundStyle(result.callsign.isEmpty ? .orange : .primary)

            if let freq = result.frequency {
                Text(String(format: "%.3f", freq))
                    .font(.caption)
                    .foregroundStyle(.teal)
            }

            if let mode = result.mode {
                Text(mode)
                    .font(.caption)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(.blue.opacity(0.15), in: .capsule)
            }
        }

        HStack(spacing: 8) {
            if let timestamp = row.timestamp {
                Text(utcFormatted(timestamp))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if let rstSent = result.rstSent {
                Text("S:\(rstSent)")
                    .font(.caption2)
                    .foregroundStyle(.blue)
            }

            if let rstReceived = result.rstReceived {
                Text("R:\(rstReceived)")
                    .font(.caption2)
                    .foregroundStyle(.blue)
            }

            if let notes = result.notes, !notes.isEmpty {
                Text(notes)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private func utcFormatted(_ date: Date) -> String {
        Self.utcFormatter.string(from: date) + "Z"
    }
}
