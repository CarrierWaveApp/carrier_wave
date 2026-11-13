import CarrierWaveData
import SwiftUI

// MARK: - MultiOpExportSheet

/// Export sheet for multi-operator sessions — export per-operator ADIF files
struct MultiOpExportSheet: View {
    // MARK: Internal

    let session: LoggingSession
    let qsos: [QSO]

    var body: some View {
        NavigationStack {
            List {
                if isGenerating {
                    generatingSection
                } else if !exportFiles.isEmpty {
                    readySection
                } else if let errorMessage {
                    errorSection(errorMessage)
                } else {
                    optionsSection
                }
            }
            .navigationTitle("Export ADIF")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss

    @State private var isGenerating = false
    @State private var exportFiles: [MultiOpExportFile] = []
    @State private var errorMessage: String?
    @State private var selectedCallsign: String?

    // MARK: - Sections

    private var generatingSection: some View {
        Section {
            HStack {
                ProgressView()
                Text("Generating ADIF...")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var optionsSection: some View {
        Section {
            Button {
                Task { await generateAll() }
            } label: {
                Label(
                    "Export All Operators (\(session.allOperatorCallsigns.count))",
                    systemImage: "square.and.arrow.up.on.square"
                )
            }

            ForEach(session.allOperatorCallsigns, id: \.self) { callsign in
                Button {
                    Task { await generateSingle(callsign) }
                } label: {
                    Label(
                        "Export for \(callsign)",
                        systemImage: "square.and.arrow.up"
                    )
                }
            }
        } header: {
            Text("Export Options")
        } footer: {
            Text(
                "\(qsos.count) QSOs — each operator gets a copy of the full log"
            )
        }
    }

    @ViewBuilder
    private var readySection: some View {
        if let single = exportFiles.first, exportFiles.count == 1 {
            singleFileSection(single)
        } else {
            allFilesSection
        }
    }

    private var allFilesSection: some View {
        Section {
            ForEach(exportFiles, id: \.callsign) { file in
                ShareLink(
                    item: file.content,
                    preview: SharePreview(file.filename)
                ) {
                    Label(file.filename, systemImage: "doc.text")
                }
            }
        } header: {
            Text("Ready — \(exportFiles.count) files")
        }
    }

    private func singleFileSection(_ file: MultiOpExportFile) -> some View {
        Section {
            ShareLink(
                item: file.content,
                preview: SharePreview(file.filename)
            ) {
                Label(file.filename, systemImage: "doc.text")
            }
        } header: {
            Text("Ready — \(file.callsign)")
        }
    }

    private func errorSection(_ message: String) -> some View {
        Section {
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
            Button("Try Again") {
                errorMessage = nil
            }
        }
    }

    // MARK: - Generation

    @MainActor
    private func generateAll() async {
        await generateForCallsigns(session.allOperatorCallsigns)
    }

    @MainActor
    private func generateSingle(_ callsign: String) async {
        await generateForCallsigns([callsign])
    }

    @MainActor
    private func generateForCallsigns(_ callsigns: [String]) async {
        isGenerating = true
        defer { isGenerating = false }

        let snapshots = qsos.map { QSOExportSnapshot(from: $0) }

        let config = MultiOpExportConfig(
            snapshots: snapshots,
            operatorCallsigns: callsigns,
            parkReference: session.parkReference,
            parkName: nil,
            sessionTitle: session.customTitle,
            sessionDate: session.startedAt
        )

        let service = ADIFExportService()
        exportFiles = await service.generateMultiOpADIF(for: config)
    }
}
