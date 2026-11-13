import CarrierWaveData
import SwiftUI

// MARK: - QueryWarningBanner

struct QueryWarningBanner: View {
    // MARK: Internal

    let analysis: QueryAnalysis
    let onProceed: () -> Void
    let onAddFilter: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(analysis.warnings.prefix(2)) { warning in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: warning.severity.icon)
                        .foregroundStyle(warningColor(warning.severity))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(warning.message)
                            .font(.caption)

                        if let suggestion = warning.suggestion {
                            Text(suggestion)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if analysis.requiresConfirmation {
                HStack {
                    Button("Search Anyway") {
                        onProceed()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    if let suggestion = analysis.warnings.first?.suggestion,
                       suggestion.contains("after:")
                    {
                        Button("Add Date Filter") {
                            onAddFilter("after:30d")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.1))
    }

    // MARK: Private

    private func warningColor(_ severity: QueryWarning.Severity) -> Color {
        switch severity {
        case .hint: .blue
        case .medium: .orange
        case .high: .red
        }
    }
}

// MARK: - QueryHelpSheet

struct QueryHelpSheet: View {
    // MARK: Internal

    var body: some View {
        NavigationStack {
            List {
                Section("Basic Search") {
                    helpRow("W1AW", "Callsigns starting with W1AW")
                    helpRow("call:W1AW", "Exact callsign match")
                    helpRow("W1*", "Wildcard: callsigns, parks, SOTA starting with W1")
                }

                Section("Field Filters") {
                    helpRow("band:20m", "20 meter contacts")
                    helpRow("mode:CW", "CW mode contacts")
                    helpRow("state:CA", "California stations")
                    helpRow("park:K-*", "Any US POTA park")
                    helpRow("grid:FN31", "Specific grid square")
                }

                Section("Date Filters") {
                    helpRow("date:today", "Today's contacts")
                    helpRow("after:7d", "Last 7 days")
                    helpRow("after:30d", "Last 30 days")
                    helpRow("date:2024-01", "January 2024")
                    helpRow("before:2024-06-01", "Before June 1, 2024")
                }

                Section("Status Filters") {
                    helpRow("confirmed:lotw", "LoTW confirmed")
                    helpRow("confirmed:qrz", "QRZ QSL confirmed")
                    helpRow("synced:pota", "Uploaded to POTA")
                    helpRow("pending:yes", "Needs upload")
                }

                Section("Combining Filters") {
                    helpRow("W1AW 20m", "W1AW on 20m (AND)")
                    helpRow("W1AW | K1ABC", "W1AW or K1ABC (OR)")
                    helpRow("-mode:FT8", "Exclude FT8")
                    helpRow("band:20m mode:CW after:30d", "20m CW in last 30 days")
                }

                Section("Numeric Filters") {
                    helpRow("freq:14.074", "Specific frequency")
                    helpRow("freq:>14.0", "Above 14 MHz")
                    helpRow("power:>100", "Over 100W")
                }
            }
            .navigationTitle("Search Help")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss

    private func helpRow(_ query: String, _ description: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(query)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.primary)
            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
