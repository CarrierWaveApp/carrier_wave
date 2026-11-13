// Bulk ADIF Export Sheet
//
// Exports ADIF for multiple selected POTA activations. Two modes:
//  - Combined: one ADIF containing every selected activation (parks written
//    as logged, so n-fers keep their comma-separated refs).
//  - Split by Park: one ADIF per park activated, with that park as the ONLY
//    park in the file. N-fer QSOs fan out into each of their parks.

import CarrierWaveCwFfi
import CarrierWaveData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - BulkADIFExportMode

enum BulkADIFExportMode: String, CaseIterable, Identifiable {
    case combined
    case splitByPark

    // MARK: Internal

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .combined: "Combined"
        case .splitByPark: "Split by Park"
        }
    }
}

// MARK: - BulkADIFExportSheet

/// Sheet for exporting ADIF from multiple activations, combined or split per park.
struct BulkADIFExportSheet: View {
    // MARK: Internal

    let activations: [POTAActivation]
    let parkNames: [String: String]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    headerSection
                    modePicker
                    detailsSection
                    if mode == .splitByPark, !splitFiles.isEmpty {
                        splitFilesSection
                    }
                }
                .padding(.horizontal)
            }
            .safeAreaInset(edge: .bottom) {
                bottomBar
            }
            .navigationTitle("Export ADIF")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .fileExporter(
                isPresented: $showFileSaver,
                document: exportResult.map { ADIFDocument(content: $0.content) },
                contentType: ADIFFileType.utType,
                defaultFilename: exportResult?.filename ?? "bulk_export.adi"
            ) { result in
                if case let .failure(error) = result {
                    errorMessage = "Failed to save: \(error.localizedDescription)"
                }
            }
        }
        .landscapeAdaptiveDetents(portrait: [.medium, .large])
        .task { await generate() }
    }

    // MARK: Private

    /// App marketing version passed to the ADIF header (`PROGRAMVERSION`).
    private static var programVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    @Environment(\.dismiss) private var dismiss

    @State private var mode: BulkADIFExportMode = .combined
    @State private var isGenerating = false
    @State private var exportResult: ADIFExportResult?
    @State private var splitFiles: [SplitExportFile] = []
    @State private var errorMessage: String?
    @State private var showFileSaver = false
    @State private var copiedToClipboard = false

    private var totalQSOs: Int {
        activations.reduce(0) { $0 + $1.qsoCount }
    }

    private var uniqueParks: [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for activation in activations {
            for park in activation.parks where seen.insert(park).inserted {
                ordered.append(park)
            }
        }
        return ordered.sorted()
    }

    // MARK: - Sections

    private var headerSection: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.text")
                .font(.system(size: 36))
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(activations.count) Activations")
                    .font(.title2)
                    .fontWeight(.bold)
                Text(mode == .splitByPark ? "One ADIF per park" : "Combined ADIF export")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var modePicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Export Mode", selection: $mode) {
                ForEach(BulkADIFExportMode.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: mode) {
                Task { await generate() }
            }
            Text(
                mode == .splitByPark
                    ? "Creates \(uniqueParks.count) file\(uniqueParks.count == 1 ? "" : "s") "
                    + "— one per park, each listing only that park."
                    : "Creates a single file with all selected activations."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var detailsSection: some View {
        VStack(spacing: 12) {
            UploadDetailRow(label: "Total QSOs", value: "\(totalQSOs)")
            UploadDetailRow(label: "Activations", value: "\(activations.count)")
            UploadDetailRow(
                label: "Parks",
                value: uniqueParks.joined(separator: ", ")
            )
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    private var splitFilesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(splitFiles.count) Files")
                .font(.headline)
            ForEach(splitFiles) { file in
                splitFileRow(file)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        VStack(spacing: 12) {
            if isGenerating {
                ProgressView().scaleEffect(1.2)
                Text("Generating ADIF...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if mode == .splitByPark {
                splitActions
            } else if let exportResult {
                combinedActions(result: exportResult)
            } else if let errorMessage {
                Text(errorMessage)
                    .font(.subheadline)
                    .foregroundStyle(.red)
            }
        }
        .padding()
        .background(.bar)
    }

    @ViewBuilder
    private var splitActions: some View {
        if !splitFiles.isEmpty {
            Button {
                shareAllSplitFiles()
            } label: {
                Label("Share All (\(splitFiles.count) files)", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        } else if let errorMessage {
            Text(errorMessage)
                .font(.subheadline)
                .foregroundStyle(.red)
        }
    }

    private func splitFileRow(_ file: SplitExportFile) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(file.parkReference ?? file.filename)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Text("\(file.qsoCount) QSOs")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            ShareLink(
                item: ShareableADIF(content: file.content, filename: file.filename),
                preview: SharePreview(file.filename, image: Image(systemName: "doc.text"))
            ) {
                Image(systemName: "square.and.arrow.up")
            }
        }
    }

    @ViewBuilder
    private func combinedActions(result: ADIFExportResult) -> some View {
        ShareLink(
            item: ShareableADIF(content: result.content, filename: result.filename),
            preview: SharePreview(result.filename, image: Image(systemName: "doc.text"))
        ) {
            Label("Share ADIF", systemImage: "square.and.arrow.up")
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

    // MARK: - Generation

    @MainActor
    private func generate() async {
        isGenerating = true
        errorMessage = nil
        defer { isGenerating = false }

        try? await Task.sleep(for: .milliseconds(100))

        switch mode {
        case .combined:
            await generateCombined()
        case .splitByPark:
            await generateSplit()
        }
    }

    @MainActor
    private func generateCombined() async {
        splitFiles = []

        // One combined ADIF over every selected activation, written by the
        // shared Rust AdifApi. Each activation is (park, callsign, UTC day);
        // the writer re-scopes the QSOs from the FieldStore, parks written as
        // logged (n-fers keep their comma-separated refs).
        let refs = activations.map { activation in
            FfiAdifBulkActivationRef(
                parkReference: activation.parkReference,
                parkName: parkNames[activation.parkReference.uppercased()],
                callsign: activation.callsign,
                date: activation.utcDateString
            )
        }
        let firstDate = activations.first?.utcDate ?? Date()
        let count = activations.count
        let qsoTotal = totalQSOs

        do {
            let store = try await CwStoreProvider.shared.store()
            let api = AdifApi(store: store)
            let version = Self.programVersion
            let content = try await Task.detached {
                try api.exportBulk(activations: refs, programVersion: version)
            }.value
            let filename = await ADIFExportService().generateBulkFilename(
                activationCount: count,
                date: firstDate
            )
            exportResult = ADIFExportResult(
                content: content, filename: filename, qsoCount: qsoTotal
            )
        } catch {
            errorMessage = "Failed to generate ADIF: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func generateSplit() async {
        exportResult = nil
        let snapshots = activations.flatMap { makeSnapshots(from: $0.qsos) }
        guard !snapshots.isEmpty else {
            errorMessage = "No QSOs to export"
            splitFiles = []
            return
        }
        let config = makeBulkSplitConfig(
            snapshots: snapshots,
            callsign: activations.first?.callsign ?? "",
            parkNames: parkNames
        )
        let service = ADIFExportService()
        splitFiles = await service.generateSplitADIF(for: config)
    }

    @MainActor
    private func makeSnapshots(from qsos: [QSO]) -> [QSOExportSnapshot] {
        var snapshots: [QSOExportSnapshot] = []
        snapshots.reserveCapacity(qsos.count)
        for qso in qsos {
            snapshots.append(QSOExportSnapshot(from: qso))
        }
        return snapshots
    }

    @MainActor
    private func shareAllSplitFiles() {
        shareADIFFiles(splitFiles.map { ($0.filename, $0.content) })
    }
}
