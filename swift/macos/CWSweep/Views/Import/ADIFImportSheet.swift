// ADIF Import Sheet
//
// macOS sheet for importing ADIF files into CW Sweep.
// Provides file picker, progress tracking, and import results.

import CarrierWaveData
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

// MARK: - ADIFImportSheet

struct ADIFImportSheet: View {
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
        .frame(width: 460, height: 340)
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: adifContentTypes,
            allowsMultipleSelection: false
        ) { pickerResult in
            handleFileSelection(pickerResult)
        }
    }

    // MARK: Private

    @AppStorage("myCallsign") private var myCallsign = ""

    @State private var showFilePicker = false
    @State private var isImporting = false
    @State private var selectedFileURL: URL?
    @State private var selectedFileName: String?
    @State private var importResult: ADIFImportResult?
    @State private var errorMessage: String?
    @State private var progress: ADIFImportProgressInfo?

    private var adifContentTypes: [UTType] {
        let adiType = UTType("org.adif.adi")
            ?? UTType(filenameExtension: "adi", conformingTo: .data)!
        let adifType = UTType(filenameExtension: "adif", conformingTo: .data)!
        return [adiType, adifType, .plainText]
    }

    private var progressFraction: Double {
        guard let progress, progress.total > 0 else {
            return 0
        }
        return Double(progress.processed) / Double(progress.total)
    }

    private var headerSection: some View {
        HStack(spacing: 12) {
            Image(systemName: "square.and.arrow.down")
                .font(.system(size: 28))
                .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: 2) {
                Text("Import ADIF")
                    .font(.headline)
                Text("Import QSOs from an ADIF file into your log")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding()
    }

    @ViewBuilder
    private var contentSection: some View {
        if let result = importResult {
            importResultView(result)
        } else if isImporting {
            importProgressView
        } else if let errorMessage {
            importErrorView(errorMessage)
        } else {
            fileSelectionView
        }
    }

    private var fileSelectionView: some View {
        VStack(spacing: 16) {
            Spacer()

            if let fileName = selectedFileName {
                Label(fileName, systemImage: "doc.text")
                    .font(.body)

                Button("Import") {
                    Task { await runImport() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(myCallsign.isEmpty)

                if myCallsign.isEmpty {
                    Text("Set your callsign in Settings first")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } else {
                Image(systemName: "doc.badge.plus")
                    .font(.system(size: 44))
                    .foregroundStyle(.secondary)

                Text("Select an ADIF file to import")
                    .foregroundStyle(.secondary)

                Button("Choose File...") {
                    showFilePicker = true
                }
                .buttonStyle(.borderedProminent)
            }

            Spacer()
        }
        .padding()
    }

    private var importProgressView: some View {
        VStack(spacing: 12) {
            Spacer()

            ProgressView(value: progressFraction)
                .progressViewStyle(.linear)

            if let progress {
                Text("Importing \(progress.processed) of \(progress.total) records...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("Parsing ADIF file...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding()
    }

    private var footerSection: some View {
        HStack {
            if importResult == nil, !isImporting, errorMessage == nil,
               selectedFileName != nil
            {
                Button("Choose Different File") {
                    showFilePicker = true
                }
                .buttonStyle(.bordered)
            }

            Spacer()

            Button(importResult != nil ? "Done" : "Cancel") {
                dismiss()
            }
            .keyboardShortcut(importResult != nil ? .defaultAction : .cancelAction)
        }
        .padding()
    }

    private func importResultView(_ result: ADIFImportResult) -> some View {
        VStack(spacing: 12) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.green)

            Text("Import Complete")
                .font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                GridRow {
                    Text("Total records:").foregroundStyle(.secondary)
                    Text("\(result.totalRecords)").monospacedDigit()
                }
                GridRow {
                    Text("Imported:").foregroundStyle(.secondary)
                    Text("\(result.imported)")
                        .monospacedDigit()
                        .foregroundStyle(.green)
                }
                GridRow {
                    Text("Duplicates skipped:").foregroundStyle(.secondary)
                    Text("\(result.duplicates)")
                        .monospacedDigit()
                        .foregroundStyle(.orange)
                }
                if result.errors > 0 {
                    GridRow {
                        Text("Errors:").foregroundStyle(.secondary)
                        Text("\(result.errors)")
                            .monospacedDigit()
                            .foregroundStyle(.red)
                    }
                }
            }

            Spacer()
        }
        .padding()
    }

    private func importErrorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Spacer()

            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.red)

            Text("Import Failed")
                .font(.headline)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Try Again") {
                errorMessage = nil
                selectedFileURL = nil
                selectedFileName = nil
            }
            .buttonStyle(.bordered)

            Spacer()
        }
        .padding()
    }

    private func handleFileSelection(
        _ result: Result<[URL], Error>
    ) {
        switch result {
        case let .success(urls):
            guard let url = urls.first else {
                return
            }
            selectedFileURL = url
            selectedFileName = url.lastPathComponent
        case let .failure(error):
            errorMessage = error.localizedDescription
        }
    }

    private func runImport() async {
        guard let fileURL = selectedFileURL else {
            return
        }

        isImporting = true
        errorMessage = nil
        progress = nil

        let actor = ADIFImportActor()
        do {
            guard fileURL.startAccessingSecurityScopedResource() else {
                throw ADIFImportError.invalidFile
            }
            defer { fileURL.stopAccessingSecurityScopedResource() }

            importResult = try await actor.importADIF(
                from: fileURL,
                myCallsign: myCallsign,
                container: modelContext.container
            ) { info in
                Task { @MainActor in
                    progress = info
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isImporting = false
    }
}
