import CarrierWaveCore
import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - LoggerView QSO Logging

extension LoggerView {
    // MARK: - Input Handling

    func handleInputSubmit() {
        // Check if it's a command — routed through the shared Rust handler.
        if let command = LoggerCommand.parse(callsignInput) {
            runLoggerCommand(callsignInput, fallback: command)
            callsignInput = ""
            quickEntryResult = nil
            quickEntryMultiResults = nil
            quickEntryTokens = []
            lastLookedUpCallsigns = []
            return
        }

        // If editing an existing QSO, always route through logQSO (which handles edits)
        if editingQSO != nil, canLog {
            logQSO()
            return
        }

        // Check for multi-callsign quick entry
        if let multiResults = quickEntryMultiResults, multiResults.count >= 2, canLog {
            logMultiQuickEntry(multiResults)
            return
        }

        // Check for single quick entry mode
        if quickEntryResult != nil, canLog {
            logQuickEntry()
            return
        }

        // Otherwise try to log normally
        if canLog {
            logQSO()
        }
    }

    // MARK: - Log QSO

    func logQSO() {
        guard canLog else {
            return
        }

        // SCP did-you-mean check: if callsign is not in database, suggest near matches
        let scpWarning = UserDefaults.standard.object(forKey: "scpWarningEnabled") as? Bool ?? false
        if scpWarning, editingQSO == nil, scpCallsignKnown == false {
            let db = SCPService.shared.database
            let callsign = callsignInput.trimmingCharacters(in: .whitespaces).uppercased()
            let near = db.nearMatches(for: callsign, maxDistance: 1)
            if !near.isEmpty {
                scpDidYouMeanSuggestions = near
                showSCPDidYouMean = true
                return
            }
        }

        logQSOConfirmed()
    }

    /// Actually log the QSO (called directly or after SCP did-you-mean dismissal).
    func logQSOConfirmed() {
        guard canLog else {
            return
        }

        // Check if we're editing an existing QSO
        if let qsoToUpdate = editingQSO {
            updateExistingQSOCallsign(qsoToUpdate)
            return
        }

        // Build field values with fallback: form > lookup
        let gridToUse = theirGrid.nonEmpty ?? lookupResult?.grid
        let stateToUse = theirState.nonEmpty ?? lookupResult?.state

        // Capture callsign and QRZ info before form reset for QRQ Crew check
        let typedCallsign = callsignInput.trimmingCharacters(in: .whitespaces).uppercased()
        let loggedLookup = lookupResult

        // When QRZ redirected, log the canonical (new) callsign instead
        let loggedCallsign = lookupResult?.callsignChangeNote != nil
            ? lookupResult?.callsign ?? typedCallsign : typedCallsign

        // Build callsign change note when QRZ redirected to a different call
        let changeNote = buildCallsignChangeNote(
            loggedCallsign: typedCallsign
        )

        // Contest exchange fields
        let exchReceived = isContestSession ? buildContestExchange() : nil
        let serialSent = isContestSession ? contestManager?.currentSerial : nil

        let logged = sessionManager?.logQSO(
            callsign: loggedCallsign,
            rstSent: rstSent.nonEmpty ?? defaultRST,
            rstReceived: rstReceived.nonEmpty ?? defaultRST,
            theirGrid: gridToUse,
            theirParkReference: theirPark.nonEmpty,
            notes: notes.nonEmpty,
            name: lookupResult?.name,
            operatorName: operatorName.nonEmpty ?? lookupResult?.displayName,
            state: stateToUse,
            country: lookupResult?.country,
            qth: lookupResult?.qth,
            theirLicenseClass: lookupResult?.licenseClass,
            aoaCode: aoaCode.nonEmpty,
            callsignChangeNote: changeNote,
            contestExchangeSent: isContestSession ? buildSentExchange() : nil,
            contestExchangeReceived: exchReceived,
            contestSerialSent: serialSent,
            contestSerialReceived: nil
        )

        // S2S summit ref + contest scoring both need the live QSO. logQSO returns a
        // value snapshot, so re-fetch via the id-bridge (this view is already
        // SwiftData-coupled) only on the branches that need it.
        if let logged, theirSummit.nonEmpty != nil || isContestSession,
           let qso = LogbookIDBridge.fetchQSO(id: logged.id, in: modelContext)
        {
            if let summit = theirSummit.nonEmpty {
                qso.sotaRef = summit.uppercased()
            }
            if isContestSession {
                registerContestQSO(qso, exchangeReceived: exchReceived ?? "")
            }
        }

        finalizeAfterLog(theirCallsign: loggedCallsign, theirQRZInfo: loggedLookup)
    }

