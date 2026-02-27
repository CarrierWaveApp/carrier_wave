import CarrierWaveCore
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

        // Check if we're editing an existing QSO
        if let qsoToUpdate = editingQSO {
            updateExistingQSOCallsign(qsoToUpdate)
            return
        }

        // Build field values with fallback: form > lookup
        let gridToUse = theirGrid.nonEmpty ?? lookupResult?.grid
        let stateToUse = theirState.nonEmpty ?? lookupResult?.state

        // Capture callsign before form reset for QRQ Crew check
        let loggedCallsign = callsignInput.trimmingCharacters(in: .whitespaces).uppercased()

        _ = sessionManager?.logQSO(
            callsign: callsignInput,
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
            aoaCode: aoaCode.nonEmpty
        )

        UINotificationFeedbackGenerator().notificationOccurred(.success)

        viewingParkOverride = nil
        refreshSessionQSOs()
        restorePreSpotFrequency()
        resetFormAfterLog()

        // Check for QRQ Crew spot after form reset (non-blocking)
        checkQRQCrewSpot(theirCallsign: loggedCallsign)
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

        // Capture callsign before form reset for QRQ Crew check
        let loggedCallsign = qeResult.callsign.trimmingCharacters(in: .whitespaces).uppercased()

        // Build field values with fallback chain: quick entry > form > lookup
        let gridToUse = qeResult.theirGrid.nonEmpty ?? theirGrid.nonEmpty ?? lookupResult?.grid
        let stateToUse = qeResult.state.nonEmpty ?? theirState.nonEmpty ?? lookupResult?.state
        let parkToUse = qeResult.theirPark.nonEmpty ?? theirPark.nonEmpty
        let notesToUse = qeResult.notes.nonEmpty ?? notes.nonEmpty

        _ = sessionManager?.logQSO(
            callsign: qeResult.callsign,
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
            aoaCode: aoaCode.nonEmpty
        )

        refreshSessionQSOs()
        restorePreSpotFrequency()
        resetFormAfterLog()

        // Check for QRQ Crew spot after form reset (non-blocking)
        checkQRQCrewSpot(theirCallsign: loggedCallsign)
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
        callsignFieldFocused = true
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
        callsignFieldFocused = true
    }

    // MARK: - Session End Handling

    /// Handle end session action - checks for POTA upload prompt first
    func handleEndSession() {
        guard let session = sessionManager?.activeSession else {
            completeSessionEnd()
            return
        }

        // Check if this is a POTA session with unuploaded QSOs
        if session.isPOTA,
           !potaUploadPromptDisabled
        {
            // Find QSOs that need upload to POTA
            let qsosNeedingUpload = sessionQSOs.filter { $0.needsUpload(to: .pota) }

            if !qsosNeedingUpload.isEmpty {
                pendingSessionEndQSOs = qsosNeedingUpload

                // Build rove stop summaries or single park info
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
                } else {
                    completeSessionEnd()
                    return
                }

                // Check maintenance window status
                pendingSessionEndInMaintenance = POTAClient.isInMaintenanceWindow()
                pendingSessionEndMaintenanceRemaining =
                    pendingSessionEndInMaintenance
                        ? POTAClient.formatMaintenanceTimeRemaining() : nil

                // Show the upload prompt (with maintenance warning if applicable)
                showPOTAUploadPrompt = true
                return
            }
        }

        // No POTA upload needed, end session directly
        completeSessionEnd()
    }

    /// Complete the session end after any POTA upload prompt handling
    func completeSessionEnd() {
        let hadQSOs = !sessionQSOs.isEmpty
        sessionManager?.endSession()
        if hadQSOs {
            onSessionEnd?()
        }

        // Clear pending state
        pendingSessionEndParkRef = nil
        pendingSessionEndParkName = nil
        pendingSessionEndQSOCount = 0
        pendingSessionEndQSOs = []
        pendingSessionEndRoveStops = []
        pendingSessionEndInMaintenance = false
        pendingSessionEndMaintenanceRemaining = nil
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

    func lookupParkName(_ reference: String?) -> String? {
        guard let ref = reference else {
            return nil
        }
        // For multi-park, look up the first park only
        let firstPark = ParkReference.split(ref).first ?? ref
        return POTAParksCache.shared.nameSync(for: firstPark)
    }

    // MARK: - QRQ Crew Spot

    /// Check if both operators are QRQ Crew members and trigger spot flow
    func checkQRQCrewSpot(theirCallsign: String) {
        guard let session = sessionManager?.activeSession,
              session.isPOTA,
              let parkRef = session.parkReference
        else {
            return
        }

        let myCallsign = session.myCallsign
        guard !myCallsign.isEmpty, !theirCallsign.isEmpty else {
            return
        }

        Task {
            guard var spotInfo = await QRQCrewService.checkMembership(
                myCallsign: myCallsign,
                theirCallsign: theirCallsign
            ) else {
                return
            }

            // Fill in the park reference
            spotInfo = QRQCrewSpotInfo(
                myInfo: spotInfo.myInfo,
                theirInfo: spotInfo.theirInfo,
                parkReference: parkRef
            )

            await MainActor.run {
                let autoSpot = UserDefaults.standard.bool(forKey: "qrqCrewAutoSpot")
                let lastWPM = UserDefaults.standard.integer(forKey: "qrqCrewLastWPM")

                if autoSpot, lastWPM > 0 {
                    // Auto-post with last-used WPM, no prompt
                    Task { await postQRQCrewSpot(spotInfo: spotInfo, wpm: lastWPM) }
                } else {
                    // Show prompt for WPM and confirmation
                    pendingQRQCrewSpot = spotInfo
                    showQRQCrewSpotSheet = true
                }
            }
        }
    }

    /// Post the QRQ Crew spot message to POTA
    func postQRQCrewSpot(spotInfo: QRQCrewSpotInfo, wpm: Int) async {
        // Save the WPM for next auto-spot
        UserDefaults.standard.set(wpm, forKey: "qrqCrewLastWPM")

        let comment = spotInfo.spotComment(wpm: wpm)
        await sessionManager?.postSpot(comment: comment, showToast: true)

        await MainActor.run {
            pendingQRQCrewSpot = nil
        }
    }
}
