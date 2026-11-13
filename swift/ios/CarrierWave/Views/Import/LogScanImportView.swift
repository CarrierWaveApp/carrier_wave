import CarrierWaveCore
import CarrierWaveData
import PhotosUI
import SwiftData
import SwiftUI

// MARK: - LogScanImportView

/// Coordinator view managing the full log scanning flow:
/// Source Selection → Camera/Library → Config → OCR Processing → Review → Import
struct LogScanImportView: View {
    // MARK: Internal

    @Environment(\.dismiss) var dismiss
    @Environment(\.modelContext) var modelContext

    var body: some View {
        switch phase {
        case .sourceSelection:
            sourceSelectionView
        case .scanning:
            LogScannerView(
                onScanComplete: { images in
                    scannedImages = images
                    phase = .configuring
                },
                onCancel: { dismiss() }
            )
        case .configuring:
            ScanConfigSheet(
                rstOrder: $rstOrder,
                defaultDate: $defaultDate,
                myCallsign: $myCallsign,
                images: $scannedImages,
                onProcess: processScans,
                onCancel: { dismiss() }
            )
        case .processing:
            processingView
        case .reviewing:
            ScanReviewView(
                rows: $scannedRows,
                images: scannedImages,
                myCallsign: myCallsign,
                rstOrder: rstOrder,
                onImport: importRows,
                onCancel: { dismiss() }
            )
        case .importing:
            importingView
        case .done:
            EmptyView()
        }
    }

    // MARK: Private

    private enum Phase {
        case sourceSelection
        case scanning
        case configuring
        case processing
        case reviewing
        case importing
        case done
    }

    private struct ImportResult {
        let imported: Int
        let skipped: Int
    }

    @State private var phase: Phase = .sourceSelection
    @State private var scannedImages: [UIImage] = []
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var isLoadingPhotos = false
    @State private var scannedRows: [ScannedQSORow] = []
    @State private var rstOrder: RSTOrder = {
        let raw = UserDefaults.standard.string(forKey: "rstParseOrder") ?? ""
        return RSTOrder(rawValue: raw) ?? .receivedFirst
    }()

    @State private var defaultDate = Date()
    @State private var myCallsign: String =
        CallsignAliasService.shared.getCurrentCallsign() ?? ""
    @State private var processingProgress = 0.0
    @State private var importResult: ImportResult?
    @State private var importError: String?
    @State private var showResultAlert = false
    @State private var showErrorAlert = false

    private var sourceSelectionView: some View {
        NavigationStack {
            List {
                Button {
                    phase = .scanning
                } label: {
                    Label("Scan with Camera", systemImage: "doc.viewfinder")
                }

                PhotosPicker(
                    selection: $selectedPhotos,
                    maxSelectionCount: 20,
                    matching: .images
                ) {
                    Label("Choose from Photo Library", systemImage: "photo.on.rectangle")
                }
                .disabled(isLoadingPhotos)
                .onChange(of: selectedPhotos) {
                    guard !selectedPhotos.isEmpty else {
                        return
                    }
                    loadSelectedPhotos()
                }
            }
            .navigationTitle("Scan Log Pages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isLoadingPhotos)
                }
            }
            .overlay {
                if isLoadingPhotos {
                    ZStack {
                        Color(.systemBackground).opacity(0.8)
                        VStack(spacing: 12) {
                            ProgressView()
                            Text("Loading images...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private var processingView: some View {
        VStack(spacing: 20) {
            ProgressView("Scanning pages...", value: processingProgress)
                .padding()
            Text("Recognizing handwriting with on-device OCR")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var importingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Importing QSOs...")
                .font(.headline)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .alert("Import Complete", isPresented: $showResultAlert) {
            Button("OK") { dismiss() }
        } message: {
            if let result = importResult {
                Text("\(result.imported) QSOs imported, \(result.skipped) skipped")
            }
        }
        .alert("Import Failed", isPresented: $showErrorAlert) {
            Button("OK") { dismiss() }
        } message: {
            Text(importError ?? "Unknown error")
        }
    }

    private func loadSelectedPhotos() {
        isLoadingPhotos = true
        let items = selectedPhotos
        Task {
            var images: [UIImage] = []
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data)
                {
                    images.append(image)
                }
            }
            scannedImages = images
            selectedPhotos = []
            isLoadingPhotos = false
            if !images.isEmpty {
                phase = .configuring
            }
        }
    }

    private func processScans() {
        phase = .processing
        Task {
            do {
                let cgImages = scannedImages.compactMap(\.cgImage)
                let totalPages = Double(cgImages.count)

                var allRows: [ScannedQSORow] = []
                var lastDateComponents: DateComponents?

                for (index, image) in cgImages.enumerated() {
                    let pageRows = try await LogPageScanner.scanPage(
                        image: image,
                        rstOrder: rstOrder,
                        defaultDate: defaultDate,
                        previousDateComponents: lastDateComponents
                    )
                    if let lastRow = pageRows.last {
                        lastDateComponents = lastRow.dateComponents
                    }
                    allRows.append(contentsOf: pageRows)
                    processingProgress = Double(index + 1) / totalPages
                }

                scannedRows = allRows
                phase = .reviewing
            } catch {
                importError = error.localizedDescription
                showErrorAlert = true
            }
        }
    }

    private func importRows(_ rows: [ScannedQSORow]) {
        phase = .importing
        Task {
            do {
                let result = try await createQSOs(from: rows)
                importResult = result
                showResultAlert = true
            } catch {
                importError = error.localizedDescription
                showErrorAlert = true
            }
        }
    }

    private func createQSOs(from rows: [ScannedQSORow]) async throws -> ImportResult {
        var imported = 0
        var skipped = 0

        for row in rows {
            guard let result = row.parseResult, !result.callsign.isEmpty else {
                skipped += 1
                continue
            }

            let qso = QSO(
                callsign: result.callsign,
                band: result.band ?? "",
                mode: result.mode ?? "",
                timestamp: row.timestamp ?? defaultDate,
                myCallsign: myCallsign.uppercased(),
                importSource: .scanned
            )
            qso.frequency = result.frequency ?? 0
            qso.rstSent = result.rstSent
            qso.rstReceived = result.rstReceived
            qso.state = result.state
            qso.theirParkReference = result.theirPark
            qso.theirGrid = result.theirGrid
            qso.notes = result.notes
            // OCR scan import is user-reviewed before save — tag as user-authored. CAR-243.
            if result.notes?.isEmpty == false {
                qso.notesUserAuthored = true
            }

            modelContext.insert(qso)
            imported += 1
        }

        try modelContext.save()

        return ImportResult(imported: imported, skipped: skipped)
    }
}
