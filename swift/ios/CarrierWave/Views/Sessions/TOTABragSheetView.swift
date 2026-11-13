// Polished, shareable TOTA brag sheet for a single session.
//
// Shown in the EndSessionFlowView brag-sheet step (replacing the generic
// SessionBragSheetCard for TOTA) and reachable from SessionDetailView+TOTA
// via a "Share brag sheet" button. Designed as a square card so a snapshot
// is socially shareable.

import CarrierWaveCore
import CarrierWaveData
import MapKit
import SwiftUI

// MARK: - TOTABragSheetView

struct TOTABragSheetView: View {
    // MARK: Internal

    let session: LoggingSession
    let qsos: [QSO]
    /// Pre-rendered contact map (geodesic arcs + chaser pins). When non-nil,
    /// displayed instead of the live Map view so snapshots embed correctly.
    /// Live preview surfaces leave nil and get the interactive Map.
    var contactMapImage: UIImage?
    /// Pre-rendered path map (track polyline + tile boundary). Same contract.
    var pathMapImage: UIImage?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(.white.opacity(0.15))
            tileBlock
            contactMapBlock
            mapBlock
            scoreBlock
            chipsBlock
            statsBlock
            equipmentBlock
            timelineBlock
            footer
        }
        .frame(width: 360)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(BragSheetTheme.border, lineWidth: 1)
        )
    }

    // MARK: Private

    private var cardBackground: some ShapeStyle {
        BragSheetTheme.cardBackground
    }
}

// Section views and derived helpers live in TOTABragSheetView+Sections.swift.

// MARK: - TOTABragSheetSheet

/// Modal wrapper that presents the brag sheet with Share + Done buttons.
struct TOTABragSheetSheet: View {
    // MARK: Internal

    let session: LoggingSession
    let qsos: [QSO]
    var onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    TOTABragSheetView(session: session, qsos: qsos)
                        .padding(.top, 8)
                    Button {
                        presentShareSheet()
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.horizontal)
                }
                .padding(.bottom, 16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Brag Sheet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { onDismiss() }
                }
            }
        }
    }

    // MARK: Private

    /// Render to image and present via UIActivityViewController so Copy /
    /// Save Image / AirDrop / Messages all work with the actual brag-sheet
    /// PNG — same UX as other session brag sheets via ShareHelper.
    @MainActor
    private func presentShareSheet() {
        Task { await presentShareSheetAsync() }
    }

    @MainActor
    private func presentShareSheetAsync() async {
        guard let image = await TOTABragSheetRenderer.render(
            session: session, qsos: qsos
        ) else {
            return
        }
        let controller = UIActivityViewController(
            activityItems: [image],
            applicationActivities: nil
        )
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let presenter = scene.windows.first?.rootViewController?.topMostPresented
        else {
            return
        }
        if let popover = controller.popoverPresentationController {
            popover.sourceView = presenter.view
            popover.sourceRect = CGRect(
                x: presenter.view.bounds.midX,
                y: presenter.view.bounds.midY,
                width: 0,
                height: 0
            )
            popover.permittedArrowDirections = []
        }
        presenter.present(controller, animated: true)
    }
}

extension UIViewController {
    /// Walk the presented-controller chain to find the visible top.
    var topMostPresented: UIViewController {
        var top: UIViewController = self
        while let next = top.presentedViewController {
            top = next
        }
        return top
    }
}
