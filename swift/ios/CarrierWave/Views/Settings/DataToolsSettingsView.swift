import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - DataToolsSettingsView

struct DataToolsSettingsView: View {
    // MARK: Internal

    var body: some View {
        List {
            SettingsHeroHeader(
                icon: "wrench.and.screwdriver.fill",
                tint: .gray,
                title: "Data & Tools",
                subtitle: "Imports, exports, lookups, and log maintenance."
            )
            importSection
            dataSection
            deduplicationSection
        }
        .navigationTitle("Data & Tools")
        .navigationBarTitleDisplayMode(.inline)
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
        .sheet(
            item: $exportedFile,
            onDismiss: { isExportingDatabase = false },
            content: { file in ShareSheet(activityItems: [file.url]) }
        )
        .sheet(isPresented: $showingFullADIFExport) {
            FullADIFExportSheet()
        }
        .sheet(isPresented: $showingFullQSONExport) {
            FullQSONExportSheet()
        }
    }

    // MARK: Private

    @Environment(\.modelContext) private var modelContext

    @State private var qrzCallbookIsConfigured = false
    @State private var isExportingDatabase = false
    @State private var exportedFile: ExportedFile?
    @State private var showingFullADIFExport = false
    @State private var showingFullQSONExport = false
    @State private var showingError = false
    @State private var errorMessage = ""

    @State private var dedupeTimeWindow = 5
    @State private var isDeduplicating = false
    @State private var showingDedupeResult = false
    @State private var dedupeResultMessage = ""
    @AppStorage("commentParkAction") private var commentParkAction = "theirPark"

    private var importSection: some View {
        Section {
            Picker("Park Ref in Comment", selection: $commentParkAction) {
                ForEach(CommentParkAction.allCases, id: \.rawValue) { action in
                    Text(action.label).tag(action.rawValue)
                }
            }
            .pickerStyle(.menu)
        } header: {
            Text("Import Behavior")
        } footer: {
            let action = CommentParkAction(rawValue: commentParkAction) ?? .theirPark
            Text(action.description)
        }
    }

    private var dataSection: some View {
        Section {
            NavigationLink {
                QRZCallbookSettingsView()
            } label: {
                HStack {
                    Text("QRZ Callsign Lookup")
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

            NavigationLink {
                OperatorProfileCacheView()
            } label: {
                Text("Offline Operator Cache")
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

            Button {
                showingFullADIFExport = true
            } label: {
                Text("Export Full ADIF Log")
            }

            Button {
                showingFullQSONExport = true
            } label: {
                Text("Export Full QSON Log")
            }
        } header: {
            Text("Data")
        } footer: {
            Text(
                "QRZ Callsign Lookup shows operator names and locations "
                    + "(requires a QRZ XML subscription — separate from QRZ Logbook Sync). "
                    + "Export creates a backup of the QSO database, ADIF, or QSON log file."
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
            let service = DeduplicationService(container: modelContext.container)
            let result = try await service.findAndMergeDuplicates(
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
}
