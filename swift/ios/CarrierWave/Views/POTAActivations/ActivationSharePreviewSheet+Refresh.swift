// Activation Share Preview Sheet - Location Refresh
//
// Retries callsign enrichment for contacts that still have no grid when the
// brag sheet opens, then re-renders the card from the current QSO records.
// An activation logged without connectivity therefore fixes itself the next
// time the sheet is opened online — no session-end snapshot to invalidate.

import CarrierWaveData
import SwiftUI

extension ActivationSharePreviewSheet {
    /// QSOs on the card that still lack a usable grid.
    var qsosMissingGrid: [QSO] {
        data.qsos.filter { ($0.theirGrid ?? "").count < 4 }
    }

    /// "N contacts without location", or `nil` when every contact has a grid
    /// (or the sheet has no QSO list to inspect).
    var missingLocationCaption: String? {
        ActivationShareMapMarkers.caption(forCount: qsosMissingGrid.count)
    }

    /// On open: if any contact lacks a grid, run the existing grid-repair
    /// lookup (QRZ → HamDB) and re-render when it filled anything in.
    func refreshMissingLocations() async {
        guard let rerender = data.rerender, !isRefreshing else {
            return
        }
        let missing = qsosMissingGrid
        guard !missing.isEmpty else {
            return
        }

        isRefreshing = true
        defer { isRefreshing = false }

        let lookupService = CallsignLookupService(modelContext: modelContext)
        let repaired = await lookupService.repairMissingGrids(
            for: missing, in: modelContext
        )
        guard repaired > 0, let image = await rerender() else {
            return
        }
        refreshedImage = image
    }

    /// Another surface repaired grids (the repair path posts
    /// `.didRepairQSOGrids`); pick up the new coordinates. Skipped while our
    /// own refresh is running — it re-renders itself.
    func rerenderAfterExternalRepair() async {
        guard let rerender = data.rerender, !isRefreshing else {
            return
        }
        if let image = await rerender() {
            refreshedImage = image
        }
    }
}
