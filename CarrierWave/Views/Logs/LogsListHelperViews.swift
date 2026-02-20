import CarrierWaveCore
import SwiftData
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

// MARK: - QSORow

struct QSORow: View {
    // MARK: Internal

    let qso: QSO
    let serviceConfig: ServiceConfiguration

    var body: some View {
        Group {
            if isLandscape {
                landscapeRow
            } else {
                portraitRow
            }
        }
        .padding(.vertical, isRegularWidth ? 8 : 4)
        .task {
            if let park = qso.parkReference {
                parkName = await POTAParksCache.shared.name(for: park)
            }
            callsignInfo = await CallsignNotesCache.shared.info(for: qso.callsign)
            totalContactCount = fetchTotalContactCount(for: qso.callsign)
        }
    }

    // MARK: Private

    private static let utcFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d HH:mm"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.modelContext) private var modelContext

    @State private var parkName: String?
    @State private var callsignInfo: CallsignInfo?
    @State private var totalContactCount: Int = 0

    private var isRegularWidth: Bool {
        horizontalSizeClass == .regular
    }

    private var isLandscape: Bool {
        verticalSizeClass == .compact
    }

    /// Display name from callsign notes (prefers nickname), fallback to QSO stored name
    private var displayName: String? {
        callsignInfo?.displayName ?? qso.name?.capitalized
    }

    private var formattedTimestamp: String {
        Self.utcFormatter.string(from: qso.timestamp) + "Z"
    }

    /// Only show pills for configured services or services with actual data
    private var sortedPresence: [ServicePresence] {
        qso.servicePresence
            .filter { presence in
                let configured = serviceConfig.isConfigured(presence.serviceType)
                return configured || presence.isPresent || presence.isSubmitted
            }
            .sorted { $0.serviceType.rawValue < $1.serviceType.rawValue }
    }

    /// Compact single-line row for landscape mode
    private var landscapeRow: some View {
        HStack(spacing: 8) {
            Text(qso.callsign)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)

            if let freq = qso.frequency {
                Text(FrequencyFormatter.format(freq))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(qso.band)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(qso.mode)
                .font(.caption)
                .foregroundStyle(.secondary)

            if let rstSent = qso.rstSent {
                Text("S:\(rstSent)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let grid = qso.theirGrid {
                Text(grid)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let park = qso.parkReference {
                Text(park)
                    .font(.caption)
                    .foregroundStyle(.green)
            }

            Spacer()

            Text(formattedTimestamp)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// Full multi-line row for portrait mode
    private var portraitRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(qso.callsign)
                    .font(.headline)

                if let name = displayName {
                    Text(name)
                        .font(isRegularWidth ? .body : .subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if let emoji = callsignInfo?.combinedEmoji {
                    Text(emoji)
                        .font(.caption)
                }

                if totalContactCount > 1 {
                    ContactCountBadge(count: totalContactCount)
                }

                Spacer()

                Text(formattedTimestamp)
                    .font(isRegularWidth ? .subheadline : .caption)
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
            .font(isRegularWidth ? .subheadline : .caption)
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
    }

    /// Count all-time QSOs with a callsign (excludes hidden and metadata modes)
    private func fetchTotalContactCount(for callsign: String) -> Int {
        let upper = callsign.uppercased()
        return
            (try? modelContext.fetchCount(
                FetchDescriptor<QSO>(
                    predicate: #Predicate<QSO> { qso in
                        qso.callsign == upper
                            && !qso.isHidden
                            && qso.mode != "WEATHER"
                            && qso.mode != "SOLAR"
                            && qso.mode != "NOTE"
                    }
                )
            )) ?? 0
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
                .lineLimit(1)
        }
        .font(isRegularWidth ? .caption : .caption2)
        .fixedSize()
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(backgroundColor.opacity(0.2))
        .foregroundStyle(backgroundColor)
        .clipShape(Capsule())
    }

    // MARK: Private

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var isRegularWidth: Bool {
        horizontalSizeClass == .regular
    }

    private var isBidirectional: Bool {
        switch presence.serviceType {
        case .qrz,
             .pota,
             .hamrs,
             .clublog:
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
