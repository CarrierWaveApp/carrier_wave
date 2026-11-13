import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - SyncDebugView

struct SyncDebugView: View {
    // MARK: Internal

    var debugLog = SyncDebugLog.shared

    var potaAuth: POTAAuthService?

    var body: some View {
        VStack(spacing: 0) {
            Picker("View", selection: $selectedTab) {
                Text("Pending").tag(0)
                Text("Raw QSOs").tag(1)
                Text("Sync Log").tag(2)
                Text("Stats").tag(3)
                Text("POTA Jobs").tag(4)
            }
            .pickerStyle(.segmented)
            .padding()

            if selectedTab == 0 {
                PendingUploadsView()
            } else if selectedTab == 1 {
                rawQSOsView
            } else if selectedTab == 2 {
                syncLogView
            } else if selectedTab == 3 {
                serviceStatsView
            } else {
                potaJobsView
            }
        }
        .navigationTitle("Sync Debug")
        .onChange(of: logFileURL) { _, url in
            guard let url else {
                return
            }
            presentShareSheet(for: url)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        shareLogFile()
                    } label: {
                        Label("Share Log", systemImage: "square.and.arrow.up")
                    }
                    .disabled(debugLog.logEntries.isEmpty)

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
    @State private var logFileURL: URL?

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
        SyncLogFilteredView(debugLog: debugLog)
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
        for service in ServiceType.allCases {
            let serviceRaw = service.rawValue
            let predicate = #Predicate<ServicePresence> {
                $0.serviceTypeRawValue == serviceRaw && $0.isPresent
            }
            counts[service] = (try? modelContext.boundedCount(
                ServicePresence.self, predicate: predicate
            )) ?? 0
        }
        serviceCounts = counts
    }

    private func formatLogForSharing() -> String {
        SyncLogFormatter.format(entries: debugLog.logEntries)
    }

    private func shareLogFile() {
        guard let url = createLogFile() else {
            return
        }
        logFileURL = url
    }

    private func createLogFile() -> URL? {
        guard !debugLog.logEntries.isEmpty else {
            return nil
        }
        let content = formatLogForSharing()
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd_HHmmss"
        let filename = "carrier-wave-sync-log-\(fmt.string(from: Date())).log"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    private func presentShareSheet(for url: URL) {
        // Delay to let the Menu dismiss before presenting
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            let activityVC = UIActivityViewController(
                activityItems: [url],
                applicationActivities: nil
            )
            activityVC.excludedActivityTypes = [.copyToPasteboard]
            guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let rootVC = scene.keyWindow?.rootViewController
            else {
                return
            }
            var presenter = rootVC
            while let presented = presenter.presentedViewController {
                presenter = presented
            }
            presenter.present(activityVC, animated: true) {
                logFileURL = nil
            }
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
                    Text(Self.timeFormatter.string(from: qso.timestamp))
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

    private static let timeFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm:ss"
        return fmt
    }()

    @State private var isExpanded = false
}

// MARK: - LogEntryRow

struct LogEntryRow: View {
    // MARK: Internal

    let entry: SyncDebugLog.LogEntry

    var body: some View {
        HStack(spacing: 0) {
            // Left color strip for warn/error/action
            if let stripColor {
                stripColor
                    .frame(width: 3)
                    .clipShape(RoundedRectangle(cornerRadius: 1.5))
                    .padding(.trailing, 8)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(Self.timeFormatter.string(from: entry.timestamp))
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    levelBadge

                    if let service = entry.service {
                        Text(service.displayName)
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .background(Color.blue.opacity(0.15))
                            .clipShape(Capsule())
                    }
                }

                Text(entry.message)
                    .font(isDebug ? .caption2 : .caption)
                    .foregroundStyle(isDebug ? .secondary : .primary)
                    .fontWeight(isError ? .medium : .regular)
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, isHighlighted ? 4 : 0)
        .listRowBackground(rowBackground)
    }

    // MARK: Private

    nonisolated private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    private var isDebug: Bool {
        entry.level == .debug
    }

    private var isError: Bool {
        entry.level == .error
    }

    private var isHighlighted: Bool {
        switch entry.level {
        case .error,
             .warning,
             .actionRequired: true
        case .info,
             .debug: false
        }
    }

    private var stripColor: Color? {
        switch entry.level {
        case .error: .red
        case .warning: .orange
        case .actionRequired: .purple
        case .info,
             .debug: nil
        }
    }

    private var rowBackground: Color? {
        switch entry.level {
        case .error: Color.red.opacity(0.08)
        case .actionRequired: Color.purple.opacity(0.08)
        case .warning,
             .info,
             .debug: nil
        }
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

    // MARK: - Subviews

    private var levelBadge: some View {
        Text(entry.level.rawValue)
            .font(.caption2)
            .fontWeight(.bold)
            .foregroundStyle(isHighlighted ? .white : levelColor)
            .padding(.horizontal, isHighlighted ? 5 : 0)
            .padding(.vertical, isHighlighted ? 1 : 0)
            .background(isHighlighted ? levelColor : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }
}
