import CarrierWaveCore
import SwiftData
import SwiftUI

// MARK: - LoggerView Data & Lookup

extension LoggerView {
    // MARK: - Session QSO Refresh

    /// Refresh the session QSOs from SwiftData
    func refreshSessionQSOs() {
        guard let session = sessionManager?.activeSession else {
            sessionQSOs = []
            return
        }

        let sessionId = session.id
        let predicate = #Predicate<QSO> { qso in
            qso.loggingSessionId == sessionId && !qso.isHidden
        }
        let descriptor = FetchDescriptor<QSO>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )

        do {
            sessionQSOs = try modelContext.fetch(descriptor)
        } catch {
            sessionQSOs = []
        }
        refreshUTCDayQSOs()
    }

    /// Refresh all QSOs for the current UTC day (for POTA duplicate detection across sessions)
    /// POTA contacts are unique per callsign + band + park + UTC day, not per session.
    func refreshUTCDayQSOs() {
        guard let session = sessionManager?.activeSession,
              session.activationType == .pota
        else {
            utcDayQSOs = []
            return
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let startOfDay = calendar.startOfDay(for: Date())
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        let predicate = #Predicate<QSO> { qso in
            !qso.isHidden
                && qso.timestamp >= startOfDay
                && qso.timestamp < endOfDay
                && qso.parkReference != nil
        }
        var descriptor = FetchDescriptor<QSO>(predicate: predicate)
        descriptor.fetchLimit = 5_000

        do {
            utcDayQSOs = try modelContext.fetch(descriptor)
        } catch {
            utcDayQSOs = []
        }
    }

    /// Refresh the list of active/paused sessions (for the no-session view)
    func refreshActiveSessions() {
        guard let manager = sessionManager else {
            activeSessions = []
            activeSessionQSOCounts = [:]
            return
        }

        activeSessions = manager.fetchActiveSessions()

        // Load QSO counts for each active session
        var counts: [UUID: Int] = [:]
        for session in activeSessions {
            let sessionId = session.id
            var descriptor = FetchDescriptor<QSO>(
                predicate: #Predicate { $0.loggingSessionId == sessionId && !$0.isHidden }
            )
            descriptor.fetchLimit = 500
            counts[sessionId] = (try? modelContext.fetch(descriptor))?.count ?? 0
        }
        activeSessionQSOCounts = counts
    }

    // MARK: - POTA Spots

    /// Refresh POTA spots for nearby frequency detection
    func refreshPOTASpots() async {
        // Only fetch if we have an active session
        guard sessionManager?.hasActiveSession == true else {
            return
        }

        // Throttle fetches to at most once per 30 seconds
        if let lastFetch = spotsLastFetched,
           Date().timeIntervalSince(lastFetch) < 30
        {
            return
        }

        do {
            let client = POTAClient(authService: POTAAuthService())
            let spots = try await client.fetchActiveSpots()
            await MainActor.run {
                cachedPOTASpots = spots
                spotsLastFetched = Date()
            }
        } catch {
            // Silently fail - spots are a nice-to-have
        }
    }

    // MARK: - POTA Duplicate Detection

    /// Compute POTA duplicate status - called only when callsign changes
    func computePotaDuplicateStatus() -> POTACallsignStatus? {
        // Don't show duplicate status when editing an existing QSO
        guard editingQSO == nil else {
            return nil
        }

        guard let session = sessionManager?.activeSession,
              session.activationType == .pota,
              !callsignInput.isEmpty,
              callsignInput.count >= 3,
              detectedCommand == nil
        else {
            return nil
        }

        // Use parsed callsign in quick entry mode, otherwise use raw input
        let callsign: String =
            if let qeResult = quickEntryResult {
                qeResult.callsign.uppercased()
            } else {
                callsignInput.uppercased()
            }
        let currentBand = session.band ?? "Unknown"

        // Search all QSOs for the UTC day at the current park (not just this session).
        // POTA contacts are unique per callsign + band + park + UTC day.
        let currentPark = session.parkReference?.uppercased()
        let matchingQSOs = utcDayQSOs.filter { qso in
            qso.callsign.uppercased() == callsign
                && qso.parkReference?.uppercased() == currentPark
        }

        if matchingQSOs.isEmpty {
            return .firstContact
        }

        let previousBands = Set(matchingQSOs.map(\.band))

        if previousBands.contains(currentBand) {
            return .duplicateBand(band: currentBand)
        } else {
            return .newBand(previousBands: Array(previousBands).sorted())
        }
    }

    // MARK: - Callsign Lookup

    func onCallsignChanged(_ callsign: String) {
        lookupTask?.cancel()

        // Update cached POTA duplicate status (avoids expensive computation on every render)
        cachedPotaDuplicateStatus = computePotaDuplicateStatus()

        let callsignForLookup = resolveCallsignForLookup(callsign)

        // Don't lookup if too short or looks like a command
        // When input is empty, preserve lookupResult so the QRZ card stays visible
        // after logging (card persists until user starts typing next callsign)
        guard callsignForLookup.count >= 3,
              LoggerCommand.parse(callsignForLookup) == nil
        else {
            if !callsignForLookup.isEmpty {
                lookupResult = nil
            }
            lookupError = nil
            previousQSOCount = 0
            return
        }

        // Extract the primary callsign for lookup (strip prefix/suffix)
        let primaryCallsign = extractPrimaryCallsign(callsignForLookup)

        // Don't lookup if primary is too short
        guard primaryCallsign.count >= 3 else {
            lookupResult = nil
            lookupError = nil
            previousQSOCount = 0
            return
        }

        let service = CallsignLookupService(modelContext: modelContext)
        lookupTask = Task {
            // Small delay to avoid excessive lookups while typing
            try? await Task.sleep(for: .milliseconds(300))

            guard !Task.isCancelled else {
                return
            }

            let result = await service.lookupWithResult(primaryCallsign)
            let count = fetchPreviousQSOCount(for: primaryCallsign)

            guard !Task.isCancelled else {
                return
            }

            await MainActor.run {
                lookupResult = result.info
                previousQSOCount = count
                // Only show actionable errors (not "not found" which is normal)
                if result.error == .notFound {
                    lookupError = nil
                } else {
                    lookupError = result.error
                }
            }
        }
    }

    /// Count all-time QSOs with a callsign (excludes hidden and metadata modes)
    func fetchPreviousQSOCount(for callsign: String) -> Int {
        let upper = callsign.uppercased()
        return
            (try? modelContext.fetchCount(
                FetchDescriptor<QSO>(
                    predicate: #Predicate<QSO> { qso in
                        qso.callsign == upper
                            && !qso.isHidden
                            && qso.mode != "WEATHER"
                            && qso.mode != "SOLAR"
                            && qso.mode != "NOTE"
                    }
                )
            )) ?? 0
    }

    // MARK: - Callsign Parsing

    /// Extract the primary callsign from a potentially prefixed/suffixed callsign
    /// e.g., "I/W6JSV/P" -> "W6JSV", "VE3/W6JSV" -> "W6JSV", "W6JSV/M" -> "W6JSV"
    func extractPrimaryCallsign(_ callsign: String) -> String {
        let parts = callsign.split(separator: "/").map(String.init)

        guard parts.count > 1 else {
            return callsign
        }

        // Common suffixes that indicate the primary is before them
        let knownSuffixes = Set(["P", "M", "MM", "AM", "QRP", "R", "A", "B"])

        // For 2 parts: check if second part is a known suffix or very short (1-2 chars)
        // If so, first part is primary. Otherwise, longer part is likely primary.
        if parts.count == 2 {
            let first = parts[0]
            let second = parts[1]

            // If second is a known suffix, first is primary
            if knownSuffixes.contains(second.uppercased()) {
                return first
            }

            // If second is very short (1-2 chars), it's likely a suffix
            if second.count <= 2 {
                return first
            }

            // If first is very short (1-2 chars), it's likely a country prefix
            if first.count <= 2 {
                return second
            }

            // Otherwise, return the longer one (more likely to be the full callsign)
            return first.count >= second.count ? first : second
        }

        // For 3 parts (prefix/call/suffix): middle is primary
        if parts.count == 3 {
            return parts[1]
        }

        // Fallback: return the longest part
        return parts.max(by: { $0.count < $1.count }) ?? callsign
    }

    /// Parse quick entry and determine callsign for lookup
    func resolveCallsignForLookup(_ callsign: String) -> String {
        let trimmed = callsign.trimmingCharacters(in: .whitespaces).uppercased()
        if callsign.contains(" ") {
            quickEntryResult = QuickEntryParser.parse(callsign)
            quickEntryTokens = QuickEntryParser.parseTokens(callsign)
        } else {
            quickEntryResult = nil
            quickEntryTokens = []
        }
        return quickEntryResult?.callsign ?? trimmed
    }

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
        if !callsignInput.isEmpty,
           closestSpot.activator.uppercased() == callsignInput.uppercased()
        {
            return nil
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

    // MARK: - Utility

    func formatWebSDRDuration(_ duration: TimeInterval) -> String {
        let total = Int(duration)
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
