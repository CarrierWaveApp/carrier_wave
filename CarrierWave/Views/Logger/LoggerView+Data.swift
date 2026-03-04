import CarrierWaveData
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
        refreshSpotMismatches()
    }

    /// Refresh all QSOs for the current UTC day (for POTA duplicate detection across sessions)
    /// POTA contacts are unique per callsign + band + park + UTC day, not per session.
    func refreshUTCDayQSOs() {
        guard let session = sessionManager?.activeSession,
              session.isPOTA
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

    // MARK: - Spot Contact Validation

    /// Recompute spot-vs-QSO mismatches for the current session.
    /// Called after QSO list changes (log, edit, delete).
    func refreshSpotMismatches() {
        guard !spotMismatchesDismissed,
              let session = sessionManager?.activeSession
        else {
            spotMismatches = []
            return
        }

        let spots = SpotContactValidator.fetchSessionSpots(
            sessionId: session.id,
            modelContext: modelContext
        )

        // Filter QSOs to non-metadata modes
        let validQSOs = sessionQSOs.filter { qso in
            let mode = qso.mode.uppercased()
            return mode != "WEATHER" && mode != "SOLAR" && mode != "NOTE"
        }

        spotMismatches = SpotContactValidator.findMismatches(
            spots: spots,
            qsos: validQSOs
        )
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
              session.isPOTA,
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

        // SCP partial check — synchronous, <10ms for ~80K callsigns
        updateSCPSuggestions(for: callsign)

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

    /// Parse quick entry and determine callsign for lookup.
    /// Populates form fields (state, grid, park, RST, notes) from parsed tokens
    /// so the fields editor reflects the quick entry values as the user types.
    func resolveCallsignForLookup(_ callsign: String) -> String {
        let trimmed = callsign.trimmingCharacters(in: .whitespaces).uppercased()
        if callsign.contains(" ") {
            quickEntryResult = QuickEntryParser.parse(callsign)
            quickEntryTokens = QuickEntryParser.parseTokens(callsign)
        } else {
            quickEntryResult = nil
            quickEntryTokens = []
        }

        // Push quick entry values into form fields so the editor stays in sync.
        // Skip when input is empty — resetFormAfterLog already handles clearing
        // fields inside its own transaction, and writing here would cause a
        // secondary state update that steals focus from the callsign field.
        if !trimmed.isEmpty {
            populateFieldsFromQuickEntry(quickEntryResult)
        }

        return quickEntryResult?.callsign ?? trimmed
    }

    /// Populate form fields from quick entry result.
    /// Clears fields that the quick entry doesn't provide so previous
    /// quick entry values don't stick when the user changes input.
    private func populateFieldsFromQuickEntry(_ result: QuickEntryResult?) {
        theirState = result?.state ?? ""
        theirGrid = result?.theirGrid ?? ""
        theirPark = result?.theirPark ?? ""
        notes = result?.notes ?? ""

        if let rst = result?.rstSent {
            rstSent = rst
        } else if result?.rstReceived != nil {
            // Single RST applies to both
            rstSent = result?.rstReceived ?? ""
        } else {
            rstSent = ""
        }

        if let rst = result?.rstReceived {
            rstReceived = rst
        } else {
            rstReceived = ""
        }
    }

    // MARK: - SCP (Super Check Partial)

    /// Update callsign suggestions and known-callsign status based on current input.
    /// Merges SCP database with active POTA spot callsigns via CallsignSuggestionProvider.
    func updateSCPSuggestions(for callsign: String) {
        let spotCallsigns = cachedPOTASpots.map(\.activator)

        scpSuggestions = CallsignSuggestionProvider.suggestions(
            for: callsign,
            spotCallsigns: spotCallsigns,
            contactCounts: suggestionContactCounts
        )

        // Known-callsign indicator (border tint)
        let fragment = callsign.trimmingCharacters(in: .whitespaces).uppercased()
        let scpDisabled = UserDefaults.standard.object(forKey: "scpEnabled") as? Bool == false
        if scpDisabled {
            scpCallsignKnown = nil
        } else if fragment.count >= 4 {
            scpCallsignKnown = CallsignSuggestionProvider.contains(
                fragment,
                spotCallsigns: spotCallsigns
            )
        } else if fragment.isEmpty {
            scpCallsignKnown = nil
        }
    }

    // MARK: - Utility

    func formatWebSDRDuration(_ duration: TimeInterval) -> String {
        let total = Int(duration)
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
