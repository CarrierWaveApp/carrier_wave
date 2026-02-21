import SwiftData
import SwiftUI

// MARK: - DataToolsSettingsView

struct DataToolsSettingsView: View {
    // MARK: Internal

    var body: some View {
        List {
            backupsSection
            dataSection
            deduplicationSection
        }
        .navigationTitle("Data & Tools")
        .alert("Error", isPresented: $showingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage)
        }
        .alert("Deduplication Complete", isPresented: $showingDedupeResult) {
            Button("OK") {}
        } message: {
            Text(dedupeResultMessage)
        }
        .task { await loadLastBackupText() }
        .sheet(
            item: $exportedFile,
            onDismiss: { isExportingDatabase = false },
            content: { file in ShareSheet(activityItems: [file.url]) }
        )
    }

    // MARK: Private

    @Environment(\.modelContext) private var modelContext

    @State private var qrzCallbookIsConfigured = false
    @State private var isExportingDatabase = false
    @State private var exportedFile: ExportedFile?
    @State private var showingError = false
    @State private var errorMessage = ""

    @State private var dedupeTimeWindow = 5
    @State private var isDeduplicating = false
    @State private var showingDedupeResult = false
    @State private var dedupeResultMessage = ""
    @State private var lastBackupText = ""

    private var backupsSection: some View {
        Section {
            NavigationLink {
                BackupSettingsView()
            } label: {
                HStack {
                    Text("Backups")
                    Spacer()
                    Text(lastBackupText)
                        .foregroundStyle(.secondary)
                }
            }
        } footer: {
            Text(
                "Automatic snapshots protect against data loss. "
                    + "Restore from any backup if needed."
            )
        }
    }

    private var dataSection: some View {
        Section {
            NavigationLink {
                QRZCallbookSettingsView()
            } label: {
                HStack {
                    Text("QRZ Callbook")
                    Spacer()
                    if qrzCallbookIsConfigured {
                        if let username = try? KeychainHelper.shared.readString(
                            for: KeychainHelper.Keys.qrzCallbookUsername
                        ) {
                            Text(username)
                                .foregroundStyle(.secondary)
                        }
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .accessibilityLabel("Connected")
                    }
                }
            }

            NavigationLink {
                CallsignNotesSettingsView()
            } label: {
                Text("Callsign Notes")
            }

            NavigationLink {
                ExternalDataView()
            } label: {
                Text("External Data")
            }

            Button {
                isExportingDatabase = true
                Task { await exportDatabase() }
            } label: {
                if isExportingDatabase {
                    HStack {
                        ProgressView()
                            .padding(.trailing, 4)
                        Text("Exporting...")
                    }
                } else {
                    Text("Export SQLite Database")
                }
            }
            .disabled(isExportingDatabase)
        } header: {
            Text("Data")
        } footer: {
            Text(
                "QRZ Callbook enables callsign lookups (requires QRZ XML subscription). "
                    + "Export creates a backup of the QSO database."
            )
        }
    }

    private var deduplicationSection: some View {
        Section {
            Stepper(
                "Time window: \(dedupeTimeWindow) min",
                value: $dedupeTimeWindow,
                in: 1 ... 15
            )

            Button {
                Task { await runDeduplication() }
            } label: {
                if isDeduplicating {
                    HStack {
                        ProgressView()
                            .padding(.trailing, 4)
                        Text("Scanning...")
                    }
                } else {
                    Text("Find & Merge Duplicates")
                }
            }
            .disabled(isDeduplicating)
        } header: {
            Text("Deduplication")
        } footer: {
            Text(
                """
                Find QSOs with same callsign, band, and mode within \
                \(dedupeTimeWindow) min and merge. Mode families are treated \
                as equivalent (e.g., PHONE/SSB/USB, DATA/FT8/PSK31).
                """
            )
        }
    }

    @MainActor
    private func exportDatabase() async {
        do {
            try modelContext.save()
            let exportURL = try await DatabaseExporter.export(
                from: modelContext.container
            )
            exportedFile = ExportedFile(url: exportURL)
        } catch {
            isExportingDatabase = false
            errorMessage = "Failed to export database: \(error.localizedDescription)"
            showingError = true
        }
    }

    private func runDeduplication() async {
        isDeduplicating = true
        defer { isDeduplicating = false }

        do {
            let service = DeduplicationService(modelContext: modelContext)
            let result = try service.findAndMergeDuplicates(
                timeWindowMinutes: dedupeTimeWindow
            )

            if result.duplicateGroupsFound == 0 {
                dedupeResultMessage = "No duplicates found."
            } else {
                dedupeResultMessage = """
                Found \(result.duplicateGroupsFound) duplicate groups.
                Merged \(result.qsosMerged) QSOs, \
                removed \(result.qsosRemoved) duplicates.
                """
            }
            showingDedupeResult = true
        } catch {
            errorMessage = "Deduplication failed: \(error.localizedDescription)"
            showingError = true
        }
    }

    private func loadLastBackupText() async {
        let backups = await BackupService.shared.availableBackups()
        if let latest = backups.first {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .abbreviated
            lastBackupText = formatter.localizedString(
                for: latest.timestamp,
                relativeTo: Date()
            )
        } else {
            lastBackupText = "Never"
        }
    }
}
