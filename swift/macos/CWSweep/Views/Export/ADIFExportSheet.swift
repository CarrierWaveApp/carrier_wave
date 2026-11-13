// ADIF Export Sheet (macOS)
//
// Sheet for exporting the full QSO log as ADIF. Uses FullADIFExportActor
// for streaming large logs to temp file, then presents NSSavePanel.

import AppKit
import CarrierWaveData
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

// MARK: - ADIFExportSheet

struct ADIFExportSheet: View {
    // MARK: Internal

    @Environment(\.dismiss) var dismiss
    @Environment(\.modelContext) var modelContext

    var body: some View {
        VStack(spacing: 0) {
            headerSection
            Divider()
            contentSection
            Divider()
            footerSection
        }
        .frame(width: 420, height: 280)
        .task { await runExport() }
    }

    // MARK: Private

    @State private var isExporting = false
    @State private var exportResult: FullExportResult?
    @State private var progress: FullExportProgressInfo?
    @State private var errorMessage: String?
    @State private var savedSuccessfully = false

    private var progressFraction: Double {
        guard let progress, progress.total > 0 else {
            return 0
        }
        return Double(progress.processed) / Double(progress.total)
    }

    private var headerSection: some View {
        HStack(spacing: 12) {
            Image(systemName: "archivebox")
                .font(.system(size: 28))
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 2) {
                Text("Export ADIF")
                    .font(.headline)
                Text("Export all QSOs as an ADIF file")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding()
    }

    @ViewBuilder
    private var contentSection: some View {
        if savedSuccessfully {
            savedView
        } else if let result = exportResult {
            exportResultView(result)
        } else if isExporting {
            exportProgressView
        } else if let errorMessage {
            exportErrorView(errorMessage)
        } else {
            preparingView
        }
    }

    private var preparingView: some View {
        VStack(spacing: 12) {
            Spacer()
            ProgressView()
            Text("Preparing export...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding()
    }

    private var exportProgressView: some View {
        VStack(spacing: 12) {
            Spacer()

            ProgressView(value: progressFraction)
                .progressViewStyle(.linear)

            if let progress {
                Text("Exporting \(progress.processed) of \(progress.total) QSOs...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding()
    }

    private var savedView: some View {
        VStack(spacing: 12) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.green)

            Text("File Saved")
                .font(.headline)

            Spacer()
        }
        .padding()
    }

    private var footerSection: some View {
        HStack {
            Spacer()

            if let result = exportResult, !savedSuccessfully {
                Button("Save As...") {
                    saveFile(result: result)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }

            Button(savedSuccessfully ? "Done" : "Cancel") {
                dismiss()
            }
            .keyboardShortcut(savedSuccessfully ? .defaultAction : .cancelAction)
        }
        .padding()
    }

    private func exportResultView(
        _ result: FullExportResult
    ) -> some View {
        VStack(spacing: 12) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.green)

            Text("Export Ready")
                .font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                GridRow {
                    Text("QSOs:").foregroundStyle(.secondary)
                    Text("\(result.qsoCount)").monospacedDigit()
                }
                GridRow {
                    Text("File size:").foregroundStyle(.secondary)
                    Text(ByteCountFormatter.string(
                        fromByteCount: result.fileSizeBytes,
                        countStyle: .file
                    ))
                }
            }

            Spacer()
        }
        .padding()
    }

    private func exportErrorView(
        _ message: String
    ) -> some View {
        VStack(spacing: 12) {
            Spacer()

            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.red)

            Text("Export Failed")
                .font(.headline)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Try Again") {
                errorMessage = nil
                Task { await runExport() }
            }
            .buttonStyle(.bordered)

            Spacer()
        }
        .padding()
    }

    private func runExport() async {
        isExporting = true
        errorMessage = nil
        progress = nil

        let config = ADIFExportConfig(
            appName: "CWSweep",
            filenamePrefix: "cwsweep_full_export",
            appFieldPrefix: "APP_CWSWEEP"
        )
        let actor = FullADIFExportActor(config: config)
        do {
            exportResult = try await actor.exportAllQSOs(
                container: modelContext.container
            ) { info in
                Task { @MainActor in
                    progress = info
                }
            }
        } catch {
            errorMessage = "Export failed: \(error.localizedDescription)"
        }
        isExporting = false
    }

    private func saveFile(result: FullExportResult) {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [
            UTType("org.adif.adi")
                ?? UTType(filenameExtension: "adi", conformingTo: .data)!,
        ]
        savePanel.nameFieldStringValue = result.filename
        savePanel.title = "Save ADIF Export"
        savePanel.message = "Choose where to save your ADIF export"

        savePanel.begin { response in
            guard response == .OK, let destURL = savePanel.url else {
                return
            }
            do {
                try FileManager.default.copyItem(
                    at: result.fileURL, to: destURL
                )
                savedSuccessfully = true
            } catch {
                errorMessage = "Failed to save: \(error.localizedDescription)"
            }
        }
    }
}
