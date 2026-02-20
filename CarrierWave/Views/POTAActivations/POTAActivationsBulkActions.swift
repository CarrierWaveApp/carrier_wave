// POTA Activations Bulk Actions
//
// Components for multi-select bulk actions on POTA activations:
// selection circles, bottom toolbar, progress banner, and helper functions.

import CarrierWaveCore
import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - BulkUploadProgress

/// Tracks progress of a bulk upload operation across multiple activations
struct BulkUploadProgress {
    let total: Int
    var completed: Int
    var currentPark: String
    var isCancelled: Bool
    var completedQSOCount: Int

    /// Whether all activations have been processed (completed or cancelled)
    var isFinished: Bool {
        completed >= total || isCancelled
    }

    /// Fraction complete for progress display
    var fractionComplete: Double {
        guard total > 0 else {
            return 0
        }
        return Double(completed) / Double(total)
    }
}

// MARK: - SelectionCircleView

/// Selection indicator for multi-select mode rows
struct SelectionCircleView: View {
    let isSelected: Bool

    var body: some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .foregroundStyle(isSelected ? Color.accentColor : .secondary)
            .font(.title3)
            .accessibilityHidden(true)
    }
}

// MARK: - BulkUploadProgressBanner

/// Progress banner shown during bulk upload operations
struct BulkUploadProgressBanner: View {
    // MARK: Internal

    let progress: BulkUploadProgress
    let onCancel: () -> Void

