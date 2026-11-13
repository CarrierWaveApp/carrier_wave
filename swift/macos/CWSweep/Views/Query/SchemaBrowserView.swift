import SwiftUI

// MARK: - SchemaBrowserView

/// Right-side workbench pane listing every queryable table with its
/// columns, types, and hand-curated descriptions. Each table is a
/// disclosure group; expanding shows the column rows. Clicking a
/// table or column inserts a starter snippet into the editor so the
/// user can build queries by selecting fields rather than memorizing
/// column names.
///
/// Uses `List` rather than `ScrollView + LazyVStack` because SwiftUI's
/// `HSplitView` doesn't reliably propagate height into a nested
/// `ScrollView`, which left scroll-wheel events bubbling out to the
/// surrounding window. `List` wraps `NSTableView` and handles the
/// scroll mechanics correctly inside split-view panes.
struct SchemaBrowserView: View {
    // MARK: Internal

    @Bindable var model: QueryWorkbenchModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            List {
                ForEach(SchemaCatalog.tables) { table in
                    TableSection(
                        table: table,
                        expanded: expandedTables.contains(table.id),
                        onToggle: { toggle(table) },
                        onInsert: { insertIntoEditor($0) }
                    )
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                }
            }
            .listStyle(.sidebar)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 260, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: Private

    @State private var expandedTables: Set<String> = []

    private var header: some View {
        HStack {
            Text("Schema")
                .font(.headline)
            Spacer()
            Text("\(SchemaCatalog.tables.count) tables")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(8)
    }

    private func toggle(_ table: SchemaCatalog.Table) {
        if expandedTables.contains(table.id) {
            expandedTables.remove(table.id)
        } else {
            expandedTables.insert(table.id)
        }
    }

    /// Append the snippet to the editor at a sane spot — usually the
    /// end. We avoid fancy cursor-position logic because the SQL
    /// editor doesn't expose a stable selection API to SwiftUI.
    private func insertIntoEditor(_ snippet: String) {
        let trimmed = model.sql.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            model.sql = snippet
        } else {
            model.sql = "\(model.sql)\n\(snippet)"
        }
    }
}

// MARK: - TableSection

/// One row per table — disclosure header lists the qualified name and
/// column count, expanded body shows the description plus one row per
/// column with type and description.
private struct TableSection: View {
    // MARK: Internal

    let table: SchemaCatalog.Table
    let expanded: Bool
    let onToggle: () -> Void
    let onInsert: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            tableHeader
            if expanded {
                Text(table.description)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)

                ForEach(table.columns) { column in
                    columnRow(column: column)
                }
            }
        }
    }

    // MARK: Private

    private var tableHeader: some View {
        HStack(spacing: 4) {
            Button {
                onToggle()
            } label: {
                Image(systemName: expanded ? "chevron.down" : "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(width: 14)
            }
            .buttonStyle(.plain)

            Text(table.qualified)
                .font(.system(.caption, design: .monospaced))
                .fontWeight(.semibold)
                .help(table.description)

            Spacer()

            Text("\(table.columns.count)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)

            Button {
                onInsert("SELECT * FROM \(table.qualified) LIMIT 10;")
            } label: {
                Image(systemName: "arrow.right.square")
                    .font(.caption2)
            }
            .buttonStyle(.plain)
            .help("Insert SELECT * FROM \(table.qualified) into the editor")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture { onToggle() }
    }

    private func columnRow(column: SchemaCatalog.Column) -> some View {
        Button {
            onInsert(column.name)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if column.isPrimaryKey {
                    Image(systemName: "key.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(.orange)
                        .frame(width: 14)
                } else {
                    Color.clear.frame(width: 14, height: 1)
                }
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(column.name)
                            .font(.system(.caption, design: .monospaced))
                            .fontWeight(.medium)
                        Text(column.type)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                        if !column.isNullable {
                            Text("NOT NULL")
                                .font(.system(size: 8, weight: .medium))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    Text(column.description)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            .padding(.leading, 10)
            .padding(.trailing, 8)
            .padding(.vertical, 3)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .help("Click to insert `\(column.name)` into the editor")
    }
}
