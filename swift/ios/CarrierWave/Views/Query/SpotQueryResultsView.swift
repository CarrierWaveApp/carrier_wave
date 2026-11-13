import CarrierWaveCwFfi
import SwiftUI

// MARK: - SpotQueryResultsView

/// Result block for the spot SQL editor. The phone screen isn't wide
/// enough for a real grid, so rows render as compact label/value stacks
/// (same presentation the old QueryRunnerView used). Truncated results
/// get a "Show More" button that doubles the row cap and re-runs.
struct SpotQueryResultsView: View {
    // MARK: Internal

    let result: FfiQueryResultSet
    let isProfile: Bool
    let isRunning: Bool
    let onShowMore: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            Divider()
            if result.rows.isEmpty {
                Text("No rows.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                rowList
            }
            if result.truncated {
                showMoreButton
            }
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Private

    private var header: some View {
        HStack {
            Text(isProfile ? "Query Plan" : "Result")
                .font(.subheadline.weight(.semibold))
            Spacer()
            Text(
                "\(result.rows.count) row\(result.rows.count == 1 ? "" : "s")\(result.truncated ? " (truncated)" : "")"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var rowList: some View {
        // The engine already caps rows at the editor's row limit, and the
        // enclosing ScrollView + LazyVStack keeps per-frame layout bounded —
        // render everything so Show More actually shows more.
        LazyVStack(alignment: .leading, spacing: 6) {
            ForEach(Array(result.rows.enumerated()), id: \.offset) { _, row in
                rowCell(row)
            }
        }
    }

    private var showMoreButton: some View {
        Button {
            onShowMore()
        } label: {
            Text("Show More")
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .disabled(isRunning)
    }

    private func rowCell(_ row: FfiQueryRow) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(row.values.enumerated()), id: \.offset) { idx, value in
                if idx < result.columns.count {
                    HStack(alignment: .firstTextBaseline) {
                        Text(result.columns[idx])
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 90, alignment: .leading)
                        Text(value ?? "—")
                            .font(.system(.caption, design: .monospaced))
                            .lineLimit(1)
                    }
                }
            }
            Divider()
        }
    }
}

// MARK: - SpotQuerySaveSheet

/// Name + description entry for saving the editor's SQL as a new
/// `.cwquery` file.
struct SpotQuerySaveSheet: View {
    // MARK: Internal

    let initialName: String
    let initialDescription: String
    let onSave: (String, String) -> Void

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                TextField("Description", text: $description, axis: .vertical)
                    .lineLimit(2 ... 4)
            }
            .navigationTitle("Save Query")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(
                            name.trimmingCharacters(in: .whitespacesAndNewlines),
                            description.trimmingCharacters(in: .whitespacesAndNewlines)
                        )
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                if name.isEmpty {
                    name = initialName
                    description = initialDescription
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var description = ""
}
