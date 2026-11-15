import CarrierWaveData
import SwiftUI

// MARK: - POTAJobStatus + Tint

extension POTAJobStatus {
    /// Badge colour for a job status.
    var tint: Color {
        switch self {
        case .pending,
             .processing: .orange
        case .completed: .green
        case .failed,
             .error: .red
        case .duplicate: .yellow
        case .removed: .secondary
        }
    }
}

// MARK: - POTAReplaceUploadConfirmation

/// Confirms deleting an activation's log from POTA and uploading it again.
/// POTA only allows this for 24 hours after the upload, so the dialog says how
/// long is left.
struct POTAReplaceUploadConfirmation: ViewModifier {
    @Binding var isPresented: Bool

    let activation: POTAActivation?
    let plan: POTAUploadReplacePlan
    let onReplace: () -> Void

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                "Replace POTA Upload",
                isPresented: $isPresented,
                titleVisibility: .visible
            ) {
                Button("Delete and Re-upload", role: .destructive) {
                    onReplace()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                if let activation {
                    Text(
                        "This deletes the log you uploaded for \(activation.parkReference) "
                            + "from POTA, then uploads its \(activation.qsoCount) QSO(s) "
                            + "as they are now. POTA allows this for another "
                            + "\(plan.timeLeftText)."
                    )
                }
            }
    }
}

// MARK: - POTAReplaceUploadFooter

/// Footer under an activation's POTA jobs explaining whether the upload can
/// still be replaced.
struct POTAReplaceUploadFooter: View {
    let plan: POTAUploadReplacePlan

    var body: some View {
        if plan.canReplace {
            Text(
                "Fixed a QSO after uploading? Use Replace POTA Upload in the menu "
                    + "above within \(plan.timeLeftText) to delete this log from POTA "
                    + "and upload the corrected one."
            )
        } else if plan.isWindowExpired {
            Text(
                "POTA only lets you delete a log for 24 hours after uploading it. "
                    + "To correct this one, contact a POTA log manager."
            )
        }
    }
}
