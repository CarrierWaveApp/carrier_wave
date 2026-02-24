// ADIF Export Sheet
//
// Sheet view for exporting activation QSOs to ADIF format.
// Provides share, save to files, and copy to clipboard options.

import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - ADIFExportSheet

struct ADIFExportSheet: View {
    // MARK: Internal

    let activation: POTAActivation
    let parkName: String?

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

                    // Details
                    VStack(spacing: 12) {
                        UploadDetailRow(label: "Date", value: activation.displayDate)
                        UploadDetailRow(label: "Callsign", value: activation.callsign)
                        UploadDetailRow(label: "QSOs", value: "\(activation.qsoCount)")
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

    @Environment(\.dismiss) private var dismiss

    @State private var isGenerating = false
    @State private var exportResult: ADIFExportResult?
    @State private var errorMessage: String?
    @State private var showFileSaver = false
    @State private var copiedToClipboard = false
    @State private var savedSuccessfully = false

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

    private func shareButton(result: ADIFExportResult) -> some View {
        ShareLink(
            item: ShareableADIF(content: result.content, filename: result.filename),
            preview: SharePreview(result.filename, image: Image(systemName: "doc.text"))
        ) {
            Label("Share ADIF", systemImage: "square.and.arrow.up")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
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

        // Small delay to let sheet animation complete before processing
        try? await Task.sleep(for: .milliseconds(100))

        // Capture values needed for background processing
        let parkRef = activation.parkReference
        let callsign = activation.callsign
        let date = activation.utcDate
        let qsoCount = activation.qsoCount
        let qsos = activation.qsos

        // Create snapshots in batches to avoid blocking UI
        var snapshots: [QSOExportSnapshot] = []
        snapshots.reserveCapacity(qsos.count)
        for (index, qso) in qsos.enumerated() {
            snapshots.append(QSOExportSnapshot(from: qso))
            // Yield every 50 QSOs to keep UI responsive
            if index % 50 == 49 {
                await Task.yield()
            }
        }

        let service = ADIFExportService()

        let content = await service.generateADIF(
            for: snapshots,
            parkReference: parkRef,
            parkName: parkName,
            activatorCallsign: callsign
        )

        let filename = await service.generateFilename(
            parkReference: parkRef,
            activatorCallsign: callsign,
            date: date
        )

        exportResult = ADIFExportResult(
            content: content,
            filename: filename,
            qsoCount: qsoCount
        )
        isGenerating = false
    }
}

// MARK: - ADIFFileType

/// ADIF file type helper - enum to avoid MainActor isolation on static property
enum ADIFFileType {
    /// ADIF UTType - prefer registered type from Info.plist, fall back to runtime declaration
    nonisolated static let utType = UTType("org.adif.adi")
        ?? UTType(filenameExtension: "adi", conformingTo: .data)!
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
