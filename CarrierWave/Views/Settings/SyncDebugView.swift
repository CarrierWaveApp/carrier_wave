import CarrierWaveCore
import SwiftData
import SwiftUI

// MARK: - SyncDebugView

struct SyncDebugView: View {
    // MARK: Internal

    @ObservedObject var debugLog = SyncDebugLog.shared

    var potaAuth: POTAAuthService?

    var body: some View {
        VStack(spacing: 0) {
            Picker("View", selection: $selectedTab) {
                Text("Raw QSOs").tag(0)
                Text("Sync Log").tag(1)
                Text("Stats").tag(2)
                Text("POTA Jobs").tag(3)
            }
            .pickerStyle(.segmented)
            .padding()

            if selectedTab == 0 {
                rawQSOsView
            } else if selectedTab == 1 {
                syncLogView
            } else if selectedTab == 2 {
                serviceStatsView
            } else {
                potaJobsView
            }
        }
        .navigationTitle("Sync Debug")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    if let logFileURL = createLogFile() {
                        ShareLink(item: logFileURL) {
                            Label("Share Log", systemImage: "square.and.arrow.up")
                        }
                    }

                    Divider()

                    Button("Clear Logs Only") {
                        debugLog.clearLogs()
                    }
                    Button("Clear All", role: .destructive) {
                        debugLog.clearAll()
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
    }

    // MARK: Private

    @Environment(\.modelContext) private var modelContext
    @State private var selectedTab = 0
    @State private var serviceCounts: [ServiceType: Int] = [:]
    @State private var potaJobs: [POTAJob] = []
    @State private var isLoadingJobs = false
    @State private var jobsError: String?

    private var potaClient: POTAClient? {
        guard let potaAuth else {
            return nil
        }
        return POTAClient(authService: potaAuth)
    }

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

    private var potaJobsView: some View {
        List {
            if let potaAuth, potaAuth.isConfigured {
                if let error = jobsError {
                    Section {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text(error)
                                .font(.caption)
                            Spacer()
                            Button("Retry") {
                                Task { await loadJobs() }
                            }
                            .font(.caption)
                        }
                    }
                }

                ForEach(potaJobs) { job in
                    POTAJobRow(job: job, potaClient: potaClient)
                }

                if potaJobs.isEmpty, !isLoadingJobs {
                    ContentUnavailableView(
                        "No Jobs",
                        systemImage: "tray",
                        description: Text("No POTA upload jobs found.")
                    )
                }
            } else {
                ContentUnavailableView(
                    "Not Authenticated",
                    systemImage: "person.crop.circle.badge.xmark",
                    description: Text("Sign in to POTA in Settings to view upload jobs.")
                )
            }
        }
        .overlay {
            if isLoadingJobs {
                ProgressView()
            }
        }
        .refreshable {
            await loadJobs()
        }
        .task {
            if potaJobs.isEmpty {
                await loadJobs()
            }
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

    private func formatLogForSharing() -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        dateFormatter.timeZone = TimeZone(identifier: "UTC")

        var lines: [String] = ["Carrier Wave Sync Debug Log", "Exported: \(dateFormatter.string(from: Date())) UTC", ""]

        for entry in debugLog.logEntries.reversed() {
            let ts = dateFormatter.string(from: entry.timestamp)
            let svc = entry.service.map { "[\($0.displayName)] " } ?? ""
            lines.append("[\(entry.level.rawValue)] \(ts) \(svc)\(entry.message)")
        }

        return lines.joined(separator: "\n")
    }

    private func createLogFile() -> URL? {
        guard !debugLog.logEntries.isEmpty else {
            return nil
        }
        let content = formatLogForSharing()
        let filenameDateFormatter = DateFormatter()
        filenameDateFormatter.dateFormat = "yyyy-MM-dd_HHmmss"
        let timestamp = filenameDateFormatter.string(from: Date())
        let filename = "carrier-wave-sync-log-\(timestamp).txt"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    private func loadJobs() async {
        guard let potaClient else {
            return
        }
        isLoadingJobs = true
        jobsError = nil

        do {
            let fetchedJobs = try await potaClient.fetchJobs()
            potaJobs = fetchedJobs.sorted { $0.submitted > $1.submitted }
        } catch {
            jobsError = error.localizedDescription
        }

        isLoadingJobs = false
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
