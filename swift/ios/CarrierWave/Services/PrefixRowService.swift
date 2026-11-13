// Prefix Row Service
//
// Fetches position-local callsign prefix suggestions for the logger's
// prefix hot-key row (CAR-290). The ranking lives in shared Rust
// (SessionApi.suggestedPrefixes); this service anchors it on the
// device's current position and caches the result for the accessory.

import CarrierWaveData
import Foundation
import SwiftUI

@MainActor
@Observable
final class PrefixRowService {
    // MARK: Internal

    static let shared = PrefixRowService()

    /// Ranked position-local prefixes, most relevant first.
    private(set) var suggested: [String] = []

    /// Refreshes only when the anchor grid changed or nothing is cached.
    func refreshIfNeeded() {
        let grid = DeviceLocationHint.lastKnownGrid
        guard suggested.isEmpty || grid != lastAnchorGrid else {
            return
        }
        refresh()
    }

    func refresh() {
        let grid = DeviceLocationHint.lastKnownGrid
        lastAnchorGrid = grid
        guard let api = SessionApiRegistry.current else {
            return
        }
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            let list = await Task.detached(priority: .utility) {
                (try? api.suggestedPrefixes(currentGrid: grid, limit: 0)) ?? []
            }.value
            guard !Task.isCancelled, let self else {
                return
            }
            if suggested != list {
                suggested = list
                // Rebuild any open UIKit keyboard accessory with the new keys.
                NotificationCenter.default.post(
                    name: .keyboardRowConfigurationChanged,
                    object: nil
                )
            }
        }
    }

    // MARK: Private

    private var lastAnchorGrid: String?
    private var refreshTask: Task<Void, Never>?
}
