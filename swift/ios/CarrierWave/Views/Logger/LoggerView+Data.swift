import CarrierWaveCore
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
        let descriptor = BoundedDescriptor<QSO>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)],
            limit: BoundedDescriptor<QSO>.maxLimit
        )

        do {
            sessionQSOs = try modelContext.boundedFetch(descriptor)
        } catch {
            sessionQSOs = []
        }
        RadioService.shared.cwSerialNumber = sessionQSOs.count + 1
        refreshUTCDayQSOs()
        refreshSpotMismatches()
    }

    /// Refresh all QSOs for the current UTC day (for duplicate detection across sessions).
    /// Dupe = same callsign + band + UTC day. POTA additionally scopes by park.
    func refreshUTCDayQSOs() {
        guard sessionManager?.activeSession != nil else {
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
        }
        let descriptor = BoundedDescriptor<QSO>(
            predicate: predicate,
            limit: BoundedDescriptor<QSO>.maxLimit
        )

        do {
            utcDayQSOs = try modelContext.boundedFetch(descriptor)
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
        let validQSOs = sessionQSOs.filter { !QSOMode.isMetadata($0.mode) }

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

        // SOTA spots come from a different feed (sotawatch). Run it
        // unconditionally so S2S enrichment stays current — the previous
        // wiring put it after POTA's 30s early-return, which meant SOTA
        // silently never fetched if the user typed within 30s of opening
        // the logger. SOTA has its own throttle internally.
        await refreshSOTASpots()

        // Throttle POTA fetches to at most once per 30 seconds
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
            NetworkHealthMonitor.shared.reportSuccess()
        } catch {
            NetworkHealthMonitor.shared.reportFailure(error)
        }
    }

    // MARK: - Duplicate Detection

    /// Compute duplicate status for the current callsign input — called on callsign change.
    /// For POTA sessions, scopes by park (callsign + band + park + UTC day).
    /// For all other sessions, scopes by callsign + band + UTC day.
    func computeDuplicateStatus() -> CallsignDuplicateStatus? {
        guard editingQSO == nil else {
            return nil
        }
        guard let session = sessionManager?.activeSession,
              !callsignInput.isEmpty,
              callsignInput.count >= 3,
              detectedCommand == nil
        else {
            return nil
        }

        let callsign: String
        let currentBand: String?
        let currentModeVal: String
        if let qeResult = quickEntryResult {
            callsign = qeResult.callsign.uppercased()
            if let qeFreq = qeResult.frequency {
                currentBand = LoggingSession.bandForFrequency(qeFreq)
            } else {
                currentBand = session.band
            }
            currentModeVal = qeResult.mode ?? session.mode
        } else {
            callsign = callsignInput.uppercased()
            currentBand = session.band
            currentModeVal = session.mode
        }

        // Classification runs in the shared Rust core
        // (`FieldStore.activationDuplicateStatus`) — the activator's side of the
        // hunter dedup, scoped to the operator's own activation park. The store
        // read is a single indexed point-query (cheaper than the prior in-memory
        // scan of the day's QSOs). Returns nil if the seam is unavailable.
        guard let store = SeamWriteBatchRegistry.current?.store else {
            return nil
        }
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(identifier: "UTC")!
        let dayStart = Int64(utcCalendar.startOfDay(for: Date()).timeIntervalSince1970)
        guard let ffi = try? store.activationDuplicateStatus(
            callsign: callsign,
            band: currentBand,
            mode: currentModeVal,
            myPark: session.isPOTA ? session.parkReference : nil,
            isPota: session.isPOTA,
            dayStart: dayStart
        ) else {
            return nil
        }
        return CallsignDuplicateStatus(ffi: ffi)
    }

    // MARK: - Callsign Lookup

    func onCallsignChanged(_ callsign: String) {
        // Drop any contest-exchange fields we auto-filled for the previous
        // callsign once the input is empty. Keeps user-typed values intact.
        if callsign.isEmpty {
            clearAutoPrefilledContestFields()
        }

        // SCP partial check — synchronous, <10ms for ~80K callsigns
        updateSCPSuggestions(for: callsign)

        // Contest dupe check
        checkContestDupe(callsign)

        let callsignForLookup = resolveCallsignForLookup(callsign)

        // Update cached duplicate status AFTER quick entry parsing so band/mode overrides apply
        cachedDuplicateStatus = computeDuplicateStatus()

        // P2P enrichment: cross-reference against active POTA spots
        updatePOTASpotMatches(for: callsignForLookup)
        // S2S enrichment: cross-reference against active SOTA spots so the
        // Summit field auto-fills when the contacted op is currently spotted.
        updateSOTASpotMatches(for: callsignForLookup)

        // Determine the callsigns that need lookup
        let currentCallsigns: [String] = if let multiResults = quickEntryMultiResults, multiResults.count >= 2 {
            multiResults.map { $0.callsign.uppercased() }
        } else {
            [callsignForLookup.uppercased()]
        }

        // Skip lookup if detected callsigns haven't changed (only metadata tokens changed)
        guard currentCallsigns != lastLookedUpCallsigns else {
            return
        }
        lastLookedUpCallsigns = currentCallsigns
        lookupTask?.cancel()

        // Multi-callsign path: look up only new/changed callsigns
        if let multiResults = quickEntryMultiResults, multiResults.count >= 2 {
            performMultiCallsignLookup(multiResults)
            return
        }

        // Clear multi-lookup state when back to single callsign
        if !multiLookupResults.isEmpty {
            multiLookupResults = []
            selectedMultiLookupIndex = 0
        }

        performSingleCallsignLookup(callsignForLookup)
    }

    /// Look up a single callsign via QRZ/cache
    func performSingleCallsignLookup(_ callsignForLookup: String) {
        // Don't lookup if too short or looks like a command
        // When input is empty, preserve lookupResult so the QRZ card stays visible
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

        let primaryCallsign = extractPrimaryCallsign(callsignForLookup)
        guard primaryCallsign.count >= 3 else {
            lookupResult = nil
            lookupError = nil
            previousQSOCount = 0
            return
        }

        // Clear stale error immediately so it doesn't flash during debounce
        lookupError = nil

        let service = CallsignLookupService(modelContext: modelContext)
        lookupTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else {
                return
            }

            let count = fetchPreviousQSOCount(for: primaryCallsign)
            await MainActor.run {
                previousQSOCount = count
            }

            // Streamed lookup: cached row first (instant from disk), enriched
            // row once QRZ/HamDB resolves.
            for await result in service.lookupStream(primaryCallsign) {
                guard !Task.isCancelled else {
                    return
                }
                await MainActor.run {
                    lookupResult = result.info
                    if result.error == .notFound {
                        lookupError = nil
                    } else {
                        lookupError = result.error
                    }
                }
                prefillContestExchangeFromEnrichment(for: primaryCallsign)
            }
        }
    }

    /// Count all-time QSOs with a callsign (excludes hidden and metadata modes)
    func fetchPreviousQSOCount(for callsign: String) -> Int {
        let upper = callsign.uppercased()
        return
            (try? modelContext.boundedCount(
                QSO.self,
                predicate: #Predicate<QSO> { qso in
                    qso.callsign == upper
                        && !qso.isHidden
                        && qso.mode != "WEATHER"
                        && qso.mode != "SOLAR"
                        && qso.mode != "NOTE"
                }
            )) ?? 0
    }

    // MARK: - Callsign Parsing

    /// Extract the primary callsign from a potentially prefixed/suffixed callsign
    /// e.g., "I/W6JSV/P" -> "W6JSV", "VE3/W6JSV" -> "W6JSV", "W6JSV/M" -> "W6JSV"
    func extractPrimaryCallsign(_ callsign: String) -> String {
        CallsignParsing.primaryCallsign(from: callsign)
    }

    /// Parse quick entry and determine callsign for lookup.
    /// Populates form fields (state, grid, park, RST, notes) from parsed tokens
    /// so the fields editor reflects the quick entry values as the user types.
    func resolveCallsignForLookup(_ callsign: String) -> String {
        let trimmed = callsign.trimmingCharacters(in: .whitespaces).uppercased()
        if callsign.contains(" ") {
            // Try multi-callsign parse first
            let order = rstParseOrder
            let multiResults = QuickEntryParser.parseMulti(callsign, rstOrder: order)
            if let multi = multiResults, multi.count >= 2 {
                quickEntryMultiResults = multi
                quickEntryResult = multi.first
                quickEntryTokens = QuickEntryParser.parseMultiTokens(callsign, rstOrder: order)
            } else {
                quickEntryMultiResults = nil
                quickEntryResult = QuickEntryParser.parse(callsign, rstOrder: order)
                quickEntryTokens = QuickEntryParser.parseTokens(callsign, rstOrder: order)
            }
        } else {
            quickEntryResult = nil
            quickEntryMultiResults = nil
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

    // MARK: - POTA P2P Enrichment

    /// Cross-reference callsign against active POTA spots for P2P detection
    /// and park enrichment display.
    /// Runs after populateFieldsFromQuickEntry so auto-fill doesn't get overwritten.
    func updatePOTASpotMatches(for callsign: String) {
        let normalized = POTASpot.normalizeCallsign(callsign)
        guard normalized.count >= 3 else {
            potaSpotMatches = []
            spotMatchPark = nil
            return
        }
        let matches = cachedPOTASpots.filter {
            POTASpot.normalizeCallsign($0.activator) == normalized
        }

        spotMatchPark = matches.first?.reference

        // P2P park enrichment only applies during POTA activations
        guard sessionManager?.activeSession?.parkReference != nil else {
            if !potaSpotMatches.isEmpty {
                potaSpotMatches = []
            }
            return
        }
        potaSpotMatches = matches
        // Auto-populate theirPark if empty (quick entry didn't set one)
        if !matches.isEmpty, theirPark.isEmpty {
            let refs: [String] = matches.map(\.reference)
            let unique = Array(Set(refs)).sorted()
            theirPark = unique.joined(separator: ",")
        }
    }
}
