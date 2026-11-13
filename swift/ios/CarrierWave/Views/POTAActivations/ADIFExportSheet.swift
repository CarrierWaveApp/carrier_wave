// ADIF Export Sheet
//
// Sheet view for exporting activation QSOs to ADIF format.
// Provides share, save to files, and copy to clipboard options.

import CarrierWaveCwFfi
import CarrierWaveData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - ADIFExportSheet

struct ADIFExportSheet: View {
    // MARK: Internal

    static let potaUploadPageURL = "https://pota.app/user/logs"

    let activation: POTAActivation
    let parkName: String?
    /// When set, the sheet exports this whole session (Rust, keyed by
    /// session id) instead of the single `activation`, which then only
    /// drives the header and stats.
    var session: LoggingSession?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Header - icon, park reference and name
                    HStack(spacing: 12) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 36))
                            .foregroundStyle(.orange)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(activation.parkReference)
                                .font(.title2)
                                .fontWeight(.bold)

                            if let name = parkName {
                                Text(name)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if showInstructions {
                        potaUploadInstructions
                    }

                    // Details
                    VStack(spacing: 12) {
                        UploadDetailRow(label: "Date", value: activation.displayDate)
                        UploadDetailRow(label: "Callsign", value: activation.callsign)
                        UploadDetailRow(
                            label: "QSOs",
                            value: "\(exportResult?.qsoCount ?? activation.qsoCount)"
                        )
                        UploadDetailRow(
                            label: "Bands",
                            value: activation.uniqueBands.sorted().joined(separator: ", ")
                        )
                        UploadDetailRow(
                            label: "Modes",
                            value: activation.uniqueModes.sorted().joined(separator: ", ")
                        )
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(12)
                }
                .padding(.horizontal)
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 12) {
                    if isGenerating {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text("Generating ADIF...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else if let exportResult {
                        uploadToPOTAButton(result: exportResult)
                        Text("Shares the ADIF and opens the POTA upload page — attach the file there.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        shareButton(result: exportResult)
                        saveToFilesButton
                        copyToClipboardButton(result: exportResult)
                    } else if let errorMessage {
                        errorView(message: errorMessage)
                    }
                }
                .padding()
                .background(.bar)
            }
            .navigationTitle("Export ADIF")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
                if !showInstructions {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            withAnimation { showInstructions = true }
                        } label: {
                            Image(systemName: "questionmark.circle")
                        }
                    }
                }
            }
            .onAppear {
                if !instructionsSeen {
                    showInstructions = true
                }
            }
            .fileExporter(
                isPresented: $showFileSaver,
                document: exportResult.map { ADIFDocument(content: $0.content) },
                contentType: ADIFFileType.utType,
                defaultFilename: exportResult?.filename ?? "activation.adi"
            ) { result in
                switch result {
                case .success:
                    savedSuccessfully = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        savedSuccessfully = false
                    }
                case let .failure(error):
                    errorMessage = "Failed to save: \(error.localizedDescription)"
                }
            }
        }
        .landscapeAdaptiveDetents(portrait: [.medium, .large])
        .task {
            await generateADIF()
        }
    }

    // MARK: Private

    /// App marketing version passed to the ADIF header (`PROGRAMVERSION`).
    private static var programVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    @Environment(\.dismiss) private var dismiss

    @AppStorage("potaExportInstructionsSeen") private var instructionsSeen = false
    @State private var showInstructions = false
    @State private var isGenerating = false
    @State private var exportResult: ADIFExportResult?
    @State private var errorMessage: String?
    @State private var showFileSaver = false
    @State private var copiedToClipboard = false
    @State private var savedSuccessfully = false

    private var potaUploadInstructions: some View {
        POTAUploadInstructionsCard(
            onGotIt: {
                withAnimation {
                    instructionsSeen = true
                    showInstructions = false
                }
            },
            onShowNextTime: {
                withAnimation {
                    showInstructions = false
                }
            }
        )
    }

    private var saveToFilesButton: some View {
        Button {
            showFileSaver = true
        } label: {
            Label("Save to Files", systemImage: "folder")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
    }

    private func uploadToPOTAButton(result: ADIFExportResult) -> some View {
        ShareLink(
            item: ShareableADIF(content: result.content, filename: result.filename),
            preview: SharePreview(result.filename, image: Image(systemName: "globe"))
        ) {
            Label("Upload to POTA", systemImage: "arrow.up.forward.app.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .simultaneousGesture(TapGesture().onEnded {
            if let url = URL(string: Self.potaUploadPageURL) {
                UIApplication.shared.open(url)
            }
        })
    }

    private func shareButton(result: ADIFExportResult) -> some View {
        ShareLink(
            item: ShareableADIF(content: result.content, filename: result.filename),
            preview: SharePreview(result.filename, image: Image(systemName: "doc.text"))
        ) {
            Label("Share ADIF", systemImage: "square.and.arrow.up")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
    }

    private func copyToClipboardButton(result: ADIFExportResult) -> some View {
        Button {
            UIPasteboard.general.string = result.content
            copiedToClipboard = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                copiedToClipboard = false
            }
        } label: {
            Label(
                copiedToClipboard ? "Copied!" : "Copy to Clipboard",
                systemImage: copiedToClipboard ? "checkmark" : "doc.on.doc"
            )
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title)
                .foregroundStyle(.red)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Try Again") {
                Task {
                    await generateADIF()
                }
            }
            .buttonStyle(.bordered)
        }
    }

    private func generateADIF() async {
        isGenerating = true
        errorMessage = nil
        defer { isGenerating = false }

        // Small delay to let sheet animation complete before processing
        try? await Task.sleep(for: .milliseconds(100))

        do {
            let store = try await CwStoreProvider.shared.store()
            let api = AdifApi(store: store)
            exportResult = if let session {
                try await generateSessionExport(session, api: api)
            } else {
                try await generateActivationExport(api: api)
            }
        } catch {
            errorMessage = "Failed to generate ADIF: \(error.localizedDescription)"
        }
    }
}

