import CarrierWaveData
import SwiftUI

struct QueryEditorView: View {
    // MARK: Internal

    @Binding var sql: String

    let error: SQLQueryError?
    var hasUnsavedChanges: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            SQLTextEditor(text: $sql)
                .frame(minHeight: 120)
                .padding(8)
                .background(Color(nsColor: .textBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(borderColor, lineWidth: 1)
                )

            if let error {
                errorLine(error)
            }
        }
    }

    // MARK: Private

    /// Red on a SQLite error, orange when the editor has unsaved
    /// changes against the selected saved query, otherwise the
    /// neutral hairline. Error trumps dirty.
    private var borderColor: Color {
        if error != nil {
            return .red
        }
        if hasUnsavedChanges {
            return .orange
        }
        return Color.secondary.opacity(0.3)
    }

    /// Show the SQLite error along with `Line N · Col M` when an error
    /// offset is available. SQLite's offset (since 3.38) points to the
    /// byte that triggered the parse/bind failure in the original SQL.
    /// Translating to line + column lets the user jump back without
    /// counting characters.
    private func errorLine(_ error: SQLQueryError) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if let label = positionLabel(for: error) {
                Text(label)
                    .font(.caption.bold().monospaced())
                    .foregroundStyle(.red)
            }
            Text(error.message)
                .font(.caption)
                .foregroundStyle(.red)
                .lineLimit(2)
        }
    }

    private func positionLabel(for error: SQLQueryError) -> String? {
        guard let offset = error.errorOffset else {
            return nil
        }
        let prefix = sql.prefix(min(offset, sql.count))
        let line = prefix.reduce(into: 1) { acc, char in
            if char == "\n" {
                acc += 1
            }
        }
        let lastNewline = prefix.lastIndex(of: "\n")
        let col: Int = if let lastNewline {
            prefix.distance(from: prefix.index(after: lastNewline), to: prefix.endIndex) + 1
        } else {
            prefix.count + 1
        }
        return "Line \(line) · Col \(col)"
    }
}
