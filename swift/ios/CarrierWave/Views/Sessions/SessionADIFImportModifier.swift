// Sheet that handles importing an ADIF file into a specific session.
// Presents a file picker, scans for metadata mismatches (callsign/park),
// shows confirmation when needed, and reports the result.

import CarrierWaveData
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

// MARK: - SessionADIFImportSheet

struct SessionADIFImportSheet: View {
    // MARK: Internal

    let session: LoggingSession
    var onComplete: (() async -> Void)?

    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            contentView
                .navigationTitle("Import ADIF")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
                .fileImporter(
                    isPresented: $showFilePicker,
                    allowedContentTypes: ADIFFileType.importTypes,
                    onCompletion: handleFileSelected
                )
                .confirmationDialog(
                    "Metadata Mismatch",
                    isPresented: $showMismatchWarning,
                    titleVisibility: .visible
                ) {
                    Button("Import As-Is") {
                        performImport(overrideMetadata: false)
                    }
                    Button("Use Session Metadata") {
                        performImport(overrideMetadata: true)
                    }
                    Button("Cancel", role: .cancel) { dismiss() }
                } message: {
                    Text(mismatchMessage)
                }
                .confirmationDialog(
                    "Missing Metadata",
                    isPresented: $showMissingInfo,
                    titleVisibility: .visible
                ) {
                    Button("Import") {
                        performImport(overrideMetadata: true)
                    }
                    Button("Cancel", role: .cancel) { dismiss() }
                } message: {
                    Text(missingInfoMessage)
                }
                .alert(
                    "Import Complete",
                    isPresented: $showResult
                ) {
                    Button("OK") {
                        Task {
                            await onComplete?()
                            dismiss()
                        }
                    }
                } message: {
                    Text(resultMessage)
                }
                .alert(
                    "Import Failed",
                    isPresented: $showError
                ) {
                    Button("OK") { dismiss() }
                } message: {
                    Text(errorMessage)
                }
                .onAppear { showFilePicker = true }
        }
    }

    // MARK: Private

    @Environment(\.modelContext) private var modelContext

    @State private var showFilePicker = false
    @State private var showMismatchWarning = false
    @State private var showMissingInfo = false
    @State private var showResult = false
    @State private var showError = false
    @State private var isImporting = false
    @State private var resultMessage = ""
    @State private var errorMessage = ""
    @State private var mismatchMessage = ""
    @State private var missingInfoMessage = ""
    @State private var pendingURL: URL?

    @ViewBuilder
    private var contentView: some View {
        if isImporting {
            VStack(spacing: 16) {
                ProgressView()
                Text("Importing...")
                    .foregroundStyle(.secondary)
            }
        } else {
            VStack(spacing: 16) {
                Image(systemName: "square.and.arrow.down")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                sessionMetadataPreview
                Button("Choose File") {
                    showFilePicker = true
                }
                .buttonStyle(.bordered)
            }
            .padding()
        }
    }

    private var sessionMetadataPreview: some View {
        VStack(spacing: 4) {
            Text("Importing into session:")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(session.myCallsign)
                .font(.headline)
            if let park = session.parkReference {
                Text(park)
                    .font(.subheadline)
                    .foregroundStyle(.green)
            }
        }
    }

    private func handleFileSelected(
        _ result: Result<URL, Error>
    ) {
        switch result {
        case let .success(url):
            scanAndValidate(url: url)
        case let .failure(error):
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    private func scanAndValidate(url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            errorMessage = "Could not access the selected file."
            showError = true
            return
        }

        let importService = ImportService(modelContext: modelContext)

        do {
            let detected = try importService.scanADIF(from: url)
            let mismatch = importService.checkMetadataMismatch(
                detected: detected, session: session
            )

            pendingURL = url

            if let mismatch {
                if hasTrueMismatch(mismatch) {
                    mismatchMessage = buildMismatchMessage(
                        mismatch, recordCount: detected.recordCount
                    )
                    showMismatchWarning = true
                } else {
                    missingInfoMessage = buildMissingMessage(
                        mismatch, recordCount: detected.recordCount
                    )
                    showMissingInfo = true
                }
            } else {
                performImport(overrideMetadata: false)
            }
        } catch {
            url.stopAccessingSecurityScopedResource()
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    private func hasTrueMismatch(
        _ mismatch: ImportService.MetadataMismatch
    ) -> Bool {
        let callDiffers = !mismatch.adifCallsigns.isEmpty
            && !mismatch.adifCallsigns
            .allSatisfy { $0 == mismatch.sessionCallsign }
        let parkDiffers = !mismatch.adifParks.isEmpty
            && mismatch.adifParks != Set(
                [mismatch.sessionPark].compactMap { $0 }
            )
        return callDiffers || parkDiffers
    }

    private func performImport(overrideMetadata: Bool) {
        guard let url = pendingURL else {
            errorMessage = "No file selected."
            showError = true
            return
        }

        isImporting = true

        Task {
            let importService = ImportService(modelContext: modelContext)
            do {
                let result = try await importService.importADIFIntoSession(
                    from: url, session: session,
                    overrideMetadata: overrideMetadata
                )
                url.stopAccessingSecurityScopedResource()
                pendingURL = nil
                resultMessage = formatResult(
                    result, filename: url.lastPathComponent
                )
                isImporting = false
                showResult = true
            } catch {
                url.stopAccessingSecurityScopedResource()
                pendingURL = nil
                isImporting = false
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }
}

// MARK: - Message Builders

extension SessionADIFImportSheet {
    private func buildMismatchMessage(
        _ mm: ImportService.MetadataMismatch,
        recordCount: Int
    ) -> String {
        var parts: [String] = []

        let callDiffers = !mm.adifCallsigns.isEmpty
            && !mm.adifCallsigns
            .allSatisfy { $0 == mm.sessionCallsign }
        if callDiffers {
            let calls = mm.adifCallsigns.sorted()
                .joined(separator: ", ")
            parts.append(
                "Callsign: ADIF has \(calls), "
                    + "session is \(mm.sessionCallsign)"
            )
        }

        let parkDiffers = !mm.adifParks.isEmpty
            && mm.adifParks != Set(
                [mm.sessionPark].compactMap { $0 }
            )
        if parkDiffers {
            let parks = mm.adifParks.sorted()
                .joined(separator: ", ")
            let sPark = mm.sessionPark ?? "none"
            parts.append(
                "Park: ADIF has \(parks), session is \(sPark)"
            )
        }

        if !mm.missingFields.isEmpty {
            let fields = mm.missingFields.joined(separator: ", ")
            parts.append(
                "Missing \(fields) — will use session values"
            )
        }

        let header = "\(recordCount) record(s) found.\n\n"
        let footer = "\n\nImporting will use the session's metadata."
        return header + parts.joined(separator: "\n") + footer
    }

    private func buildMissingMessage(
        _ mismatch: ImportService.MetadataMismatch,
        recordCount: Int
    ) -> String {
        let fields = mismatch.missingFields
            .joined(separator: " and ")
        return "\(recordCount) record(s) found.\n\n"
            + "The ADIF file has no \(fields). "
            + "The session's values will be used."
    }

    private func formatResult(
        _ result: ImportService.ImportResult,
        filename: String
    ) -> String {
        var lines: [String] = [filename]

        if result.imported > 0 {
            lines.append("\(result.imported) QSO(s) imported")
        }
        if result.duplicates > 0 {
            lines.append(
                "\(result.duplicates) existing QSO(s) adopted into session"
            )
        }
        if result.errors > 0 {
            lines.append("\(result.errors) error(s)")
        }
        if result.imported == 0, result.duplicates == 0 {
            lines.append("No new QSOs to import")
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - View Extension

extension View {
    func sessionADIFImportable(
        session: Binding<LoggingSession?>,
        onComplete: (() async -> Void)? = nil
    ) -> some View {
        sheet(item: session) { targetSession in
            SessionADIFImportSheet(
                session: targetSession,
                onComplete: onComplete
            )
        }
    }
}
