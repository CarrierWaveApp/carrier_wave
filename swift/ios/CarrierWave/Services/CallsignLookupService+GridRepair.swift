// CallsignLookupService - Grid Repair
//
// Batch-repairs missing theirGrid on QSOs by looking up callsigns
// via QRZ (with session key reuse) or HamDB fallback.

import CarrierWaveData
import SwiftData
import UIKit

extension Notification.Name {
    /// Posted (on the main actor) after `repairMissingGrids` fills in at
    /// least one `theirGrid`. Views holding a rendered map should re-render.
    static let didRepairQSOGrids = Notification.Name("didRepairQSOGrids")
}

extension CallsignLookupService {
    /// Batch-lookup missing `theirGrid` for QSOs in an activation.
    /// Gets a single QRZ session key and reuses it for all lookups.
    /// Falls back to HamDB when QRZ credentials are unavailable.
    /// - Parameters:
    ///   - qsos: QSOs to check and repair
    ///   - modelContext: Context to save updated QSOs
    /// - Returns: Number of QSOs repaired
    @discardableResult
    func repairMissingGrids(
        for qsos: [QSO],
        in modelContext: ModelContext
    ) async -> Int {
        let missing = qsos.filter { ($0.theirGrid ?? "").isEmpty }
        guard !missing.isEmpty else {
            return 0
        }

        let callsignToGrid = await batchLookupGrids(
            callsigns: Set(
                missing.map { $0.callsign.uppercased() }
                    .filter { !$0.isEmpty }
            )
        )

        // Apply grids to QSOs
        var repaired = 0
        for qso in missing {
            let callsign = qso.callsign.uppercased()
            guard !callsign.isEmpty,
                  let grid = callsignToGrid[callsign]
            else {
                continue
            }
            qso.theirGrid = grid
            repaired += 1
        }

        if repaired > 0 {
            try? modelContext.save()
            NotificationCenter.default.post(name: .didRepairQSOGrids, object: nil)
        }

        return repaired
    }

    /// Look up grids for a set of callsigns, reusing a single QRZ session.
    private func batchLookupGrids(
        callsigns: Set<String>
    ) async -> [String: String] {
        guard !callsigns.isEmpty else {
            return [:]
        }

        var results: [String: String] = [:]

        // QRZ lookups reuse a single in-memory session managed by the shared
        // `QrzApi`, so no session key needs threading through here.
        let qrzAvailable = hasQRZCallbookCredentials()

        for callsign in callsigns {
            if qrzAvailable,
               let info = try? await Self.qrzCallbook.lookup(callsign),
               let grid = info.grid, grid.count >= 4
            {
                results[callsign] = grid
                continue
            }

            // Fall back to HamDB (free, no credentials needed)
            if let info = await lookupInHamDB(callsign),
               let grid = info.grid, grid.count >= 4
            {
                results[callsign] = grid
            }
        }

        return results
    }
}
