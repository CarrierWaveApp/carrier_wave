import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - LoggerView QSO Logging

extension LoggerView {
    // MARK: - Input Handling

    func handleInputSubmit() {
        // Check if it's a command
        if let command = LoggerCommand.parse(callsignInput) {
            executeCommand(command)
            callsignInput = ""
            quickEntryResult = nil
            quickEntryTokens = []
            return
        }

        // If editing an existing QSO, always route through logQSO (which handles edits)
        if editingQSO != nil, canLog {
            logQSO()
            return
        }

        // Check for quick entry mode
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

        _ = sessionManager?.logQSO(
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
            callsignChangeNote: changeNote
        )

        UINotificationFeedbackGenerator().notificationOccurred(.success)

        viewingParkOverride = nil
        refreshSessionQSOs()
        restorePreSpotFrequency()
        resetFormAfterLog()

        // Check for QRQ Crew spot after form reset (non-blocking)
        checkQRQCrewSpot(theirCallsign: loggedCallsign, theirQRZInfo: loggedLookup)
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
        if let v = quickEntryResult?.notes.nonEmpty ?? notes.nonEmpty {
            qso.notes = v
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
            callsignChangeNote: changeNote
        )

        refreshSessionQSOs()
        restorePreSpotFrequency()
        resetFormAfterLog()

        // Check for QRQ Crew spot after form reset (non-blocking)
        checkQRQCrewSpot(theirCallsign: loggedCallsign, theirQRZInfo: loggedLookup)
    }

    // MARK: - Editing

    /// Start editing an existing QSO
    func startEditingCallsign(_ qso: QSO) {
        editingQSO = qso
        callsignInput = qso.callsign
        theirState = qso.state ?? ""
        theirGrid = qso.theirGrid ?? ""
        theirPark = qso.theirParkReference ?? ""
        notes = qso.notes ?? ""
        rstSent = qso.rstSent ?? ""
        rstReceived = qso.rstReceived ?? ""
        operatorName = ""
        aoaCode = qso.aoaCode ?? ""
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .focusCallsignField, object: nil)
        }
        ToastManager.shared.info("Editing QSO - tap Save to update")
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
            cachedPotaDuplicateStatus = nil
            viewingParkOverride = nil
            quickEntryResult = nil
            quickEntryTokens = []
            theirGrid = ""
            theirState = ""
            theirPark = ""
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

    // MARK: - Session End Handling

    /// Handle end session action — shows multi-step end session flow
    func handleEndSession() {
        guard let session = sessionManager?.activeSession else {
            completeSessionEnd()
            return
        }

        // Populate POTA upload state if applicable
        if session.isPOTA, !potaUploadPromptDisabled {
            let qsosNeedingUpload = sessionQSOs.filter { $0.needsUpload(to: .pota) }
            if !qsosNeedingUpload.isEmpty {
                pendingSessionEndQSOs = qsosNeedingUpload
                if session.isRove {
                    let stops = session.mergedRoveStops
                    var summaries: [RoveUploadSummary] = []
                    for stop in stops {
                        let parkRef = stop.parkReference
                        let stopQSOs = qsosNeedingUpload.filter {
                            $0.parkReference?.uppercased() == parkRef.uppercased()
                        }
                        guard !stopQSOs.isEmpty else {
                            continue
                        }
                        let primaryPark = ParkReference.split(parkRef).first ?? parkRef
                        summaries.append(RoveUploadSummary(
                            parkReference: primaryPark,
                            parkName: lookupParkName(primaryPark),
                            qsoCount: stopQSOs.count
                        ))
                    }
                    pendingSessionEndRoveStops = summaries
                    pendingSessionEndParkRef = session.parkReference
                    pendingSessionEndParkName = nil
                    pendingSessionEndQSOCount = qsosNeedingUpload.count
                } else if let parkRef = session.parkReference {
                    pendingSessionEndRoveStops = []
                    pendingSessionEndParkRef = parkRef
                    pendingSessionEndParkName = lookupParkName(parkRef)
                    pendingSessionEndQSOCount = qsosNeedingUpload.count
                }

                pendingSessionEndInMaintenance = POTAClient.isInMaintenanceWindow()
                pendingSessionEndMaintenanceRemaining =
                    pendingSessionEndInMaintenance
                        ? POTAClient.formatMaintenanceTimeRemaining() : nil
            }
        }

        showEndSessionFlow = true
    }

    /// Actually end the session and build the activity item for the brag sheet
    func performSessionEnd() {
        guard sessionManager?.activeSession != nil else {
            return
        }

        let hadQSOs = !sessionQSOs.isEmpty
        sessionManager?.endSession()
        if hadQSOs {
            onSessionEnd?()
        }

        // Find the just-created ActivityItem for the brag sheet display
        endSessionActivityItem = fetchLatestOwnActivity()
    }

    /// Complete the session end flow (called when the flow sheet is dismissed)
    func completeSessionEnd() {
        let hadQSOs = !sessionQSOs.isEmpty
        if sessionManager?.activeSession != nil {
            sessionManager?.endSession()
            if hadQSOs {
                onSessionEnd?()
            }
        }

        // Clear pending state
        pendingSessionEndParkRef = nil
        pendingSessionEndParkName = nil
        pendingSessionEndQSOCount = 0
        pendingSessionEndQSOs = []
        pendingSessionEndRoveStops = []
        pendingSessionEndInMaintenance = false
        pendingSessionEndMaintenanceRemaining = nil
        endSessionActivityItem = nil
    }

    /// Upload pending POTA QSOs from the upload prompt (supports multi-park)
    func uploadPendingPOTAQSOs() async -> Bool {
        guard let parkRef = pendingSessionEndParkRef,
              !pendingSessionEndQSOs.isEmpty
        else {
            return false
        }

        let parks = ParkReference.split(parkRef)
        let potaClient = POTAClient(authService: POTAAuthService())
        var allSucceeded = true

        for park in parks {
            do {
                let result = try await potaClient.uploadActivationWithRecording(
                    parkReference: park,
                    qsos: pendingSessionEndQSOs,
                    modelContext: modelContext
                )

                if result.success {
                    for qso in pendingSessionEndQSOs {
                        qso.markSubmittedToPark(park, context: modelContext)
                    }
                    try? modelContext.save()
                } else {
                    allSucceeded = false
                    SyncDebugLog.shared.warning(
                        "POTA upload for \(park): result.success=false, "
                            + "message=\(result.message ?? "nil")",
                        service: .pota
                    )
                }
            } catch {
                allSucceeded = false
                SyncDebugLog.shared.error(
                    "POTA upload for \(park) failed: \(error.localizedDescription)",
                    service: .pota
                )
            }
        }

        return allSucceeded
    }

    /// Build a callsign change note when QRZ redirected to a different canonical call
    func buildCallsignChangeNote(loggedCallsign: String) -> String? {
        guard let lookup = lookupResult, lookup.callsignChangeNote != nil else {
            return nil
        }
        return "Logged as \(loggedCallsign) but operator changed to \(lookup.callsign)"
    }

    func lookupParkName(_ reference: String?) -> String? {
        guard let ref = reference else {
            return nil
        }
        // For multi-park, look up the first park only
        let firstPark = ParkReference.split(ref).first ?? ref
        return POTAParksCache.shared.nameSync(for: firstPark)
    }
}
