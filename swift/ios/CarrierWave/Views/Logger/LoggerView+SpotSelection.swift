import CarrierWaveData
import SwiftUI

// MARK: - LoggerView Spot Selection

extension LoggerView {
    // MARK: - Spot Selection

    /// Shared handler for spot selection from both panels and sidebar
    func handleSpotSelection(_ selection: SpotSelection) {
        guard sessionManager?.activeSession != nil else {
            ToastManager.shared.warning("Start a session first")
            return
        }

        // In an active FT8 session, route spot taps to FT8 call-station
        // rather than disrupting the FT8 view with a frequency/form change.
        if sessionManager?.activeSession?.mode == "FT8",
           let ft8 = ft8Manager
        {
            let ft8Callsign: String? = switch selection {
            case let .pota(spot): spot.activator
            case let .sota(spot): spot.activatorCallsign
            default: nil
            }
            if let callsign = ft8Callsign,
               handleFT8SpotTap(callsign: callsign, ft8: ft8)
            {
                return
            }
        }

        // Return to the operator's own frequency after the hunt, even when tapping
        // a second spot while still tuned to the first (CAR-296).
        preSpotFrequency = sessionManager?.selfSpotFrequency

        switch selection {
        case let .pota(spot):
            applyPOTASpotSelection(spot)
        case let .sota(spot):
            applySOTASpotSelection(spot)
        case let .rbn(spot):
            callsignInput = spot.callsign
            _ = sessionManager?.updateFrequency(spot.frequencyMHz, isTuningToSpot: true)
            ToastManager.shared.info("Loaded \(spot.callsign)")
        case let .p2p(opportunity):
            applyP2POpportunitySelection(opportunity)
        }
    }

    /// Try to start an FT8 call to `callsign` using a recent decode from that
    /// station. Returns true if handled — skip the default spot-tap behaviour
    /// so the FT8 view isn't disrupted by a frequency/form change.
    func handleFT8SpotTap(callsign: String, ft8: FT8SessionManager) -> Bool {
        let upper = callsign.uppercased()
        let match = ft8.enrichedDecodes.reversed().first { enriched in
            enriched.decode.message.callerCallsign?.uppercased() == upper
        }
        if let match {
            ft8.callStation(match.decode)
            ToastManager.shared.info("Calling \(callsign)")
        } else {
            ToastManager.shared.info(
                "\(callsign) not decoded yet — listen on current FT8 band"
            )
        }
        return true
    }

    // MARK: - Per-Source Application

    private func applyPOTASpotSelection(_ spot: POTASpot) {
        callsignInput = spot.activator
        theirPark = spot.reference
        if let freqKHz = spot.frequencyKHz {
            _ = sessionManager?.updateFrequency(freqKHz / 1_000.0, isTuningToSpot: true)
        }
        var noteParts: [String] = [spot.reference]
        if let loc = spot.locationDesc {
            let state = loc.components(separatedBy: "-").last ?? loc
            noteParts.append(state)
        }
        if let parkName = spot.parkName {
            noteParts.append(parkName)
        }
        notes = noteParts.joined(separator: " - ")
        ToastManager.shared.info("Loaded \(spot.activator)")
    }

    private func applySOTASpotSelection(_ spot: SOTASpot) {
        callsignInput = spot.activatorCallsign
        if let freqMHz = spot.frequencyMHz {
            _ = sessionManager?.updateFrequency(freqMHz, isTuningToSpot: true)
        }
        var noteParts: [String] = [spot.fullSummitReference, spot.summitName]
        if spot.points > 0 {
            noteParts.append("\(spot.points)pts")
        }
        notes = noteParts.joined(separator: " - ")
        ToastManager.shared.info("Loaded \(spot.activatorCallsign)")
    }

    private func applyP2POpportunitySelection(_ opportunity: P2POpportunity) {
        callsignInput = opportunity.callsign
        theirPark = opportunity.parkRef
        _ = sessionManager?.updateFrequency(
            opportunity.frequencyMHz, isTuningToSpot: true
        )
        var noteParts: [String] = ["P2P", opportunity.parkRef]
        if let loc = opportunity.locationDesc {
            let state = loc.components(separatedBy: "-").last ?? loc
            noteParts.append(state)
        }
        if let parkName = opportunity.parkName {
            noteParts.append(parkName)
        }
        notes = noteParts.joined(separator: " - ")
        ToastManager.shared.info(
            "P2P: \(opportunity.callsign) @ \(opportunity.parkRef)"
        )
    }
}