    /// Common post-log cleanup: haptics, refresh, form reset, QRQ Crew check
    private func finalizeAfterLog(theirCallsign: String, theirQRZInfo: CallsignInfo?) {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        viewingParkOverride = nil
        refreshSessionQSOs()
        restorePreSpotFrequency()
        resetFormAfterLog()
        if isContestSession {
            resetContestFields()
        }
        checkQRQCrewSpot(theirCallsign: theirCallsign, theirQRZInfo: theirQRZInfo)
    }

    /// Update an existing QSO with current form field values
    func updateExistingQSOCallsign(_ qso: QSO) {
        let newCallsign: String = if let qeResult = quickEntryResult {
            qeResult.callsign.trimmingCharacters(in: .whitespaces).uppercased()
        } else {
            callsignInput.trimmingCharacters(in: .whitespaces).uppercased()
        }

        guard !newCallsign.isEmpty else {
            ToastManager.shared.error("Callsign cannot be empty")
            return
        }

        // Preserve the very-first contact callsign so download-merge can match
        // against the pre-edit value. See CAR-245.
        if qso.originalCallsign == nil, qso.callsign != newCallsign,
           !qso.callsign.trimmingCharacters(in: .whitespaces).isEmpty
        {
            qso.originalCallsign = qso.callsign
        }
        qso.callsign = newCallsign
        applyFormFieldsToQSO(qso)
        applyLookupToEditedQSO(qso, callsign: newCallsign)

        qso.cloudDirtyFlag = true
        qso.modifiedAt = Date()
        try? modelContext.save()

        refreshSessionQSOs()
        resetFormAfterLog()
        editingQSO = nil
        ToastManager.shared.success("QSO updated")
    }

    /// Apply quick entry and form field values to a QSO being edited
    private func applyFormFieldsToQSO(_ qso: QSO) {
        if let v = quickEntryResult?.state.nonEmpty ?? theirState.nonEmpty {
            qso.state = v
        }
        if let v = quickEntryResult?.theirGrid.nonEmpty ?? theirGrid.nonEmpty {
            qso.theirGrid = v
        }
        if let v = quickEntryResult?.theirPark.nonEmpty ?? theirPark.nonEmpty {
            qso.theirParkReference = v
        }
        if let v = theirSummit.nonEmpty {
            qso.sotaRef = v.uppercased()
        }
        if let v = quickEntryResult?.notes.nonEmpty ?? notes.nonEmpty {
            qso.notes = v
            // User typed notes in the logger form — tag as user-authored. CAR-243.
            qso.notesUserAuthored = true
        }
        if let v = quickEntryResult?.rstSent ?? rstSent.nonEmpty {
            qso.rstSent = v
        }
        if let v = quickEntryResult?.rstReceived ?? rstReceived.nonEmpty {
            qso.rstReceived = v
        }
        if let v = aoaCode.nonEmpty {
            qso.aoaCode = v
        }
    }

    /// Apply callsign lookup data to an edited QSO, or fetch if no match
    private func applyLookupToEditedQSO(_ qso: QSO, callsign: String) {
        let primaryCallsign = extractPrimaryCallsign(callsign)
        if let info = lookupResult, info.callsign == primaryCallsign {
            qso.name = info.name
            if qso.theirGrid == nil {
                qso.theirGrid = info.grid
            }
            if qso.state == nil {
                qso.state = info.state
            }
            qso.country = info.country
            qso.qth = info.qth
            qso.theirLicenseClass = info.licenseClass
            if info.callsignChangeNote != nil {
                qso.callsignChangeNote =
                    "Logged as \(callsign) but operator changed to \(info.callsign)"
            }
        } else {
            Task { await fetchAndUpdateQSOMetadata(qso, callsign: callsign) }
        }
    }

    /// Fetch callsign metadata and update QSO (called when editing without existing lookup)
    func fetchAndUpdateQSOMetadata(_ qso: QSO, callsign: String) async {
        let service = CallsignLookupService(modelContext: modelContext)
        guard let info = await service.lookup(callsign) else {
            return
        }

        await MainActor.run {
            qso.name = info.name
            qso.theirGrid = info.grid
            qso.state = info.state
            qso.country = info.country
            qso.qth = info.qth
            qso.theirLicenseClass = info.licenseClass
            if info.callsignChangeNote != nil {
                qso.callsignChangeNote =
                    "Logged as \(qso.callsign) but operator changed to \(info.callsign)"
            }
            try? modelContext.save()
            refreshSessionQSOs()
        }
    }

