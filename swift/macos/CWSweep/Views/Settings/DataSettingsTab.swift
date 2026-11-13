import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - DataSettingsTab

/// Settings tab for log data management including clear log with backup.
struct DataSettingsTab: View {
    // MARK: Internal

    @Environment(\.modelContext) var modelContext

    var body: some View {
        Form {
            potaParksCacheSection
            logOverviewSection
            clearLogSection
        }
        .formStyle(.grouped)
        .task {
            await loadQSOCount()
            await loadParkStatus()
        }
        .sheet(isPresented: $showClearConfirmation) {
            ClearLogConfirmationSheet(
                qsoCount: qsoCount,
                container: modelContext.container,
                onCleared: {
                    Task { await loadQSOCount() }
                }
            )
        }
    }

    // MARK: Private

    @State private var qsoCount = 0
    @State private var showClearConfirmation = false
    @State private var parkCacheStatus: ParksCacheStatus = .notLoaded
    @State private var isRefreshingParks = false

    private var potaParksCacheSection: some View {
        Section("POTA Parks Database") {
            switch parkCacheStatus {
            case .notLoaded:
                HStack {
                    Text("Not downloaded")
                    Spacer()
                    Button("Download") {
                        Task { await refreshParks() }
                    }
                    .buttonStyle(.bordered)
                }
            case .loading:
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Loading from cache...")
                }
            case .downloading:
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Downloading parks database...")
                }
            case let .loaded(count, downloadedAt):
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(count.formatted()) parks")
                        if let date = downloadedAt {
                            HStack(spacing: 4) {
                                Text("Downloaded")
                                Text(date, style: .relative)
                                Text("ago")
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button {
                        Task { await refreshParks() }
                    } label: {
                        if isRefreshingParks {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isRefreshingParks)
                }
            case let .failed(error):
                VStack(alignment: .leading, spacing: 4) {
                    Text("Download failed: \(error)")
                        .foregroundStyle(.orange)
                    Button("Retry") {
                        Task { await refreshParks() }
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private var logOverviewSection: some View {
        Section("Log Overview") {
            HStack {
                Text("Total QSOs")
                Spacer()
                Text("\(qsoCount)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var clearLogSection: some View {
        Section("Clear Log") {
            Text(
                "Permanently delete all QSOs from this device. "
                    + "An ADIF backup will be created first. "
                    + "If iCloud QSO Sync is enabled, your logbook "
                    + "will be re-downloaded from iCloud immediately. "
                    + "This does not delete QSOs from sync services "
                    + "(QRZ, POTA, LoTW, Club Log)."
            )
            .font(.callout)
            .foregroundStyle(.secondary)

            Button("Clear All QSOs...", role: .destructive) {
                showClearConfirmation = true
            }
            .disabled(qsoCount == 0)
        }
    }

    private func loadParkStatus() async {
        parkCacheStatus = await POTAParksCache.shared.status
        if case .notLoaded = parkCacheStatus {
            await POTAParksCache.shared.ensureLoaded()
            parkCacheStatus = await POTAParksCache.shared.status
        }
    }

    private func refreshParks() async {
        isRefreshingParks = true
        defer { isRefreshingParks = false }
        await POTAParksCache.shared.forceRefresh()
        parkCacheStatus = await POTAParksCache.shared.status
    }

    private func loadQSOCount() async {
        let predicate = #Predicate<QSO> { qso in
            !qso.isHidden && !qso.callsign.isEmpty
                && qso.mode != "WEATHER"
                && qso.mode != "SOLAR"
                && qso.mode != "NOTE"
        }
        var seen = Set<UUID>()
        var total = 0
        var offset = 0

        while true {
            let descriptor = BoundedDescriptor<QSO>(
                predicate: predicate,
                limit: BoundedDescriptor<QSO>.maxLimit,
                offset: offset
            )
            let batch = (try? modelContext.boundedFetch(descriptor)) ?? []
            if batch.isEmpty {
                break
            }
            total += batch.filter { seen.insert($0.id).inserted }.count
            offset += batch.count
        }
        qsoCount = total
    }
}

// MARK: - ClearLogConfirmationSheet

/// Confirmation sheet that requires the user to type the exact QSO count,
/// takes an ADIF backup, then deletes all QSOs locally.
struct ClearLogConfirmationSheet: View {
    // MARK: Internal

    let qsoCount: Int
    let container: ModelContainer
    var onCleared: (() -> Void)?

    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 0) {
            headerSection
            Divider()
            contentSection
            Divider()
            footerSection
        }
        .frame(width: 440, height: 360)
    }

    // MARK: Private

    private enum ClearState {
        case confirming
        case backingUp
        case clearing
        case completed(backupPath: String)
        case failed(String)
    }

    @State private var confirmationText = ""
    @State private var clearState: ClearState = .confirming
    @State private var backupProgress: FullExportProgressInfo?

    private var confirmationMatches: Bool {
        confirmationText == String(qsoCount)
    }

    private var headerSection: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 28))
                .foregroundStyle(.red)

            VStack(alignment: .leading, spacing: 2) {
                Text("Clear Log")
                    .font(.headline)
                Text("This will permanently delete \(qsoCount) QSOs")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding()
    }

    @ViewBuilder
    private var contentSection: some View {
        switch clearState {
        case .confirming:
            confirmingView
        case .backingUp:
            backingUpView
        case .clearing:
            clearingView
        case let .completed(backupPath):
            completedView(backupPath: backupPath)
        case let .failed(message):
            failedView(message: message)
        }
    }

    private var confirmingView: some View {
        VStack(spacing: 16) {
            Spacer()

            Text("Type the number of QSOs to confirm:")
                .font(.subheadline)

            HStack(spacing: 12) {
                TextField("Enter \(qsoCount)", text: $confirmationText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
                    .multilineTextAlignment(.center)
                    .font(.system(.title3, design: .monospaced))

                Text("/ \(qsoCount)")
                    .font(.title3.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 4) {
                Text("An ADIF backup will be saved before deleting.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("QSOs on sync services will not be affected.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding()
    }

    private var backingUpView: some View {
        VStack(spacing: 12) {
            Spacer()
            ProgressView()
            Text("Creating ADIF backup...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let progress = backupProgress {
                Text("Exporting \(progress.processed) of \(progress.total)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .padding()
    }

    private var clearingView: some View {
        VStack(spacing: 12) {
            Spacer()
            ProgressView()
            Text("Deleting QSOs...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding()
    }

    private var footerSection: some View {
        HStack {
            Spacer()

            switch clearState {
            case .confirming:
                Button("Clear All QSOs", role: .destructive) {
                    Task { await performClearLog() }
                }
                .disabled(!confirmationMatches)

                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)

            case .backingUp,
                 .clearing:
                EmptyView()

            case .completed,
                 .failed:
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
    }

    private func completedView(backupPath: String) -> some View {
        VStack(spacing: 12) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.green)

            Text("Log Cleared")
                .font(.headline)

            Text("Backup saved to:")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(backupPath)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .textSelection(.enabled)

            Button("Show in Finder") {
                showInFinder(path: backupPath)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Spacer()
        }
        .padding()
    }

    private func failedView(message: String) -> some View {
        VStack(spacing: 12) {
            Spacer()

            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.red)

            Text("Clear Failed")
                .font(.headline)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Spacer()
        }
        .padding()
    }

    // MARK: - Clear Log Logic

    private func performClearLog() async {
        // Step 1: Create ADIF backup
        clearState = .backingUp

        let config = ADIFExportConfig(
            appName: "CWSweep",
            filenamePrefix: "cwsweep_backup_before_clear",
            appFieldPrefix: "APP_CWSWEEP"
        )
        let exportActor = FullADIFExportActor(config: config)

        do {
            let result = try await exportActor.exportAllQSOs(
                container: container
            ) { info in
                Task { @MainActor in
                    backupProgress = info
                }
            }

            // Save backup to Documents
            let documentsURL = FileManager.default.urls(
                for: .documentDirectory, in: .userDomainMask
            ).first!
            let backupURL = documentsURL.appendingPathComponent(
                result.filename
            )
            try FileManager.default.copyItem(
                at: result.fileURL, to: backupURL
            )

            // Step 2: Delete all QSOs
            clearState = .clearing
            try await deleteAllQSOs()

            // CAR-264 (server-sync analogue): clearing the local store leaves
            // the per-server pull cursor in place, so the next pass would
            // skip everything already applied and the log would never
            // repopulate. Drop the cursors so the whole journal replays.
            await ServerSyncService.shared.resetForLocalWipe()

            clearState = .completed(backupPath: backupURL.path)
            onCleared?()
        } catch {
            clearState = .failed(error.localizedDescription)
        }
    }

    private func deleteAllQSOs() async throws {
        let context = ModelContext(container)

        let descriptor = BoundedDescriptor<QSO>(
            limit: BoundedDescriptor<QSO>.maxLimit
        )

        var totalDeleted = 0
        var hasMore = true

        while hasMore {
            let batch = try context.boundedFetch(descriptor)
            if batch.isEmpty {
                hasMore = false
            } else {
                // Local wipe: hard-delete from cw-store too (under `.on` the
                // seam deletes there first), presence rows before their QSOs.
                let qsoIds = batch.map { SwiftDataStoreImporter.uuid($0.id) }
                let presenceIds = batch
                    .flatMap { qso in qso.servicePresence.map { SwiftDataStoreImporter.uuid($0.id) } }
                for qso in batch {
                    context.delete(qso)
                }
                totalDeleted += batch.count
                try OffMainStoreSeam.commit(in: context, storeOps: [{ store in
                    for id in presenceIds {
                        try store.deleteServicePresence(id: id)
                    }
                    for id in qsoIds {
                        try store.deleteQso(id: id)
                    }
                }])
            }
        }
    }

    private func showInFinder(path: String) {
        NSWorkspace.shared.selectFile(
            path, inFileViewerRootedAtPath: ""
        )
    }
}