    var body: some View {
        HStack {
            if progress.isFinished {
                completionContent
            } else {
                activeContent
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: Private

    @ViewBuilder private var activeContent: some View {
        ProgressView()
            .controlSize(.small)
        VStack(alignment: .leading, spacing: 2) {
            Text("Uploading \(progress.completed + 1) of \(progress.total)...")
                .font(.subheadline)
                .fontWeight(.medium)
            Text(progress.currentPark)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        Spacer()
        Button("Cancel") {
            onCancel()
        }
        .font(.subheadline)
        .foregroundStyle(.red)
    }

    @ViewBuilder private var completionContent: some View {
        Image(systemName: progress.isCancelled ? "xmark.circle.fill" : "checkmark.circle.fill")
            .foregroundStyle(progress.isCancelled ? .orange : .green)
        VStack(alignment: .leading, spacing: 2) {
            if progress.isCancelled {
                Text("Upload cancelled")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(
                    "Uploaded \(progress.completed) of \(progress.total) activations "
                        + "(\(progress.completedQSOCount) QSOs)"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
                Text("Upload complete")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(
                    "Uploaded \(progress.total) activations "
                        + "(\(progress.completedQSOCount) QSOs)"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        Spacer()
    }
}

// MARK: - BulkActionToolbar

/// Bottom toolbar with bulk action buttons shown during selection mode
struct BulkActionToolbar: View {
    // MARK: Internal

    let pendingQSOCount: Int
    let selectedCount: Int
    let hasSelectedPending: Bool
    let isAuthenticated: Bool
    let isInMaintenance: Bool
    let onUpload: () -> Void
    let onReject: () -> Void
    let onExport: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            bulkButton(
                icon: "arrow.up.circle.fill",
                label: pendingQSOCount > 0 ? "Upload (\(pendingQSOCount))" : "Upload",
                enabled: hasSelectedPending && isAuthenticated && !isInMaintenance,
                action: onUpload
            )
            bulkButton(
                icon: "xmark.circle",
                label: "Reject",
                enabled: hasSelectedPending,
                action: onReject
            )
            bulkButton(
                icon: "doc.text",
                label: "Export",
                enabled: selectedCount > 0,
                action: onExport
            )
        }
        .padding(.vertical, 8)
        .background(.bar)
    }

    // MARK: Private

    private func bulkButton(
        icon: String,
        label: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            action()
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.title3)
                Text(label)
                    .font(.caption)
            }
            .frame(maxWidth: .infinity)
        }
        .disabled(!enabled)
        .accessibilityLabel(label)
    }
}

// MARK: - BulkADIFExportSheet

/// Sheet for exporting combined ADIF from multiple activations
struct BulkADIFExportSheet: View {
    // MARK: Internal

    let activations: [POTAActivation]
    let parkNames: [String: String]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    headerSection
                    detailsSection
                }
                .padding(.horizontal)
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 12) {
                    if isGenerating {
                        ProgressView().scaleEffect(1.2)
                        Text("Generating ADIF...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else if let exportResult {
                        shareButton(result: exportResult)
                        saveToFilesButton
                        copyToClipboardButton(result: exportResult)
                    } else if let errorMessage {
                        Text(errorMessage)
                            .font(.subheadline)
                            .foregroundStyle(.red)
                    }
                }
                .padding()
                .background(.bar)
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
        .task { await generateBulkADIF() }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss

    @State private var isGenerating = false
    @State private var exportResult: ADIFExportResult?
    @State private var errorMessage: String?
    @State private var showFileSaver = false
    @State private var copiedToClipboard = false

    private var headerSection: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.text")
                .font(.system(size: 36))
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(activations.count) Activations")
                    .font(.title2)
                    .fontWeight(.bold)
                Text("Combined ADIF export")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var detailsSection: some View {
        VStack(spacing: 12) {
            let totalQSOs = activations.reduce(0) { $0 + $1.qsoCount }
            UploadDetailRow(label: "Total QSOs", value: "\(totalQSOs)")
            UploadDetailRow(label: "Activations", value: "\(activations.count)")
            UploadDetailRow(
                label: "Parks",
                value: activations.map(\.parkReference).joined(separator: ", ")
            )
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    private var saveToFilesButton: some View {
        Button {
            showFileSaver = true
        } label: {
            Label("Save to Files", systemImage: "folder")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
    }

    private func shareButton(result: ADIFExportResult) -> some View {
        ShareLink(
            item: ShareableADIF(content: result.content, filename: result.filename),
            preview: SharePreview(result.filename, image: Image(systemName: "doc.text"))
        ) {
            Label("Share ADIF", systemImage: "square.and.arrow.up")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }

    private func copyToClipboardButton(result: ADIFExportResult) -> some View {
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

    private func generateBulkADIF() async {
        isGenerating = true

        try? await Task.sleep(for: .milliseconds(100))

        var activationData: [BulkADIFActivation] = []

        for activation in activations {
            var snapshots: [QSOExportSnapshot] = []
            for (index, qso) in activation.qsos.enumerated() {
                snapshots.append(QSOExportSnapshot(from: qso))
                if index % 50 == 49 {
                    await Task.yield()
                }
            }
            activationData.append(
                BulkADIFActivation(
                    snapshots: snapshots,
                    parkReference: activation.parkReference,
                    parkName: parkNames[activation.parkReference.uppercased()]
                )
            )
        }

        let service = ADIFExportService()
        let content = await service.generateBulkADIF(for: activationData)
        let filename = await service.generateBulkFilename(
            activationCount: activations.count,
            date: activations.first?.utcDate ?? Date()
        )
        let totalQSOs = activations.reduce(0) { $0 + $1.qsoCount }

        exportResult = ADIFExportResult(
            content: content,
            filename: filename,
            qsoCount: totalQSOs
        )
        isGenerating = false
    }
}

// MARK: - Bulk Action Methods

extension POTAActivationsContentView {
    /// Upload all pending QSOs across selected activations sequentially
    func performBulkUpload() async {
        let toUpload = selectedActivationsWithPending(
            activations: activations, selectedIds: selectedActivationIds
        )
        guard !toUpload.isEmpty else {
            return
        }

        // Exit selection mode and show progress
        isSelecting = false
        selectedActivationIds.removeAll()
        bulkUploadProgress = BulkUploadProgress(
            total: toUpload.count,
            completed: 0,
            currentPark: toUpload.first?.parkReference ?? "",
            isCancelled: false,
            completedQSOCount: 0
        )

        for activation in toUpload {
            // Check cancellation
            if bulkUploadProgress?.isCancelled == true {
                break
            }
            // Check maintenance window before each upload
            if isInMaintenance {
                errorMessage = "Maintenance window started. Remaining uploads skipped."
                break
            }

            bulkUploadProgress?.currentPark = activation.parkReference
            await performUpload(for: activation)
            bulkUploadProgress?.completed += 1
            bulkUploadProgress?.completedQSOCount += activation.pendingCount
        }

        // Reload data to reflect changes
        await loadParkQSOs()

        // Auto-hide progress banner after 3 seconds
        try? await Task.sleep(for: .seconds(3))
        bulkUploadProgress = nil
    }

    /// Reject all pending QSOs across selected activations
    func performBulkReject() {
        let toReject = selectedActivationsWithPending(
            activations: activations, selectedIds: selectedActivationIds
        )
        for activation in toReject {
            let pendingQSOs = activation.pendingQSOs()
            for qso in pendingQSOs {
                qso.markUploadRejected(for: .pota, context: modelContext)
            }
        }
        isSelecting = false
        selectedActivationIds.removeAll()
        Task { await loadParkQSOs() }
    }

    /// Export combined ADIF for all selected activations
    func performBulkExport() {
        let selected = selectedActivations(
            activations: activations, selectedIds: selectedActivationIds
        )
        guard !selected.isEmpty else {
            return
        }
        bulkExportActivations = selected
    }
}

// MARK: - Bulk Selection Helpers

/// Count pending QSOs across selected activations
func selectedPendingQSOCount(
    activations: [POTAActivation],
    selectedIds: Set<String>
) -> Int {
    activations
        .filter { selectedIds.contains($0.id) }
        .reduce(0) { $0 + $1.pendingCount }
}

/// Filter to selected activations that have pending QSOs
func selectedActivationsWithPending(
    activations: [POTAActivation],
    selectedIds: Set<String>
) -> [POTAActivation] {
    activations.filter { selectedIds.contains($0.id) && $0.hasQSOsToUpload && !$0.isRejected }
}

/// Filter to selected activations
func selectedActivations(
    activations: [POTAActivation],
    selectedIds: Set<String>
) -> [POTAActivation] {
    activations.filter { selectedIds.contains($0.id) }
}
