import CarrierWaveData
import SwiftUI

// MARK: - SessionDetailConfirmations

/// Hosts the Reject Upload + Reopen Session confirmation dialogs for
/// `SessionDetailView`. Extracted to a `ViewModifier` so the dialogs render
/// from the visible detail view (CAR-250) without pushing the parent struct
/// past SwiftLint's 250-line type-body cap.
struct SessionDetailConfirmations: ViewModifier {
    @Binding var showRejectConfirmation: Bool
    @Binding var showReopenConfirmation: Bool

    let activation: POTAActivation?
    let onReject: (() -> Void)?
    let onReopen: (() -> Void)?

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                "Reject Upload",
                isPresented: $showRejectConfirmation,
                titleVisibility: .visible
            ) {
                Button("Reject Upload", role: .destructive) {
                    onReject?()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                if let activation {
                    Text(
                        "Reject upload for \(activation.parkReference)? "
                            + "This will hide \(activation.pendingCount) QSO(s) "
                            + "from POTA uploads."
                    )
                }
            }
            .confirmationDialog(
                "Reopen Session",
                isPresented: $showReopenConfirmation,
                titleVisibility: .visible
            ) {
                Button("Reopen") { onReopen?() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(
                    "This session will become active and you can log more QSOs."
                )
            }
    }
}

// MARK: - Actions Menu

extension SessionDetailView {
    var actionsMenu: some View {
        Group {
            if hasActions || activation != nil || session != nil {
                Menu {
                    sessionEditItems
                    exportItems
                    sessionLifecycleItems
                    shareAndUploadItems
                    debugItems
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
    }

    @ViewBuilder
    private var sessionEditItems: some View {
        if session != nil {
            Button { showEditSheet = true } label: {
                Label("Edit Info", systemImage: "pencil")
            }
            Button { showGridEditSheet = true } label: {
                Label("Set My Grid", systemImage: "square.grid.3x3")
            }
        }
        if canAddLateQSO {
            Button { showAddQSOSheet = true } label: {
                Label("Add QSO", systemImage: "plus.circle")
            }
        }
    }

    @ViewBuilder
    private var exportItems: some View {
        if let session, session.isMultiOp {
            Button { showMultiOpExportSheet = true } label: {
                Label("Multi-Op Export", systemImage: "person.2.fill")
            }
        }
        if session != nil {
            Button { showSplitExportSheet = true } label: {
                Label("Split Export", systemImage: "doc.on.doc")
            }
        }
        if let onExport {
            Button { onExport() } label: {
                Label("Export ADIF", systemImage: "doc.text")
            }
        }
        if let onImport {
            Button { onImport() } label: {
                Label("Import ADIF", systemImage: "square.and.arrow.down")
            }
        }
    }

    @ViewBuilder
    private var sessionLifecycleItems: some View {
        if onReopen != nil {
            Divider()
            Button { showReopenConfirmation = true } label: {
                Label("Reopen Session", systemImage: "arrow.clockwise")
            }
        }
        if let onMerge {
            Button { onMerge() } label: {
                Label(
                    "Merge Into\u{2026}",
                    systemImage: "arrow.triangle.merge"
                )
            }
        }
    }

    @ViewBuilder
    private var shareAndUploadItems: some View {
        if session?.activationType == .tota {
            Button {
                showTOTABragSheet = true
            } label: {
                Label("Brag Sheet", systemImage: "square.and.arrow.up")
            }
        } else if let onShare {
            Button { onShare() } label: {
                Label("Brag Sheet", systemImage: "square.and.arrow.up")
            }
        }
        if shouldShowUpload, onReject != nil {
            Divider()
            Button(role: .destructive) { showRejectConfirmation = true } label: {
                Label("Reject Upload", systemImage: "xmark.circle")
            }
        }
    }

    @ViewBuilder
    private var debugItems: some View {
        if session != nil {
            Divider()
            Button { showDebugInfoSheet = true } label: {
                Label("Send Debug Info", systemImage: "ladybug")
            }
        }
        if debugMode, let onForceReupload {
            Button { onForceReupload() } label: {
                Label(
                    "Force Reupload",
                    systemImage: "arrow.counterclockwise.circle"
                )
            }
        }
    }
}
