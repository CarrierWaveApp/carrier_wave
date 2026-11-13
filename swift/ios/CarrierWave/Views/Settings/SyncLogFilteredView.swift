import CarrierWaveCore
import CarrierWaveData
import SwiftUI

// MARK: - ProblemCounts

struct ProblemCounts {
    let errors: Int
    let warnings: Int
    let actions: Int
}

// MARK: - LogLevelFilter

enum LogLevelFilter: String, CaseIterable {
    case all = "All"
    case important = "Important"
    case errors = "Errors"

    // MARK: Internal

    func matches(_ level: SyncDebugLog.LogEntry.Level) -> Bool {
        switch self {
        case .all: true
        case .important:
            level == .error || level == .warning || level == .actionRequired
        case .errors:
            level == .error
        }
    }
}

// MARK: - SyncLogFilteredView

/// Filtered sync log with problems banner, level/service filters, and
/// improved visual hierarchy. Defaults to "Important" when problems exist.
struct SyncLogFilteredView: View {
    // MARK: Internal

    var debugLog: SyncDebugLog

    var body: some View {
        VStack(spacing: 0) {
            filterBar
            Divider()

            if filteredEntries.isEmpty {
                emptyState
            } else {
                List {
                    if hasProblems, levelFilter != .all {
                        problemsBanner
                    }
                    ForEach(filteredEntries) { entry in
                        LogEntryRow(entry: entry)
                    }
                }
                .listStyle(.plain)
            }
        }
        .onAppear {
            if hasProblems {
                levelFilter = .important
            }
        }
    }

    // MARK: Private

    // MARK: - State

    @State private var levelFilter: LogLevelFilter = .all
    @State private var selectedServices: Set<ServiceType> = []
    @State private var showGeneralEntries = true

    // MARK: - Computed

    private var hasProblems: Bool {
        debugLog.logEntries.contains {
            $0.level == .error || $0.level == .warning
                || $0.level == .actionRequired
        }
    }

    private var problemCounts: ProblemCounts {
        var errs = 0
        var warns = 0
        var acts = 0
        for entry in serviceFilteredEntries {
            switch entry.level {
            case .error: errs += 1
            case .warning: warns += 1
            case .actionRequired: acts += 1
            case .info,
                 .debug: break
            }
        }
        return ProblemCounts(errors: errs, warnings: warns, actions: acts)
    }

    /// Services that have at least one log entry.
    private var activeServices: [ServiceType] {
        var seen = Set<ServiceType>()
        for entry in debugLog.logEntries {
            if let svc = entry.service {
                seen.insert(svc)
            }
        }
        return ServiceType.allCases.filter { seen.contains($0) }
    }

    /// Whether any service/general filter chip is active.
    private var hasServiceFilter: Bool {
        !selectedServices.isEmpty || !showGeneralEntries
    }

    /// Entries filtered by service only (for problem counts).
    private var serviceFilteredEntries: [SyncDebugLog.LogEntry] {
        guard hasServiceFilter else {
            return debugLog.logEntries
        }
        return debugLog.logEntries.filter { entry in
            if let svc = entry.service {
                return selectedServices.contains(svc)
            }
            return showGeneralEntries
        }
    }

    /// Entries filtered by both service and level.
    private var filteredEntries: [SyncDebugLog.LogEntry] {
        serviceFilteredEntries.filter { levelFilter.matches($0.level) }
    }

    /// Whether there are entries with nil service (general/iCloud).
    private var hasGeneralEntries: Bool {
        debugLog.logEntries.contains { $0.service == nil }
    }
}

// MARK: - Filter Bar

extension SyncLogFilteredView {
    private var filterBar: some View {
        VStack(spacing: 8) {
            // Level filter
            Picker("Level", selection: $levelFilter) {
                ForEach(LogLevelFilter.allCases, id: \.self) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.segmented)

            // Service chips
            if !activeServices.isEmpty || hasGeneralEntries {
                serviceChips
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.systemGroupedBackground))
    }