// MARK: - Generation

private extension ADIFExportSheet {
    /// Activation-keyed export. The activation is (park, callsign, UTC day) —
    /// the Rust writer re-scopes the QSOs from the FieldStore, so no in-memory
    /// snapshotting is needed here.
    func generateActivationExport(api: AdifApi) async throws -> ADIFExportResult {
        let parkRef = activation.parkReference
        let callsign = activation.callsign
        let date = activation.utcDate
        let dateString = activation.utcDateString
        let version = Self.programVersion
        let content = try await Task.detached {
            try api.exportActivation(
                parkReference: parkRef,
                parkName: parkName,
                callsign: callsign,
                date: dateString,
                programVersion: version
            )
        }.value
        let filename = await ADIFExportService().generateFilename(
            parkReference: parkRef,
            activatorCallsign: callsign,
            date: date
        )
        return ADIFExportResult(content: content, filename: filename, qsoCount: activation.qsoCount)
    }

    /// Session-keyed export. Rust selects every visible QSO of the session by
    /// `logging_session_id` — merged days and parks, roves, and park-less
    /// QSOs included — and falls back to the session's park for records that
    /// have none. The QSO count comes back from Rust so the sheet shows what
    /// the file actually holds.
    func generateSessionExport(_ session: LoggingSession, api: AdifApi) async throws -> ADIFExportResult {
        let sessionId = SwiftDataStoreImporter.uuid(session.id)
        let parkRef = session.parkReference?.nonEmpty
        let sotaRef = session.sotaReference?.nonEmpty
        let callsign = session.stationCallsign?.nonEmpty ?? session.myCallsign
        let fallbackDate = session.startedAt
        let version = Self.programVersion
        let export = try await Task.detached {
            try api.exportSession(sessionId: sessionId, parkName: parkName, programVersion: version)
        }.value
        guard let export else {
            throw SessionExportError.sessionNotInStore
        }
        let date = export.firstQsoDate.map { Date(timeIntervalSince1970: TimeInterval($0)) } ?? fallbackDate
        let filename = await ADIFExportService().generateSessionFilename(
            activatorCallsign: callsign,
            parkReference: parkRef,
            sotaReference: sotaRef,
            date: date
        )
        return ADIFExportResult(content: export.adif, filename: filename, qsoCount: Int(export.qsoCount))
    }
}

// MARK: - SessionExportError

private enum SessionExportError: LocalizedError {
    case sessionNotInStore

    // MARK: Internal

    var errorDescription: String? {
        "This session isn't in the log store yet."
    }
}

// MARK: - ADIFFileType

/// ADIF file type helper - enum to avoid MainActor isolation on static property
enum ADIFFileType {
    /// ADIF UTType - prefer registered type from Info.plist, fall back to runtime declaration
    nonisolated static let utType = UTType("org.adif.adi")
        ?? UTType(filenameExtension: "adi", conformingTo: .data)!

    /// All content types accepted by ADIF file importers.
    /// Includes .data so .adi/.adif files not created by this app are selectable.
    nonisolated static let importTypes: [UTType] = [utType, .data]
}

// MARK: - ShareableADIF

/// A transferable wrapper for sharing ADIF files
struct ShareableADIF: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: ADIFFileType.utType) { item in
            let tempDir = FileManager.default.temporaryDirectory
            let fileURL = tempDir.appendingPathComponent(item.filename)
            try item.content.write(to: fileURL, atomically: true, encoding: .utf8)
            return SentTransferredFile(fileURL)
        }
    }

    let content: String
    let filename: String
}

// MARK: - ADIFDocument

/// FileDocument wrapper for ADIF export to Files app
struct ADIFDocument: FileDocument {
    // MARK: Lifecycle

    init(content: String) {
        self.content = content
    }

    init(configuration: ReadConfiguration) throws {
        if let data = configuration.file.regularFileContents {
            content = String(data: data, encoding: .utf8) ?? ""
        } else {
            content = ""
        }
    }

    // MARK: Internal

    static var readableContentTypes: [UTType] {
        [ADIFFileType.utType]
    }

    let content: String

    func fileWrapper(configuration _: WriteConfiguration) throws -> FileWrapper {
        let data = content.data(using: .utf8) ?? Data()
        return FileWrapper(regularFileWithContents: data)
    }
}

// MARK: - UploadDetailRow

struct UploadDetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
    }
}

// MARK: - POTAUploadInstructionsCard

struct POTAUploadInstructionsCard: View {
    // MARK: Internal

    let onGotIt: () -> Void
    let onShowNextTime: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("How to Upload to POTA", systemImage: "info.circle.fill")
                .font(.headline)
                .foregroundStyle(.green)

            VStack(alignment: .leading, spacing: 10) {
                step(1, "Tap **Save to Files** and save the ADIF somewhere easy to find.")
                step(2, "Tap **Upload to POTA** to open the POTA logs page.")
                step(3, "**Turn your phone to landscape** and **pinch to zoom out**.")
                step(4, "Tap **Choose File**, find your saved ADIF, and submit.")
            }

            HStack {
                Button {
                    onGotIt()
                } label: {
                    Text("Got It")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)

                Button {
                    onShowNextTime()
                } label: {
                    Text("Show Next Time")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: Private

    private func step(_ number: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle()
                    .fill(.green.opacity(0.15))
                    .frame(width: 28, height: 28)
                Text("\(number)")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.green)
            }
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
