import CarrierWaveCore
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
                    helpRow("W1AW", "Find contacts with W1AW")
                    helpRow("K-1234", "Find contacts at park K-1234")
                    helpRow("W1*", "Callsigns starting with W1")
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

// MARK: - QSORow

struct QSORow: View {
    // MARK: Internal

    let qso: QSO
    let serviceConfig: ServiceConfiguration

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(qso.callsign)
                    .font(.headline)

                Spacer()

                Text(formattedTimestamp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                if let freq = qso.frequency {
                    Label(FrequencyFormatter.format(freq), systemImage: "waveform")
                }
                Label(qso.band, systemImage: "antenna.radiowaves.left.and.right")
                Label(qso.mode, systemImage: "dot.radiowaves.left.and.right")

                if let park = qso.parkReference {
                    if let name = parkName {
                        Label("\(park) - \(name)", systemImage: "tree")
                            .foregroundStyle(.green)
                            .lineLimit(1)
                    } else {
                        Label(park, systemImage: "tree")
                            .foregroundStyle(.green)
                    }
                }

                Spacer()
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                ForEach(sortedPresence) { presence in
                    ServicePresenceBadge(
                        presence: presence,
                        qso: qso,
                        isServiceConfigured: serviceConfig.isConfigured(presence.serviceType)
                    )
                }
            }
        }
        .padding(.vertical, 4)
        .task {
            if let park = qso.parkReference {
                parkName = await POTAParksCache.shared.name(for: park)
            }
        }
    }

    // MARK: Private

    private static let utcFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d HH:mm"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    @State private var parkName: String?

    private var formattedTimestamp: String {
        Self.utcFormatter.string(from: qso.timestamp) + "Z"
    }

    private var sortedPresence: [ServicePresence] {
        qso.servicePresence.sorted { $0.serviceType.rawValue < $1.serviceType.rawValue }
    }
}

// MARK: - ServicePresenceBadge

struct ServicePresenceBadge: View {
    // MARK: Internal

    let presence: ServicePresence
    let qso: QSO
    let isServiceConfigured: Bool

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: iconName)
            Text(presence.serviceType.displayName)
        }
        .font(.caption2)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(backgroundColor.opacity(0.2))
        .foregroundStyle(backgroundColor)
        .clipShape(Capsule())
    }

    // MARK: Private

    private var isBidirectional: Bool {
        switch presence.serviceType {
        case .qrz,
             .pota,
             .hamrs:
            true
        case .lofi,
             .lotw:
            false
        }
    }

    private var isConfirmed: Bool {
        switch presence.serviceType {
        case .lotw:
            qso.lotwConfirmed
        case .qrz:
            qso.qrzConfirmed
        default:
            false
        }
    }

    private var iconName: String {
        if presence.isPresent, isConfirmed {
            return "star.fill"
        }

        if isBidirectional {
            if presence.isPresent, !presence.needsUpload {
                return "checkmark"
            } else if presence.isPresent, presence.needsUpload {
                return "arrow.down"
            }
        }

        if presence.isPresent {
            return "checkmark"
        }

        if presence.isSubmitted {
            return "clock.arrow.circlepath"
        }

        return "clock"
    }

    private var backgroundColor: Color {
        if presence.isPresent {
            .green
        } else if presence.isSubmitted {
            .blue
        } else if isServiceConfigured {
            .orange
        } else {
            .gray
        }
    }
}