    private var serviceChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                allServicesChip
                if hasGeneralEntries {
                    serviceChip(label: "General", isSelected: showGeneralEntries) {
                        showGeneralEntries.toggle()
                        if !showGeneralEntries, selectedServices.isEmpty {
                            // Select all specific services when deselecting general
                            selectedServices = Set(activeServices)
                        }
                    }
                }
                ForEach(activeServices, id: \.self) { service in
                    let count = entryCount(for: service)
                    serviceChip(
                        label: "\(service.displayName) (\(count))",
                        isSelected: selectedServices.contains(service)
                    ) {
                        toggleService(service)
                    }
                }
            }
        }
    }

    private var allServicesChip: some View {
        serviceChip(
            label: "All",
            isSelected: !hasServiceFilter
        ) {
            selectedServices = []
            showGeneralEntries = true
        }
    }

    private func serviceChip(
        label: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(label)
                .font(.caption)
                .fontWeight(isSelected ? .semibold : .regular)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(isSelected ? Color.accentColor : Color(.systemGray5))
                .foregroundStyle(isSelected ? .white : .primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func toggleService(_ service: ServiceType) {
        if selectedServices.contains(service) {
            selectedServices.remove(service)
            if selectedServices.isEmpty, showGeneralEntries {
                // Back to "all" state
                showGeneralEntries = true
            }
        } else {
            if !hasServiceFilter {
                // First specific selection: deselect "all" implicitly
                selectedServices = [service]
                showGeneralEntries = false
            } else {
                selectedServices.insert(service)
            }
        }
    }

    private func entryCount(for service: ServiceType) -> Int {
        debugLog.logEntries.count { $0.service == service }
    }
}

// MARK: - Problems Banner & Empty State

extension SyncLogFilteredView {
    private var problemsBanner: some View {
        let counts = problemCounts
        return HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 2) {
                Text("Problems Found")
                    .font(.subheadline.weight(.semibold))
                problemCountsText(counts)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Show All") {
                levelFilter = .all
            }
            .font(.caption)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func problemCountsText(
        _ counts: ProblemCounts
    ) -> some View {
        let parts = problemCountParts(counts)
        if parts.isEmpty {
            Text("No problems")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            HStack(spacing: 4) {
                ForEach(Array(parts.enumerated()), id: \.offset) { idx, part in
                    if idx > 0 {
                        Text(",")
                            .foregroundStyle(.secondary)
                    }
                    Text(part.label)
                        .foregroundStyle(part.color)
                }
            }
            .font(.caption)
        }
    }

    private func problemCountParts(
        _ counts: ProblemCounts
    ) -> [(label: String, color: Color)] {
        var parts: [(label: String, color: Color)] = []
        if counts.errors > 0 {
            let suffix = counts.errors == 1 ? "" : "s"
            parts.append(("\(counts.errors) error\(suffix)", .red))
        }
        if counts.warnings > 0 {
            let suffix = counts.warnings == 1 ? "" : "s"
            parts.append(("\(counts.warnings) warning\(suffix)", .orange))
        }
        if counts.actions > 0 {
            let suffix = counts.actions == 1 ? "" : "s"
            parts.append(("\(counts.actions) action\(suffix)", .purple))
        }
        return parts
    }

    private var emptyState: some View {
        ContentUnavailableView(
            hasServiceFilter || levelFilter != .all
                ? "No Matching Entries"
                : "No Log Entries",
            systemImage: hasServiceFilter || levelFilter != .all
                ? "line.3.horizontal.decrease.circle"
                : "text.page",
            description: Text(
                hasServiceFilter || levelFilter != .all
                    ? "Try changing your filters to see more entries."
                    : "Sync operations will appear here."
            )
        )
    }
}

// MARK: - SyncLogFormatter

enum SyncLogFormatter {
    static func format(entries: [SyncDebugLog.LogEntry]) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        dateFormatter.timeZone = TimeZone(identifier: "UTC")

        var lines: [String] = [
            "Carrier Wave Sync Debug Log",
            "Exported: \(dateFormatter.string(from: Date())) UTC",
            "",
        ]

        for entry in entries.reversed() {
            let ts = dateFormatter.string(from: entry.timestamp)
            let svc = entry.service.map { "[\($0.displayName)] " } ?? ""
            lines.append(
                "[\(entry.level.rawValue)] \(ts) \(svc)\(entry.message)"
            )
        }

        return lines.joined(separator: "\n")
    }
}
