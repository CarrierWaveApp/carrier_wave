import CarrierWaveCore
import CarrierWaveData
import SwiftUI

// MARK: - BKGExportSheet

/// Pre-upload check and ADIF export for a BKG session. Rust builds the file
/// (`BkgApi.exportSession`) and lists the contacts that break a BKG rule; this
/// sheet shows both and hands the file to the share sheet. Uploading to the
/// BKG server is not built yet.
struct BKGExportSheet: View {
    // MARK: Internal

    let sessionId: UUID
    let callsign: String

    var body: some View {
        NavigationStack {
            List {
                if let export {
                    summarySection(export)
                    flaggedSection(export)
                } else if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle(BKGLog.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .buttonStyle(.cwToolbarTinted)
                }
                .sharedBackgroundVisibility(.hidden)
            }
            .task { await generate() }
        }
    }

    // MARK: Private

    private static var programVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    @Environment(\.dismiss) private var dismiss
    @State private var export: FfiBkgExport?
    @State private var fileURL: URL?
    @State private var errorMessage: String?

    private func summarySection(_ export: FfiBkgExport) -> some View {
        Section {
            LabeledContent("Contacts", value: "\(export.qsoCount)")
            LabeledContent("Ready", value: "\(Int(export.qsoCount) - export.flagged.count)")
            if !export.cornerGrids.isEmpty {
                LabeledContent("4-grid corner", value: export.cornerGrids.joined(separator: " "))
            }
            if let fileURL, export.qsoCount > 0 {
                ShareLink(item: fileURL) {
                    Label("Share ADIF", systemImage: "square.and.arrow.up")
                }
            }
        } footer: {
            Text("Upload to the BKG server is not available yet. Share the ADIF file instead.")
        }
    }

    @ViewBuilder
    private func flaggedSection(_ export: FfiBkgExport) -> some View {
        if !export.flagged.isEmpty {
            Section {
                ForEach(export.flagged, id: \.qsoId) { check in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(check.callsign)
                                .font(.body.monospaced().weight(.semibold))
                            Spacer()
                            Text(
                                Date(timeIntervalSince1970: TimeInterval(check.qsoDate)),
                                format: .dateTime.hour().minute()
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        ForEach(check.issues, id: \.self) { issue in
                            Label(issue, systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }
            } header: {
                Text("Needs attention")
            } footer: {
                Text("These contacts are in the file but break a \(BKGLog.displayName) rule.")
            }
        }
    }

    private func generate() async {
        do {
            let store = try await CwStoreProvider.shared.store()
            let key = SwiftDataStoreImporter.uuid(sessionId)
            let version = Self.programVersion
            let result = try await Task.detached {
                try BkgApi(store: store).exportSession(sessionId: key, programVersion: version)
            }.value
            guard let result else {
                errorMessage = "This session isn't in the log store yet."
                return
            }
            let day = result.firstQsoDate.map { Date(timeIntervalSince1970: TimeInterval($0)) } ?? Date()
            let stamp = day.formatted(.iso8601.year().month().day().dateSeparator(.dash))
            let name = "\(callsign.replacingOccurrences(of: "/", with: "-"))-BKG-\(stamp).adi"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
            try result.adif.write(to: url, atomically: true, encoding: .utf8)
            fileURL = url
            export = result
        } catch {
            errorMessage = "Couldn't build the \(BKGLog.displayName) log: \(error.localizedDescription)"
        }
    }
}
