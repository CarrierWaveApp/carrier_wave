import CarrierWaveData
import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - SessionDebugInfoSheet

/// Sheet that generates a `SessionDebugReport` for a session and exposes
/// share / save-to-files / copy-to-clipboard actions so the user can send the
/// report to support.
struct SessionDebugInfoSheet: View {
    // MARK: Internal

    let session: LoggingSession
    let qsos: [QSO]
    let activationMetadata: ActivationMetadata?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    headerCard
                    if let report {
                        includesCard
                        previewCard(report: report)
                    }
                }
                .padding(.horizontal)
            }
            .safeAreaInset(edge: .bottom) {
                footer
            }
            .navigationTitle("Send Debug Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                await generate()
            }
        }
        .landscapeAdaptiveDetents(portrait: [.medium, .large])
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var report: SessionDebugReport?
    @State private var isGenerating = false
    @State private var copiedToClipboard = false
    @State private var savedSuccessfully = false
    @State private var showFileSaver = false
    @State private var errorMessage: String?

    private var headerCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "ladybug")
                .font(.system(size: 36))
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(session.customTitle ?? session.myCallsign)
                    .font(.title3)
                    .fontWeight(.bold)
                Text("\(qsos.count) QSO\(qsos.count == 1 ? "" : "s") • \(session.programsDisplayName)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var includesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Report Includes")
                .font(.headline)
            bullet("Session metadata, equipment, and conditions")
            bullet("All \(qsos.count) QSOs with service sync state")
            bullet("Session spots (RBN / POTA)")
            bullet("Activation metadata (if any)")
            bullet("Recent sync debug log entries")
            bullet("Generated ADIF export")
            bullet("App version, device, and operator callsigns")
            Text("Sensitive: callsigns, park references, and notes are included.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    private var footer: some View {
        VStack(spacing: 12) {
            if isGenerating {
                ProgressView()
                    .scaleEffect(1.2)
                Text("Gathering debug info...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if let report {
                shareButton(report: report)
                saveToFilesButton(report: report)
                copyButton(report: report)
            } else if let errorMessage {
                Text(errorMessage)
                    .font(.subheadline)
                    .foregroundStyle(.red)
            }
        }
        .padding()
        .background(.bar)
        .fileExporter(
            isPresented: $showFileSaver,
            document: report.map { DebugReportDocument(content: $0.combinedText) },
            contentType: .plainText,
            defaultFilename: report.map { "\($0.filenameStem).txt" } ?? "debug.txt"
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

    private func previewCard(report: SessionDebugReport) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Preview")
                .font(.headline)
            ScrollView(.horizontal, showsIndicators: true) {
                Text(report.summary.prefix(2_000))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(nil)
            }
            .frame(maxHeight: 220)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    private func shareButton(report: SessionDebugReport) -> some View {
        ShareLink(
            item: ShareableDebugReport(
                content: report.combinedText,
                filename: "\(report.filenameStem).txt"
            ),
            preview: SharePreview(
                "\(report.filenameStem).txt",
                image: Image(systemName: "ladybug")
            )
        ) {
            Label("Share Debug Info", systemImage: "square.and.arrow.up")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }

    private func saveToFilesButton(report _: SessionDebugReport) -> some View {
        Button {
            showFileSaver = true
        } label: {
            Label(
                savedSuccessfully ? "Saved" : "Save to Files",
                systemImage: savedSuccessfully ? "checkmark" : "folder"
            )
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
    }

    private func copyButton(report: SessionDebugReport) -> some View {
        Button {
            UIPasteboard.general.string = report.combinedText
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

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("•").foregroundStyle(.secondary)
            Text(text).font(.subheadline)
        }
    }

    private func generate() async {
        guard report == nil else {
            return
        }
        isGenerating = true
        errorMessage = nil
        try? await Task.sleep(for: .milliseconds(100))
        let built = await SessionDebugInfoService.buildReport(
            session: session,
            qsos: qsos,
            activationMetadata: activationMetadata,
            modelContext: modelContext
        )
        report = built
        isGenerating = false
    }
}

// MARK: - ShareableDebugReport

struct ShareableDebugReport: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .plainText) { item in
            let dir = FileManager.default.temporaryDirectory
            let url = dir.appendingPathComponent(item.filename)
            try item.content.write(to: url, atomically: true, encoding: .utf8)
            return SentTransferredFile(url)
        }
    }

    let content: String
    let filename: String
}

// MARK: - DebugReportDocument

struct DebugReportDocument: FileDocument {
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
        [.plainText]
    }

    static var writableContentTypes: [UTType] {
        [.plainText]
    }

    let content: String

    func fileWrapper(configuration _: WriteConfiguration) throws -> FileWrapper {
        let data = content.data(using: .utf8) ?? Data()
        return FileWrapper(regularFileWithContents: data)
    }
}
