import SwiftUI

// MARK: - SpotSchemaHelpView

/// Static schema reference sheet for the spot SQL editor — a port of CW
/// Sweep's `SchemaBrowserView` copy adapted to a phone sheet. Each table
/// is a disclosure group with column rows; tapping a table's insert
/// button drops a starter `SELECT` into the editor.
struct SpotSchemaHelpView: View {
    // MARK: Internal

    /// Called with a SQL snippet the user chose to insert.
    let onInsert: (String) -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(
                        "Queries run read-only against the spot engine's in-memory "
                            + "database. Spot-filter queries must include `spot_id` in "
                            + "their result set."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                ForEach(SpotSchemaCatalog.tables) { table in
                    tableSection(table)
                }
                functionsSection
            }
            .navigationTitle("Schema")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDragIndicator(.visible)
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss

    private var functionsSection: some View {
        Section("Helper Functions") {
            functionRow(
                signature: "cw_user_grid_distance_km(grid)",
                description: "Great-circle distance in km from your configured grid to a Maidenhead grid."
            )
            functionRow(
                signature: "cw_user_grid_bearing_deg(grid)",
                description: "Bearing in degrees from your configured grid to a Maidenhead grid."
            )
            functionRow(
                signature: "cw_user_distance_km(lat, lon)",
                description: "Great-circle distance in km from your configured grid to a lat/lon."
            )
        }
    }

    private func functionRow(signature: String, description: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(signature)
                .font(.system(.caption, design: .monospaced))
                .fontWeight(.medium)
            Text(description)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func tableSection(_ table: SpotSchemaCatalog.Table) -> some View {
        Section {
            DisclosureGroup {
                Text(table.description)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                ForEach(table.columns) { column in
                    columnRow(column)
                }
            } label: {
                HStack {
                    Text(table.qualified)
                        .font(.system(.caption, design: .monospaced))
                        .fontWeight(.semibold)
                    Spacer()
                    Text("\(table.columns.count)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                    Button {
                        onInsert("SELECT * FROM \(table.qualified) LIMIT 10;")
                    } label: {
                        Image(systemName: "arrow.right.square")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Insert SELECT for \(table.qualified)")
                }
            }
        }
    }

    private func columnRow(_ column: SpotSchemaCatalog.Column) -> some View {
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
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
