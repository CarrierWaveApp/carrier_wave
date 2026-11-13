// HamAlert Export Sheet
//
// Confirmation and export UI for pushing needs to HamAlert.
// Supports text export (clipboard) and direct API push via session auth.

import CarrierWaveData
import SwiftUI

// MARK: - HamAlertExportSheet

struct HamAlertExportSheet: View {
    // MARK: Internal

    let snapshot: NeedsSnapshot

    var body: some View {
        NavigationStack {
            List {
                previewSection
                exportModeSection
            }
            .navigationTitle("Export to HamAlert")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .landscapeAdaptiveDetents(portrait: [.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
    @State private var exportText: String?
    @State private var isExporting = false
    @State private var exportResult: HamAlertExportResult?
    @State private var exportError: String?

    private var hasCredentials: Bool {
        (try? KeychainHelper.shared.read(
            for: KeychainHelper.Keys.hamAlertUsername
        )) != nil
    }

    private var previewSection: some View {
        Section("What will be exported") {
            if !snapshot.was.isComplete {
                exportRow(
                    icon: "map",
                    label: "WAS States",
                    detail: "\(snapshot.was.statesMissing.count) missing"
                )
            }

            if snapshot.potaHunter.parksRemaining > 0 {
                exportRow(
                    icon: "tree",
                    label: "POTA Hunter",
                    detail: "Any new park (general alert)"
                )
            }

            ForEach(snapshot.customPatterns) { pattern in
                exportRow(
                    icon: "star",
                    label: pattern.label,
                    detail: pattern.pattern
                )
            }

            if snapshot.was.isComplete, snapshot.customPatterns.isEmpty {
                Text("No exportable needs")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var exportModeSection: some View {
        Section("Export Method") {
            Button {
                Task { await generateTextExport() }
            } label: {
                Label("Copy as Text", systemImage: "doc.on.clipboard")
            }
            .disabled(isExporting)

            if let text = exportText {
                Button {
                    UIPasteboard.general.string = text
                } label: {
                    Label(
                        "Copied! Tap to copy again",
                        systemImage: "checkmark"
                    )
                    .foregroundStyle(.green)
                }
            }

            if hasCredentials {
                Button {
                    Task { await pushToHamAlert() }
                } label: {
                    Label(
                        "Push to HamAlert",
                        systemImage: "arrow.up.circle"
                    )
                }
                .disabled(isExporting)
            } else {
                HStack {
                    Label(
                        "Push to HamAlert",
                        systemImage: "arrow.up.circle"
                    )
                    .foregroundStyle(.secondary)
                    Spacer()
                    Text("Configure in Settings")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let result = exportResult {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Created \(result.triggersCreated) triggers")
                }
                .font(.subheadline)
            }

            if let error = exportError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private func exportRow(
        icon: String,
        label: String,
        detail: String
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(.blue)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.subheadline)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func generateTextExport() async {
        isExporting = true
        let exporter = HamAlertExporter()
        let text = await exporter.exportAsText(
            snapshot, customNeeds: snapshot.customPatterns
        )
        exportText = text
        UIPasteboard.general.string = text
        isExporting = false
    }

    private func pushToHamAlert() async {
        guard
            let username = try? KeychainHelper.shared.readString(
                for: KeychainHelper.Keys.hamAlertUsername
            ),
            let password = try? KeychainHelper.shared.readString(
                for: KeychainHelper.Keys.hamAlertPassword
            )
        else {
            exportError = "HamAlert credentials not found."
            return
        }

        isExporting = true
        exportError = nil
        exportResult = nil

        do {
            let exporter = HamAlertExporter()
            let result = try await exporter.pushToHamAlert(
                snapshot,
                customNeeds: snapshot.customPatterns,
                username: username,
                password: password
            )
            exportResult = result
        } catch {
            exportError = error.localizedDescription
        }
        isExporting = false
    }
}
