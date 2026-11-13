// POTA Activations Bulk Actions
//
// Components for multi-select bulk actions on POTA activations:
// selection circles, bottom toolbar, progress banner, and helper functions.

import CarrierWaveData
import SwiftUI
import UIKit

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
