import CarrierWaveCore
import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - QSOEntryPopupView + Logic

extension QSOEntryPopupView {
    func parseQuickEntry(_ text: String) {
        guard !text.isEmpty else {
            parsedResult = nil
            if callsign.isEmpty {
                clearCallsignLookup()
            }
            return
        }
        let result = QuickEntryParser.parse(text)
        parsedResult = result

        // Only do callsign lookup from quick entry if dedicated field is empty
        if callsign.isEmpty {
            let detectedCallsign: String? = if let result {
                result.callsign
            } else {
                extractLeadingCallsign(text)
            }
            updateCallsignLookup(
                callsign: detectedCallsign,
                band: result?.band
            )
        }
    }

    func autoDeriveBand(from freqText: String) {
        guard band.isEmpty, let freq = Double(freqText), freq > 0 else {
            return
        }
        if let derived = BandUtilities.deriveBand(from: freq * 1_000) {
            band = derived
        }
    }

    func logQSO() {
        let finalCallsign = resolvedCallsign
        guard !finalCallsign.isEmpty else {
            return
        }

        let qso = buildQSO(callsign: finalCallsign)
        let session = cachedActiveSession

        if let session {
            qso.loggingSessionId = session.id
            qso.cloudDirtyFlag = true
            qso.modifiedAt = Date()
        }

        modelContext.insert(qso)
        session?.incrementQSOCount()
        try? CwStoreSeams.save(modelContext, qsos: [qso], sessions: session.map { [$0] } ?? [])

        history.append(quickEntryText.isEmpty ? finalCallsign : quickEntryText)
        historyIndex = nil
        lastLoggedCallsign = finalCallsign
        logCount += 1
        clearAll()
    }

    func buildQSO(callsign: String) -> QSO {
        let session = cachedActiveSession
        let finalMode = mode.uppercased()
        return QSO(
            callsign: callsign,
            band: resolvedBand ?? "Unknown",
            mode: finalMode,
            frequency: resolvedFrequency,
            timestamp: Date(),
            rstSent: effectiveRST(dedicated: rstSent, parsed: parsedResult?.rstSent, mode: finalMode),
            rstReceived: effectiveRST(dedicated: rstReceived, parsed: parsedResult?.rstReceived, mode: finalMode),
            myCallsign: session?.myCallsign ?? currentCallsign,
            myGrid: session?.myGrid,
            theirGrid: effectiveValue(theirGrid, parsedResult?.theirGrid),
            parkReference: session?.parkReference,
            theirParkReference: effectiveValue(theirPark, parsedResult?.theirPark),
            notes: notes.isEmpty ? nil : notes,
            importSource: .logger,
            name: name.isEmpty ? nil : name,
            qth: qth.isEmpty ? nil : qth,
            state: effectiveValue(state, parsedResult?.state),
            power: session?.power ?? Int(power)
        )
    }

    func loadActiveSession() {
        var descriptor = FetchDescriptor<LoggingSession>(
            predicate: #Predicate<LoggingSession> { session in
                session.statusRawValue == "active"
                    && session.activationTypeRawValue != "casual"
            },
            sortBy: [SortDescriptor(\LoggingSession.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        cachedActiveSession = try? modelContext.fetch(descriptor).first
    }

    func effectiveValue(
        _ dedicated: String,
        _ parsed: String?
    ) -> String? {
        if !dedicated.isEmpty {
            return dedicated.uppercased()
        }
        return parsed
    }

    func effectiveRST(
        dedicated: String,
        parsed: String?,
        mode: String
    ) -> String {
        if !dedicated.isEmpty, dedicated != defaultRSTFor(mode) {
            return dedicated
        }
        if let parsed {
            return parsed
        }
        return dedicated.isEmpty ? defaultRSTFor(mode) : dedicated
    }

    func defaultRSTFor(_ mode: String) -> String {
        mode == "SSB" ? "59" : "599"
    }

    func clearAll() {
        quickEntryText = ""
        parsedResult = nil
        callsign = ""
        frequency = ""
        band = ""
        rstSent = "599"
        rstReceived = "599"
        theirGrid = ""
        theirPark = ""
        state = ""
        notes = ""
        name = ""
        qth = ""
        power = ""
        clearCallsignLookup()
        isQuickEntryFocused = true
    }

    func populateFromSpot(_ enrichedSpot: EnrichedSpot) {
        let spot = enrichedSpot.spot

        // Clear existing fields first
        clearAll()

        // Build quick entry text (callsign freq mode)
        let freqStr = String(format: "%.3f", spot.frequencyMHz)
        let spotMode = spot.mode
        quickEntryText = spotMode.isEmpty
            ? "\(spot.callsign) \(freqStr)"
            : "\(spot.callsign) \(freqStr) \(spotMode)"
        parseQuickEntry(quickEntryText)

        // Core dedicated fields
        callsign = spot.callsign.uppercased()
        frequency = freqStr
        if !spotMode.isEmpty {
            mode = spotMode.uppercased()
            rstSent = defaultRSTFor(mode)
            rstReceived = defaultRSTFor(mode)
        }
        let derivedBand = spot.band
        if !derivedBand.isEmpty {
            band = derivedBand
        }

        // Grid from spot data
        if let grid = spot.dxGrid, !grid.isEmpty {
            theirGrid = grid
        }

        // Park/SOTA/WWFF references
        if let parkRef = spot.parkRef, !parkRef.isEmpty {
            theirPark = parkRef
        } else if let summitCode = spot.summitCode, !summitCode.isEmpty {
            theirPark = summitCode
        } else if let wwffRef = spot.wwffRef, !wwffRef.isEmpty {
            theirPark = wwffRef
        }

        // State from enriched data or spot data
        if let spotState = enrichedSpot.state, !spotState.isEmpty {
            state = spotState
        } else if let stateAbbr = spot.stateAbbr, !stateAbbr.isEmpty {
            state = stateAbbr
        }

        // Comments as notes
        if let spotComments = spot.comments, !spotComments.isEmpty {
            notes = spotComments
        }

        // Trigger callsign lookup — will auto-fill name/grid/qth
        updateCallsignLookup(
            callsign: callsign,
            band: band.isEmpty ? nil : band
        )

        isQuickEntryFocused = true
    }

    func recallHistory(direction: HistoryDirection) {
        guard !history.isEmpty else {
            return
        }
        switch direction {
        case .up:
            if let index = historyIndex {
                let newIndex = max(0, index - 1)
                historyIndex = newIndex
                quickEntryText = history[newIndex]
            } else {
                historyIndex = history.count - 1
                quickEntryText = history[history.count - 1]
            }
        case .down:
            if let index = historyIndex {
                let newIndex = index + 1
                if newIndex >= history.count {
                    historyIndex = nil
                    quickEntryText = ""
                } else {
                    historyIndex = newIndex
                    quickEntryText = history[newIndex]
                }
            }
        }
    }
}