    /// Re-fetch the live QSO for `id` and enrich it. Lets callers that hold only a
    /// `LoggedQSO` snapshot (e.g. HUNT logging) trigger metadata enrichment without
    /// referencing a live `@Model`.
    func fetchAndUpdateQSOMetadata(id: String, callsign: String) async {
        guard let qso = LogbookIDBridge.fetchQSO(id: id, in: modelContext) else {
            return
        }
        await fetchAndUpdateQSOMetadata(qso, callsign: callsign)
    }

    // MARK: - Quick Entry

    /// Log a QSO using quick entry data
    func logQuickEntry() {
        guard let qeResult = quickEntryResult, canLog else {
            return
        }

        // Capture callsign and QRZ info before form reset for QRQ Crew check
        let typedCallsign = qeResult.callsign.trimmingCharacters(in: .whitespaces).uppercased()
        let loggedLookup = lookupResult

        // When QRZ redirected, log the canonical (new) callsign instead
        let loggedCallsign = lookupResult?.callsignChangeNote != nil
            ? lookupResult?.callsign ?? typedCallsign : typedCallsign

        // Build field values with fallback chain: quick entry > form > lookup
        let gridToUse = qeResult.theirGrid.nonEmpty ?? theirGrid.nonEmpty ?? lookupResult?.grid
        let stateToUse = qeResult.state.nonEmpty ?? theirState.nonEmpty ?? lookupResult?.state
        let parkToUse = qeResult.theirPark.nonEmpty ?? theirPark.nonEmpty
        let notesToUse = qeResult.notes.nonEmpty ?? notes.nonEmpty

        // Build callsign change note when QRZ redirected to a different call
        let changeNote = buildCallsignChangeNote(
            loggedCallsign: typedCallsign
        )

        _ = sessionManager?.logQSO(
            callsign: loggedCallsign,
            rstSent: qeResult.rstSent ?? rstSent.nonEmpty ?? defaultRST,
            rstReceived: qeResult.rstReceived ?? rstReceived.nonEmpty ?? defaultRST,
            theirGrid: gridToUse,
            theirParkReference: parkToUse,
            notes: notesToUse,
            name: lookupResult?.name,
            operatorName: operatorName.nonEmpty ?? lookupResult?.displayName,
            state: stateToUse,
            country: lookupResult?.country,
            qth: lookupResult?.qth,
            theirLicenseClass: lookupResult?.licenseClass,
            aoaCode: aoaCode.nonEmpty,
            callsignChangeNote: changeNote,
            frequencyOverride: qeResult.frequency,
            modeOverride: qeResult.mode,
            timestampOverride: qeResult.zuluTime?.dateToday()
        )

        refreshSessionQSOs()
        restorePreSpotFrequency()
        resetFormAfterLog()

        // Check for QRQ Crew spot after form reset (non-blocking)
        checkQRQCrewSpot(theirCallsign: loggedCallsign, theirQRZInfo: loggedLookup)
    }

    /// Log multiple QSOs from a multi-callsign quick entry
    func logMultiQuickEntry(_ results: [QuickEntryResult]) {
        guard canLog else {
            return
        }

        for qeResult in results {
            let callsign = qeResult.callsign.trimmingCharacters(in: .whitespaces).uppercased()
            let gridToUse = qeResult.theirGrid.nonEmpty ?? theirGrid.nonEmpty
            let stateToUse = qeResult.state.nonEmpty ?? theirState.nonEmpty
            let parkToUse = qeResult.theirPark.nonEmpty ?? theirPark.nonEmpty
            let notesToUse = qeResult.notes.nonEmpty ?? notes.nonEmpty

            // Match lookup data from multi-callsign lookups
            let matched = multiLookupResults.first { $0.callsign == callsign }

            _ = sessionManager?.logQSO(
                callsign: callsign,
                rstSent: qeResult.rstSent ?? rstSent.nonEmpty ?? defaultRST,
                rstReceived: qeResult.rstReceived ?? rstReceived.nonEmpty ?? defaultRST,
                theirGrid: gridToUse ?? matched?.info?.grid,
                theirParkReference: parkToUse,
                notes: notesToUse,
                name: matched?.info?.name,
                operatorName: operatorName.nonEmpty ?? matched?.info?.displayName,
                state: stateToUse ?? matched?.info?.state,
                country: matched?.info?.country,
                qth: matched?.info?.qth,
                theirLicenseClass: matched?.info?.licenseClass,
                aoaCode: aoaCode.nonEmpty,
                callsignChangeNote: nil,
                frequencyOverride: qeResult.frequency,
                modeOverride: qeResult.mode,
                timestampOverride: qeResult.zuluTime?.dateToday()
            )
        }

        UINotificationFeedbackGenerator().notificationOccurred(.success)
        refreshSessionQSOs()
        restorePreSpotFrequency()
        resetFormAfterLog()
    }

