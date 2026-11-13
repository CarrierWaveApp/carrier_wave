// RBNPanelView data loading + display helpers
//
// Split from RBNPanelView.swift for the 500-line file limit. Spots come
// from the Rust engine's per-callsign fetch; the target station's own grid
// is resolved host-side (HamDB + GridCache).

import CarrierWaveCwFfi
import CarrierWaveData
import SwiftUI

// MARK: - RBNPanelView + Helpers

extension RBNPanelView {
    func sourceColor(_ spot: UnifiedSpot) -> Color {
        switch spot.source {
        case .rbn:
            if let snr = spot.snr {
                return snrColor(snr)
            }
            return .blue
        case .pota:
            return .green
        case .sota:
            return .orange
        case .wwff:
            return .mint
        case .pskr:
            return .purple
        case .dxSummit,
             .dxHeat,
             .dxWatch,
             .cluster:
            return spot.source.color
        }
    }

    func sourceIcon(_ spot: UnifiedSpot) -> String {
        switch spot.source {
        case .rbn:
            if let snr = spot.snr {
                return signalIcon(snr: snr)
            }
            return "antenna.radiowaves.left.and.right"
        case .pota:
            return "leaf.fill"
        case .sota:
            return "mountain.2.fill"
        case .wwff:
            return "leaf.fill"
        case .pskr:
            return "waveform"
        case .dxSummit,
             .dxHeat,
             .dxWatch:
            return "globe"
        case .cluster:
            return "terminal"
        }
    }

    func snrColor(_ snr: Int) -> Color {
        switch snr {
        case 25...: .green
        case 15...: .blue
        case 5...: .orange
        default: .red
        }
    }

    func signalIcon(snr: Int) -> String {
        switch snr {
        case 25...: "wifi"
        case 15...: "wifi"
        case 5...: "wifi.exclamationmark"
        default: "wifi.slash"
        }
    }

    func loadData() async {
        isLoading = true
        errorMessage = nil

        let provider = SpotEngineProvider.shared
        guard let engine = provider.engine() else {
            errorMessage = provider.lastEngineError
            isLoading = false
            return
        }

        do {
            async let gridTask = lookupTargetGrid()
            let ffiSpots = try await engine.fetchCallsignSpots(
                callsign: displayCallsign,
                minutes: UInt32(lookbackMinutes),
                includePota: true
            )
            spots = ffiSpots.map(\.appUnifiedSpot)
            targetGrid = await gridTask

            if showMap, !spots.contains(where: { $0.spotterGrid != nil }) {
                showMap = false
            }
            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    /// The target station's own grid for the map center (HamDB + shared
    /// cache) — the one piece the engine's per-callsign fetch doesn't cover.
    private func lookupTargetGrid() async -> String? {
        let normalized = displayCallsign.uppercased()
        if let cached = await GridCache.shared.get(normalized) {
            return cached
        }
        let grid = try? await hamDBClient.lookup(callsign: normalized)?.grid
        await GridCache.shared.set(normalized, grid: grid)
        return grid
    }

    func autoRefreshLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(60))
            guard !Task.isCancelled else {
                return
            }
            await loadData()
        }
    }
}
