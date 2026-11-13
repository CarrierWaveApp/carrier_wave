// Session ADIF Export Sheet — per-program (flavored) share rendering
//
// Splits the bottom-bar share section out of `SessionADIFExportSheet.swift` so
// that file stays under SwiftLint's 500-line cap. When an n-fer session has
// more than one program (e.g. POTA + WWFF) we render one prominent
// "Submit to <program>" ShareLink per detected flavor — each emits an ADIF
// with the right `MY_SIG` and the program-specific filename — plus a
// "Combined archive" link for the unified record. Single-program sessions
// keep the original one-button look.

import SwiftUI

extension SessionADIFExportSheet {
    /// Renders the share area. With 2+ flavors, shows one row per program
    /// followed by the combined archive; otherwise falls back to a single
    /// "Share ADIF" button.
    @ViewBuilder
    func flavorPullUp(combined: ADIFExportResult) -> some View {
        if availableFlavors.count > 1 {
            VStack(spacing: 8) {
                ForEach(availableFlavors) { flavor in
                    flavorShareLink(flavor: flavor)
                }
                combinedArchiveShareLink(result: combined)
                Text("This session is an n-fer. Submit each program separately.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
        } else {
            shareButton(result: combined)
        }
    }

    /// Single prominent ShareLink for the combined-flavor case (1 program or
    /// casual session).
    func shareButton(result: ADIFExportResult) -> some View {
        ShareLink(
            item: ShareableADIF(
                content: result.content,
                filename: result.filename
            ),
            preview: SharePreview(
                result.filename,
                image: Image(systemName: "doc.text")
            )
        ) {
            Label("Share ADIF", systemImage: "square.and.arrow.up")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }

    @ViewBuilder
    private func flavorShareLink(flavor: LogSubmissionFlavor) -> some View {
        if let result = flavoredResults[flavor] {
            switch flavor.format {
            case .adif:
                adifShareLink(flavor: flavor, result: result)
            case .sotaCSV:
                sotaCSVShareLink(flavor: flavor, result: result)
            }
        }
    }

    private func adifShareLink(
        flavor: LogSubmissionFlavor,
        result: ADIFExportResult
    ) -> some View {
        ShareLink(
            item: ShareableADIF(
                content: result.content,
                filename: result.filename
            ),
            preview: SharePreview(
                result.filename,
                image: Image(systemName: flavor.iconName)
            )
        ) {
            Label(
                "Submit to \(flavor.displayName)",
                systemImage: flavor.iconName
            )
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }

    private func sotaCSVShareLink(
        flavor: LogSubmissionFlavor,
        result: ADIFExportResult
    ) -> some View {
        ShareLink(
            item: ShareableSOTACSV(
                content: result.content,
                filename: result.filename
            ),
            preview: SharePreview(
                result.filename,
                image: Image(systemName: flavor.iconName)
            )
        ) {
            Label(
                "Submit to \(flavor.displayName)",
                systemImage: flavor.iconName
            )
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }

    private func combinedArchiveShareLink(result: ADIFExportResult) -> some View {
        ShareLink(
            item: ShareableADIF(
                content: result.content,
                filename: result.filename
            ),
            preview: SharePreview(
                result.filename,
                image: Image(systemName: "archivebox")
            )
        ) {
            Label("Combined archive", systemImage: "archivebox")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
    }
}
