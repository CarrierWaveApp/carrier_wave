// Bulk ADIF Export - Split helpers
//
// Config construction and multi-file sharing for the "Split by Park" mode of
// the bulk activation ADIF export.

import CarrierWaveData
import SwiftUI
import UIKit

// MARK: - Split Config

/// Build a park-split config for a bulk activation export.
///
/// Splits by park only — day and operator are left intact — so each unique
/// park across the selected activations yields exactly one ADIF file that
/// lists only that park. N-fer QSOs (`"US-1, US-2"`) fan out into each park.
func makeBulkSplitConfig(
    snapshots: [QSOExportSnapshot],
    callsign: String,
    parkNames: [String: String]
) -> SplitExportConfig {
    SplitExportConfig(
        snapshots: snapshots,
        splitByUTCDay: false,
        splitByPark: true,
        splitByOperator: false,
        fallbackPark: nil,
        fallbackCallsign: callsign,
        parkNames: parkNames
    )
}

// MARK: - Multi-file Share

/// Write each ADIF to a temp file and present a share sheet for all of them.
@MainActor
func shareADIFFiles(_ files: [(filename: String, content: String)]) {
    let items: [Any] = files.map { file in
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(file.filename)
        try? file.content.write(to: url, atomically: true, encoding: .utf8)
        return url as Any
    }

    guard let scene = UIApplication.shared.connectedScenes
        .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
        let root = scene.windows.first?.rootViewController
    else {
        return
    }

    let activityVC = UIActivityViewController(
        activityItems: items, applicationActivities: nil
    )
    if let popover = activityVC.popoverPresentationController {
        popover.sourceView = root.view
        popover.sourceRect = CGRect(
            x: root.view.bounds.midX,
            y: root.view.bounds.midY,
            width: 0, height: 0
        )
    }
    root.present(activityVC, animated: true)
}
