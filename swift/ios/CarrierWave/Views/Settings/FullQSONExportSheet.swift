// Full QSON Export Sheet
//
// Sheet view for exporting the entire QSO log to a single QSON file.
// Mirrors FullADIFExportSheet with determinate progress and streaming.

import CarrierWaveData
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

// MARK: - FullQSONExportSheet

struct FullQSONExportSheet: View {
    // MARK: Internal

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    header
                    if let result {
                        detailRows(result: result)
                    }
                }
                .padding(.horizontal)
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 12) {
                    if isGenerating {
                        progressSection
                    } else if let result {
                        actionButtons(result: result)
                    } else if let errorMessage {
                        errorView(message: errorMessage)
                    }
                }
                .padding()
                .background(.bar)
            }
            .navigationTitle("Export QSON")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .fileExporter(
                isPresented: $showFileSaver,
                document: fileDocument,
                contentType: QSONFileType.utType,
                defaultFilename: result?.filename ?? "carrierwave_export.qson"
            ) { exportResult in
                switch exportResult {
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
        .task { await runExport() }
    }

    // MARK: Private

    private static let clipboardMaxBytes: Int64 = 5 * 1_024 * 1_024

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var isGenerating = false
    @State private var result: FullExportResult?
    @State private var progress: FullExportProgressInfo?
    @State private var errorMessage: String?
    @State private var showFileSaver = false
    @State private var copiedToClipboard = false
    @State private var savedSuccessfully = false

    private var progressFraction: Double {
        guard let progress, progress.total > 0 else {
            return 0
        }
        return Double(progress.processed) / Double(progress.total)
    }

    private var fileDocument: QSONFileExportDocument? {
        result.map { QSONFileExportDocument(fileURL: $0.fileURL) }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.text")
                .font(.system(size: 36))
                .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: 2) {
                Text("Full QSO Log")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Export all QSOs as QSON")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var progressSection: some View {
        VStack(spacing: 8) {
            ProgressView(value: progressFraction)
            if let progress {
                Text("Exporting \(progress.processed) of \(progress.total) QSOs...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("Preparing export...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func detailRows(result: FullExportResult) -> some View {
        VStack(spacing: 12) {
            UploadDetailRow(
                label: "QSO Count",
                value: result.qsoCount.formatted()
            )
            UploadDetailRow(
                label: "File Size",
                value: ByteCountFormatter.string(
                    fromByteCount: result.fileSizeBytes,
                    countStyle: .file
                )
            )
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    @ViewBuilder
    private func actionButtons(result: FullExportResult) -> some View {
        ShareLink(
            item: result.fileURL,
            preview: SharePreview(
                result.filename,
                image: Image(systemName: "doc.text")
            )
        ) {
            Label("Share QSON", systemImage: "square.and.arrow.up")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)

        Button {
            showFileSaver = true
        } label: {
            Label("Save to Files", systemImage: "folder")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)

        if result.fileSizeBytes <= Self.clipboardMaxBytes {
            Button {
                copyToClipboard(fileURL: result.fileURL)
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
                Task { await runExport() }
            }
            .buttonStyle(.bordered)
        }
    }

    private func runExport() async {
        isGenerating = true
        errorMessage = nil
        try? await Task.sleep(for: .milliseconds(100))

        let actor = FullQSONExportActor()
        do {
            result = try await actor.exportAllQSOs(
                container: modelContext.container
            ) { info in
                Task { @MainActor in
                    progress = info
                }
            }
        } catch {
            errorMessage = "Export failed: \(error.localizedDescription)"
        }
        isGenerating = false
    }

    private func copyToClipboard(fileURL: URL) {
        guard let data = try? Data(contentsOf: fileURL),
              let content = String(data: data, encoding: .utf8)
        else {
            return
        }
        UIPasteboard.general.string = content
        copiedToClipboard = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            copiedToClipboard = false
        }
    }
}

// MARK: - QSONFileType

enum QSONFileType {
    nonisolated static let utType = UTType(
        filenameExtension: "qson", conformingTo: .json
    )!
}

// MARK: - QSONFileExportDocument

struct QSONFileExportDocument: FileDocument {
    // MARK: Lifecycle

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    init(configuration: ReadConfiguration) throws {
        fileURL = nil
        data = configuration.file.regularFileContents ?? Data()
    }

    // MARK: Internal

    static var readableContentTypes: [UTType] {
        [QSONFileType.utType]
    }

    func fileWrapper(configuration _: WriteConfiguration) throws -> FileWrapper {
        let contents: Data = if let fileURL {
            try Data(contentsOf: fileURL)
        } else {
            data ?? Data()
        }
        return FileWrapper(regularFileWithContents: contents)
    }

    // MARK: Private

    private let fileURL: URL?
    private var data: Data?
}
