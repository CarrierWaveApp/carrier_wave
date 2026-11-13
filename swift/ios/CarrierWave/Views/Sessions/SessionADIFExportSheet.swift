// Session ADIF Export Sheet
//
// A program-agnostic sheet for exporting a single LoggingSession's QSOs to
// ADIF. POTA-only sessions still go through the activation-keyed
// ADIFExportSheet (it carries POTA upload helpers). This sheet covers SOTA
// sessions, dual POTA+SOTA sessions, and casual sessions where the
// activation-keyed sheet doesn't apply.
//
// The shape is intentionally close to ADIFExportSheet — same buttons,
// progress UI, FileExporter — minus the POTA upload prompt and re-using the
// existing ShareableADIF / ADIFDocument transferables defined there.

import CarrierWaveData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - SessionADIFExportSheet

struct SessionADIFExportSheet: View {
    // MARK: Internal

    let session: LoggingSession
    let qsos: [QSO]
    var summitName: String?

    @State var flavoredResults: [LogSubmissionFlavor: ADIFExportResult] = [:]

    /// Programs detected on the session that we have a flavored exporter for.
    /// Drives the per-program "Submit to X" rows in the bottom bar.
    var availableFlavors: [LogSubmissionFlavor] {
        LogSubmissionFlavor.availableFlavors(in: session)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    headerSection
                    detailsCard
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
                defaultFilename: exportResult?.filename ?? "session.adi"
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

    var saveToFilesButton: some View {
        Button {
            showFileSaver = true
        } label: {
            Label("Save to Files", systemImage: "folder")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
    }

    func copyToClipboardButton(result: ADIFExportResult) -> some View {
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

    // MARK: Private

    private struct HeadlineLabels {
        let icon: String
        let code: String
        let name: String?
        let program: String
    }

    @Environment(\.dismiss) private var dismiss

    @State private var isGenerating = false
    @State private var exportResult: ADIFExportResult?
    @State private var errorMessage: String?
    @State private var showFileSaver = false
    @State private var copiedToClipboard = false
    @State private var savedSuccessfully = false

    /// Headline reference + program label. Prefer the SOTA summit because POTA
    /// sessions usually use the activation-keyed sheet; if both are set we
    /// label "POTA + SOTA" so the user sees both refs.
    private var headlineLabels: HeadlineLabels {
        if session.isPOTA, session.isSOTA {
            return HeadlineLabels(
                icon: "mountain.2.fill",
                code: session.sotaReference ?? session.parkReference ?? "",
                name: summitName,
                program: "POTA + SOTA"
            )
        }
        if session.isSOTA {
            return HeadlineLabels(
                icon: "mountain.2.fill",
                code: session.sotaReference ?? "",
                name: summitName,
                program: "SOTA"
            )
        }
        if session.isPOTA {
            return HeadlineLabels(
                icon: "tree.fill",
                code: session.parkReference ?? "",
                name: nil,
                program: "POTA"
            )
        }
        return HeadlineLabels(
            icon: "antenna.radiowaves.left.and.right",
            code: "",
            name: nil,
            program: "Session"
        )
    }

    private var dateString: String {
        let date = qsos.min(by: { $0.timestamp < $1.timestamp })?.timestamp ?? session.startedAt
        let df = DateFormatter()
        df.dateFormat = "MMMM d, yyyy"
        df.timeZone = TimeZone(identifier: "UTC")
        return df.string(from: date)
    }

    private var headerSection: some View {
        let labels = headlineLabels
        return HStack(spacing: 12) {
            Image(systemName: "doc.text")
                .font(.system(size: 36))
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(labels.code.isEmpty ? labels.program : labels.code)
                    .font(.title2)
                    .fontWeight(.bold)
                if let name = labels.name {
                    Text(name)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                } else if !labels.code.isEmpty {
                    Text(labels.program)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var detailsCard: some View {
        VStack(spacing: 12) {
            UploadDetailRow(label: "Date", value: dateString)
            UploadDetailRow(label: "Callsign", value: session.myCallsign)
            UploadDetailRow(label: "QSOs", value: "\(qsos.count)")
            UploadDetailRow(
                label: "Bands",
                value: Set(qsos.map(\.band)).sorted().joined(separator: ", ")
            )
            UploadDetailRow(
                label: "Modes",
                value: Set(qsos.map(\.mode)).sorted().joined(separator: ", ")
            )
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    private var bottomBar: some View {
        VStack(spacing: 12) {
            if isGenerating {
                ProgressView()
                    .scaleEffect(1.2)
                Text("Generating ADIF\u{2026}")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if let exportResult {
                flavorPullUp(combined: exportResult)
                saveToFilesButton
                copyToClipboardButton(result: exportResult)
            } else if let errorMessage {
                errorView(message: errorMessage)
            }
        }
        .padding()
        .background(.bar)
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
                Task { await generateADIF() }
            }
            .buttonStyle(.bordered)
        }
    }
}

// MARK: - Export Generation

extension SessionADIFExportSheet {
    func generateADIF() async {
        isGenerating = true
        errorMessage = nil
        try? await Task.sleep(for: .milliseconds(100))

        let callsign = session.stationCallsign?.nonEmpty ?? session.myCallsign
        let date = qsos.min(by: { $0.timestamp < $1.timestamp })?.timestamp ?? session.startedAt
        let references = ADIFExportService.SessionReferences(
            parkReference: session.parkReference?.nonEmpty,
            parkName: nil,
            sotaReference: session.sotaReference?.nonEmpty,
            summitName: summitName,
            wwffReference: session.wwffReference?.nonEmpty
        )
        let snapshots = await captureSnapshots()
        let service = ADIFExportService()

        exportResult = await buildCombinedResult(
            service: service,
            snapshots: snapshots,
            callsign: callsign,
            references: references,
            date: date
        )
        flavoredResults = await buildFlavoredResults(
            service: service,
            snapshots: snapshots,
            callsign: callsign,
            references: references,
            date: date
        )
        isGenerating = false
    }

    private func captureSnapshots() async -> [QSOExportSnapshot] {
        var snapshots: [QSOExportSnapshot] = []
        snapshots.reserveCapacity(qsos.count)
        for (index, qso) in qsos.enumerated() {
            snapshots.append(QSOExportSnapshot(from: qso))
            if index % 50 == 49 {
                await Task.yield()
            }
        }
        return snapshots
    }

    private func buildCombinedResult(
        service: ADIFExportService,
        snapshots: [QSOExportSnapshot],
        callsign: String,
        references: ADIFExportService.SessionReferences,
        date: Date
    ) async -> ADIFExportResult {
        let content = await service.generateSessionADIF(
            for: snapshots,
            activatorCallsign: callsign,
            references: references
        )
        let filename = await service.generateSessionFilename(
            activatorCallsign: callsign,
            parkReference: references.parkReference,
            sotaReference: references.sotaReference,
            date: date
        )
        return ADIFExportResult(
            content: content,
            filename: filename,
            qsoCount: qsos.count
        )
    }

    private func buildFlavoredResults(
        service: ADIFExportService,
        snapshots: [QSOExportSnapshot],
        callsign: String,
        references: ADIFExportService.SessionReferences,
        date: Date
    ) async -> [LogSubmissionFlavor: ADIFExportResult] {
        var flavored: [LogSubmissionFlavor: ADIFExportResult] = [:]
        for flavor in availableFlavors {
            let result: ADIFExportResult? = switch flavor.format {
            case .adif:
                await service.generateFlavoredSessionADIF(
                    for: snapshots,
                    activatorCallsign: callsign,
                    references: references,
                    flavor: flavor,
                    date: date
                )
            case .sotaCSV:
                await buildSOTACSVResult(
                    snapshots: snapshots,
                    callsign: callsign,
                    reference: flavor.myReference(in: session),
                    date: date
                )
            }
            if let result {
                flavored[flavor] = result
            }
        }
        return flavored
    }

    private func buildSOTACSVResult(
        snapshots: [QSOExportSnapshot],
        callsign: String,
        reference: String?,
        date: Date
    ) async -> ADIFExportResult? {
        guard let reference else {
            return nil
        }
        let content = await SOTACSVExporter().generate(
            snapshots: snapshots,
            activatorCallsign: callsign
        )
        let filename = LogSubmissionFlavor.sota.filename(
            activatorCallsign: callsign,
            reference: reference,
            date: date
        )
        return ADIFExportResult(
            content: content,
            filename: filename,
            qsoCount: snapshots.count
        )
    }
}
