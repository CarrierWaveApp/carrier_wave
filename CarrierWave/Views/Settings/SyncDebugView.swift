import CarrierWaveCore
import SwiftData
import SwiftUI

// MARK: - SyncDebugView

struct SyncDebugView: View {
    // MARK: Internal

    @ObservedObject var debugLog = SyncDebugLog.shared

    var body: some View {
        VStack(spacing: 0) {
            Picker("View", selection: $selectedTab) {
                Text("Raw QSOs").tag(0)
                Text("Sync Log").tag(1)
                Text("Stats").tag(2)
            }
            .pickerStyle(.segmented)
            .padding()

            if selectedTab == 0 {
                rawQSOsView
            } else if selectedTab == 1 {
                syncLogView
            } else {
                serviceStatsView
            }
        }
        .navigationTitle("Sync Debug")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Clear All") {
                        debugLog.clearAll()
                    }
                    Button("Clear Logs Only") {
                        debugLog.clearLogs()
                    }
                } label: {
                    Image(systemName: "trash")
                }
            }
        }
    }

    // MARK: Private

    @Environment(\.modelContext) private var modelContext
    @State private var selectedTab = 0
    @State private var serviceCounts: [ServiceType: Int] = [:]

    private var rawQSOsView: some View {
        List {
            ForEach(ServiceType.allCases, id: \.self) { service in
                Section {
                    if let qsos = debugLog.rawQSOs[service], !qsos.isEmpty {
                        ForEach(qsos) { qso in
                            RawQSORow(qso: qso)
                        }
                    } else {
                        Text("No QSOs captured")
                            .foregroundStyle(.secondary)
                            .italic()
                    }
                } header: {
                    HStack {
                        Text(service.displayName)
                        Spacer()
                        if let count = debugLog.rawQSOs[service]?.count, count > 0 {
                            Text("\(count) captured")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private var syncLogView: some View {
        List {
            if debugLog.logEntries.isEmpty {
                Text("No log entries")
                    .foregroundStyle(.secondary)
                    .italic()
            } else {
                ForEach(debugLog.logEntries) { entry in
                    LogEntryRow(entry: entry)
                }
            }
        }
    }

    private var serviceStatsView: some View {
        List {
            Section("QSOs Present per Service") {
                ForEach(ServiceType.allCases, id: \.self) { service in
                    HStack {
                        Text(service.displayName)
                        Spacer()
                        Text("\(serviceCounts[service] ?? 0)")
                            .foregroundStyle(.secondary)
                            .fontDesign(.monospaced)
                    }
                }
            }
        }
        .onAppear {
            loadServiceCounts()
        }
        .refreshable {
            loadServiceCounts()
        }
    }

    private func loadServiceCounts() {
        var counts: [ServiceType: Int] = [:]
        do {
            let descriptor = FetchDescriptor<ServicePresence>()
            let allPresence = try modelContext.fetch(descriptor)
            for service in ServiceType.allCases {
                counts[service] =
                    allPresence.filter { $0.serviceType == service && $0.isPresent }.count
            }
        } catch {
            for service in ServiceType.allCases {
                counts[service] = 0
            }
        }
        serviceCounts = counts
    }
}

// MARK: - RawQSORow

struct RawQSORow: View {
    // MARK: Internal

    let qso: SyncDebugLog.RawQSOData

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation { isExpanded.toggle() }
            } label: {
                HStack {
                    Text(timeFormatter.string(from: qso.timestamp))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let call = qso.parsedFields["callsign"] {
                        Text(call)
                            .fontWeight(.medium)
                    }

                    if let freq = qso.parsedFields["frequency"] {
                        Text(freq)
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }

                    if let band = qso.parsedFields["band"] {
                        Text(band)
                            .font(.caption)
                            .padding(.horizontal, 4)
                            .background(Color.blue.opacity(0.2))
                            .clipShape(Capsule())
                    }

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    // Parsed fields
                    Text("Parsed Fields:")
                        .font(.caption)
                        .fontWeight(.semibold)

                    let sortedFields = qso.parsedFields.sorted { $0.key < $1.key }
                    ForEach(sortedFields, id: \.key) { key, value in
                        HStack(alignment: .top) {
                            Text(key)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .frame(width: 100, alignment: .leading)
                            Text(value)
                                .font(.caption2)
                                .fontDesign(.monospaced)
                        }
                    }

                    Divider()

                    // Raw JSON
                    Text("Raw Data:")
                        .font(.caption)
                        .fontWeight(.semibold)

                    ScrollView(.horizontal, showsIndicators: true) {
                        Text(qso.rawJSON)
                            .font(.caption2)
                            .fontDesign(.monospaced)
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: 150)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .padding(.top, 4)
            }
        }
    }

    // MARK: Private

    @State private var isExpanded = false

    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }
}

// MARK: - LogEntryRow

struct LogEntryRow: View {
    // MARK: Internal

    let entry: SyncDebugLog.LogEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(timeFormatter.string(from: entry.timestamp))
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Text(entry.level.rawValue)
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(levelColor)
                    .padding(.horizontal, isActionRequired ? 6 : 0)
                    .padding(.vertical, isActionRequired ? 2 : 0)
                    .background(isActionRequired ? Color.purple.opacity(0.3) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                if let service = entry.service {
                    Text(service.displayName)
                        .font(.caption2)
                        .padding(.horizontal, 4)
                        .background(Color.blue.opacity(0.2))
                        .clipShape(Capsule())
                }
            }

            Text(entry.message)
                .font(.caption)
                .foregroundStyle(isActionRequired ? .primary : .primary)
                .textSelection(.enabled)
        }
        .padding(.vertical, isActionRequired ? 4 : 0)
        .padding(.horizontal, isActionRequired ? 8 : 0)
        .background(isActionRequired ? Color.purple.opacity(0.1) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: Private

    private var isActionRequired: Bool {
        entry.level == .actionRequired
    }

    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }

    private var levelColor: Color {
        switch entry.level {
        case .info: .blue
        case .warning: .orange
        case .error: .red
        case .debug: .gray
        case .actionRequired: .purple
        }
    }
}
