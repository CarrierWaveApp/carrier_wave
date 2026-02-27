import CarrierWaveCore
import SwiftUI

// MARK: - LoggerView Frequency Warnings

extension LoggerView {
    // MARK: - Frequency Warnings

    /// Current frequency warning (if any) - includes license violations, activity warnings,
    /// and nearby spots. The spotCount parameter forces SwiftUI to re-evaluate when cached
    /// spots change.
    func computeCurrentWarning(spotCount: Int, inputText: String) -> FrequencyWarning? {
        // Reference parameters to silence unused parameter warnings
        _ = spotCount
        _ = inputText

        guard let session = sessionManager?.activeSession else {
            return nil
        }

        // Check both the session frequency AND any frequency being typed as a command
        let freq: Double
        if case let .frequency(typedFreq) = detectedCommand {
            // User is typing a frequency command - check that frequency
            freq = typedFreq
        } else if let sessionFreq = session.frequency {
            // Use the session's current frequency
            freq = sessionFreq
        } else {
            return nil
        }

        var warnings = BandPlanService.validateFrequency(
            frequencyMHz: freq,
            mode: session.mode,
            license: userLicenseClass
        )

        // Check for nearby POTA spots
        if let nearbyWarning = checkNearbySpots(frequencyMHz: freq, mode: session.mode) {
            warnings.append(nearbyWarning)
            warnings.sort { $0.priority < $1.priority }
        }

        // Return the highest priority warning not dismissed
        return warnings.first { !dismissedWarnings.contains($0.message) }
    }

    /// Tolerance for nearby spot detection based on mode
    func spotToleranceKHz(for mode: String) -> Double {
        let normalizedMode = mode.uppercased()
        // CW is narrower, SSB/phone is wider
        if normalizedMode == "CW" {
            return 2.0
        } else if ["SSB", "USB", "LSB", "PHONE", "AM"].contains(normalizedMode) {
            return 3.0
        } else {
            // Digital modes, etc.
            return 3.0
        }
    }

    /// Check if there are POTA spots near the current frequency
    func checkNearbySpots(frequencyMHz: Double, mode: String) -> FrequencyWarning? {
        // FT8/FT4 always operate on the same frequency — nearby spot warnings are noise
        let upperMode = mode.uppercased()
        if upperMode == "FT8" || upperMode == "FT4" {
            return nil
        }

        let tolerance = spotToleranceKHz(for: mode)
        let freqKHz = frequencyMHz * 1_000

        // Find spots within tolerance
        let nearbySpots = cachedPOTASpots.filter { spot in
            guard let spotFreqKHz = spot.frequencyKHz else {
                return false
            }
            let distanceKHz = abs(spotFreqKHz - freqKHz)
            return distanceKHz <= tolerance
        }

        guard
            let closestSpot = nearbySpots.min(by: { spot1, spot2 in
                guard let freq1 = spot1.frequencyKHz, let freq2 = spot2.frequencyKHz else {
                    return false
                }
                return abs(freq1 - freqKHz) < abs(freq2 - freqKHz)
            })
        else {
            return nil
        }

        // Don't warn about our own spots
        if let myCallsign = sessionManager?.activeSession?.myCallsign,
           closestSpot.activator.uppercased().hasPrefix(myCallsign.uppercased())
        {
            return nil
        }

        // Don't warn about the spot we're actively trying to work
        // Extract just the callsign from quick-entry input (e.g. "W7PFB 599" → "W7PFB")
        if !callsignInput.isEmpty {
            let inputCallsign: String = if let qeResult = QuickEntryParser.parse(callsignInput) {
                qeResult.callsign.uppercased()
            } else {
                callsignInput
                    .split(separator: " ").first.map(String.init)?.uppercased() ?? ""
            }
            if !inputCallsign.isEmpty,
               closestSpot.activator.uppercased() == inputCallsign
            {
                return nil
            }
        }

        return buildNearbySpotWarning(spot: closestSpot, freqKHz: freqKHz, mode: mode)
    }

    /// Build a FrequencyWarning with detailed context for a nearby spot
    func buildNearbySpotWarning(
        spot: POTASpot,
        freqKHz: Double,
        mode: String
    ) -> FrequencyWarning? {
        guard let spotFreqKHz = spot.frequencyKHz else {
            return nil
        }
        let distanceKHz = abs(spotFreqKHz - freqKHz)
        let distanceStr =
            distanceKHz < 0.1 ? "same frequency" : String(format: "%.1f kHz away", distanceKHz)

        // Build context details
        var details: [String] = [distanceStr]

        // Mode comparison
        let spotMode = spot.mode.uppercased()
        let currentModeUpper = mode.uppercased()
        if spotMode == currentModeUpper {
            details.append("same mode (\(spot.mode))")
        } else {
            details.append("mode: \(spot.mode)")
        }

        // How fresh is the spot
        let timeAgo = spot.timeAgo
        if !timeAgo.isEmpty {
            details.append("spotted \(timeAgo)")
        }

        // Spotter info (RBN vs human)
        if spot.isAutomatedSpot {
            details.append("via RBN")
        } else {
            details.append("by \(spot.spotter)")
        }

        // Location
        if let location = spot.locationDesc, !location.isEmpty {
            details.append(location)
        }

        // Park info for the message
        let parkInfo =
            if let parkName = spot.parkName {
                "\(spot.reference) - \(parkName)"
            } else {
                spot.reference
            }

        return FrequencyWarning(
            type: .spotNearby,
            message: "\(spot.activator) at \(parkInfo)",
            suggestion: details.joined(separator: " \u{2022} ")
        )
    }
}