    // MARK: - Editing

    /// Start editing an existing QSO
    func startEditingCallsign(_ qso: QSO) {
        editingQSO = qso
        populateFormFromQSO(qso)
        ToastManager.shared.info("Editing QSO - tap Save to update")
    }

    // MARK: - Recall

    /// Recall a QSO's fields into the form for logging a new contact
    /// (e.g., 2-fer / 3-fer — same operator at multiple parks)
    func recallQSO(_ qso: QSO) {
        editingQSO = nil
        // Build callsign input with park, mode, and frequency inline for quick entry
        var parts = [qso.callsign]
        if let park = qso.theirParkReference, !park.isEmpty {
            parts.append(park)
        }
        parts.append(qso.mode)
        if let freq = qso.frequency {
            parts.append(FrequencyFormatter.format(freq))
        }
        callsignInput = parts.joined(separator: " ")
        populateFormFieldsFromQSO(qso)
        ToastManager.shared.info("Recalled \(qso.callsign) — edit and log as new QSO")
    }

    /// Populate form fields from a QSO (shared by edit and recall)
    private func populateFormFromQSO(_ qso: QSO) {
        callsignInput = qso.callsign
        populateFormFieldsFromQSO(qso)
    }

    /// Set non-callsign form fields from a QSO
    private func populateFormFieldsFromQSO(_ qso: QSO) {
        theirState = qso.state ?? ""
        theirGrid = qso.theirGrid ?? ""
        theirPark = qso.theirParkReference ?? ""
        theirSummit = qso.sotaRef ?? ""
        // Recalled values count as user-set; clear the auto-fill marker
        // so the S2S enrichment can't blow them away if the cache says
        // the operator isn't currently spotted on a summit.
        autoFilledSummit = nil
        notes = qso.notes ?? ""
        rstSent = qso.rstSent ?? ""
        rstReceived = qso.rstReceived ?? ""
        operatorName = ""
        aoaCode = qso.aoaCode ?? ""
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .focusCallsignField, object: nil)
        }
    }

    /// Cancel editing and clear the form
    func cancelEditingCallsign() {
        editingQSO = nil
        resetFormAfterLog()
    }

    // MARK: - Form Reset

    /// Restore frequency if we tuned away for a spot
    func restorePreSpotFrequency() {
        if let freq = preSpotFrequency {
            _ = sessionManager?.updateFrequency(freq, isTuningToSpot: true)
            preSpotFrequency = nil
        }
    }

    /// Reset form fields without animations after logging
    func resetFormAfterLog() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            callsignInput = ""
            // When keepLookupAfterLog is on, card persists until user starts typing next callsign
            if !keepLookupAfterLog {
                lookupResult = nil
            }
            lookupError = nil
            previousQSOCount = 0
            cachedDuplicateStatus = nil
            viewingParkOverride = nil
            quickEntryResult = nil
            quickEntryMultiResults = nil
            quickEntryTokens = []
            spotMatchPark = nil
            // Always clear multi-lookup state (not subject to keepLookupAfterLog)
            multiLookupResults = []
            selectedMultiLookupIndex = 0
            lastLookedUpCallsigns = []
            theirGrid = ""
            theirState = ""
            theirPark = ""
            theirSummit = ""
            autoFilledSummit = nil
            notes = ""
            operatorName = ""
            rstSent = ""
            rstReceived = ""
            aoaCode = ""
            editingQSO = nil
        }
        // Explicitly defocus compact fields so they don't steal focus when their
        // bindings are cleared, then directly focus the callsign UITextField via
        // notification (bypasses SwiftUI @FocusState which is unreliable during
        // keyboard dismiss animations from other fields).
        compactFieldFocus = nil
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .focusCallsignField, object: nil)
        }
    }
}
