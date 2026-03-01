import CarrierWaveCore
import SwiftData
import SwiftUI

// MARK: - LoggerView Sheet & Event Modifiers

extension LoggerView {
    /// Applies all sheet presentations to the main navigation content
    func applySheetModifiers(_ content: some View) -> some View {
        applyEndSessionSheets(
            applyEquipmentSheets(
                applyBandModeSheets(
                    applySessionSheets(content)
                )
            )
        )
    }

    /// Session start, title, park, and rove stop sheets
    private func applySessionSheets(_ content: some View) -> some View {
        content
            .sheet(isPresented: $showSessionSheet) {
                SessionStartSheet(
                    sessionManager: sessionManager,
                    onDismiss: { showSessionSheet = false }
                )
            }
            .sheet(isPresented: $showTitleEditSheet) {
                SessionTitleEditSheet(
                    title: $editingTitle,
                    defaultTitle: sessionManager?.activeSession?.defaultTitle ?? "",
                    onSave: { newTitle in
                        sessionManager?.updateTitle(newTitle.isEmpty ? nil : newTitle)
                        showTitleEditSheet = false
                    },
                    onCancel: { showTitleEditSheet = false }
                )
                .landscapeAdaptiveDetents(portrait: [.height(200)])
            }
            .sheet(isPresented: $showParkEditSheet) {
                SessionParkEditSheet(
                    parkReference: $editingParkReference,
                    userGrid: sessionManager?.activeSession?.myGrid
                        ?? UserDefaults.standard.string(forKey: "loggerDefaultGrid"),
                    onSave: { newPark in
                        sessionManager?.updateParkReference(newPark.isEmpty ? nil : newPark)
                        showParkEditSheet = false
                    },
                    onCancel: { showParkEditSheet = false }
                )
                .landscapeAdaptiveDetents(portrait: [.height(340)])
            }
            .sheet(isPresented: $showNextStopSheet) {
                NextRoveStopSheet(
                    sessionManager: sessionManager,
                    onDismiss: {
                        showNextStopSheet = false
                        refreshSessionQSOs()
                    }
                )
                .landscapeAdaptiveDetents(portrait: [.medium, .large])
            }
    }

    /// Band and mode edit sheets with QSY spot handling
    private func applyBandModeSheets(_ content: some View) -> some View {
        applyQSYAlert(applyModeSheet(applyBandSheet(content)))
    }

    private func applyBandSheet(_ content: some View) -> some View {
        content.sheet(
            isPresented: $showBandEditSheet,
            onDismiss: { handleQSYDismiss() },
            content: {
                SessionBandEditSheet(
                    currentFrequency: sessionManager?.activeSession?.frequency,
                    currentMode: sessionManager?.activeSession?.mode ?? "CW",
                    onSelectFrequency: { freq in handleBandFrequencySelection(freq) },
                    onCancel: { showBandEditSheet = false }
                )
                .landscapeAdaptiveDetents(portrait: [.medium, .large])
            }
        )
    }

    private func applyModeSheet(_ content: some View) -> some View {
        content.sheet(
            isPresented: $showModeEditSheet,
            onDismiss: { handleQSYDismiss() },
            content: {
                SessionModeEditSheet(
                    currentMode: sessionManager?.activeSession?.mode ?? "CW",
                    onSelectMode: { newMode in
                        let shouldPrompt = sessionManager?.updateMode(newMode) ?? false
                        if shouldPrompt {
                            pendingQSYFrequency = sessionManager?.activeSession?.frequency
                        }
                        showModeEditSheet = false
                    },
                    onCancel: { showModeEditSheet = false }
                )
                .landscapeAdaptiveDetents(portrait: [.height(280)])
            }
        )
    }

    private func applyQSYAlert(_ content: some View) -> some View {
        content.alert("Post QSY Spot?", isPresented: $showQSYSpotConfirmation) {
            Button("No", role: .cancel) {}
            Button("Yes") { Task { await sessionManager?.postQSYSpot() } }
        } message: {
            if let freq = qsyNewFrequency {
                Text("Post a QSY spot to POTA at \(FrequencyFormatter.formatWithUnit(freq))?")
            } else {
                Text("Post a QSY spot to POTA?")
            }
        }
    }

    private func handleBandFrequencySelection(_ freq: Double) {
        let result = sessionManager?.updateFrequency(freq)
        if result?.isFirstFrequencySet == true {
            let band = LoggingSession.bandForFrequency(freq)
            ToastManager.shared.success(
                "Frequency set to \(FrequencyFormatter.formatWithUnit(freq)) (\(band))"
            )
        }
        if autoModeSwitch, let suggestedMode = result?.suggestedMode {
            _ = sessionManager?.updateMode(suggestedMode)
        }
        if result?.shouldPromptForSpot == true {
            pendingQSYFrequency = freq
        }
    }

    /// Equipment, hidden QSOs, help, and SCP alert sheets
    private func applyEquipmentSheets(_ content: some View) -> some View {
        applySCPAlert(
            content
                .sheet(isPresented: $showRigEditSheet) {
                    equipmentEditSheet
                }
                .sheet(isPresented: $showHiddenQSOsSheet) {
                    HiddenQSOsSheet(sessionId: sessionManager?.activeSession?.id)
                }
                .sheet(isPresented: $showHelpSheet) {
                    LoggerHelpSheet()
                }
                .sheet(isPresented: $showBLERadioPanel) {
                    BLERadioPanel(service: BLERadioService.shared)
                }
        )
    }

    private var equipmentEditSheet: some View {
        SessionEquipmentEditSheet(
            radio: Binding(
                get: { sessionManager?.activeSession?.myRig },
                set: { sessionManager?.activeSession?.myRig = $0 }
            ),
            antenna: Binding(
                get: { sessionManager?.activeSession?.myAntenna },
                set: { sessionManager?.activeSession?.myAntenna = $0 }
            ),
            key: Binding(
                get: { sessionManager?.activeSession?.myKey },
                set: { sessionManager?.activeSession?.myKey = $0 }
            ),
            mic: Binding(
                get: { sessionManager?.activeSession?.myMic },
                set: { sessionManager?.activeSession?.myMic = $0 }
            ),
            extraEquipment: Binding(
                get: { sessionManager?.activeSession?.extraEquipment },
                set: { sessionManager?.activeSession?.extraEquipment = $0 }
            ),
            mode: sessionManager?.activeSession?.mode ?? "CW"
        )
        .landscapeAdaptiveDetents(portrait: [.medium, .large])
    }

    private func applySCPAlert(_ content: some View) -> some View {
        content
            .alert("Callsign not in SCP", isPresented: $showSCPDidYouMean) {
                if let first = scpDidYouMeanSuggestions.first {
                    Button(first.callsign) {
                        callsignInput = first.callsign
                    }
                }
                Button("Log Anyway") {
                    logQSOConfirmed()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                if let first = scpDidYouMeanSuggestions.first {
                    Text("Did you mean \(first.callsign)?")
                } else {
                    Text("This callsign was not found in the SCP database.")
                }
            }
    }

    /// QRQ Crew spot and POTA upload prompt and delete session sheets
    private func applyEndSessionSheets(_ content: some View) -> some View {
        content
            .sheet(isPresented: $showQRQCrewSpotSheet) {
                if let spotInfo = pendingQRQCrewSpot {
                    QRQCrewSpotSheet(
                        spotInfo: spotInfo,
                        onPost: { wpm in
                            showQRQCrewSpotSheet = false
                            Task { await postQRQCrewSpot(spotInfo: spotInfo, wpm: wpm) }
                        },
                        onCancel: {
                            showQRQCrewSpotSheet = false
                            pendingQRQCrewSpot = nil
                        }
                    )
                }
            }
            .sheet(isPresented: $showPOTAUploadPrompt) {
                POTAUploadPromptSheet(
                    parkReference: pendingSessionEndParkRef ?? "",
                    parkName: pendingSessionEndParkName,
                    qsoCount: pendingSessionEndQSOCount,
                    roveStops: pendingSessionEndRoveStops,
                    isInMaintenance: pendingSessionEndInMaintenance,
                    maintenanceTimeRemaining: pendingSessionEndMaintenanceRemaining,
                    onUpload: { await uploadPendingPOTAQSOs() },
                    onLater: {
                        showPOTAUploadPrompt = false
                        completeSessionEnd()
                    },
                    onDontAskAgain: {
                        potaUploadPromptDisabled = true
                        showPOTAUploadPrompt = false
                        completeSessionEnd()
                    }
                )
            }
            .sheet(isPresented: $showDeleteSessionSheet) {
                DeleteSessionConfirmationSheet(
                    qsoCount: sessionQSOs.count,
                    onConfirm: {
                        sessionManager?.deleteCurrentSession()
                        showDeleteSessionSheet = false
                    },
                    onCancel: { showDeleteSessionSheet = false }
                )
            }
    }

    /// Handle QSY spot confirmation on band/mode sheet dismiss
    private func handleQSYDismiss() {
        if let freq = pendingQSYFrequency {
            pendingQSYFrequency = nil
            qsyNewFrequency = freq
            showQSYSpotConfirmation = true
        }
    }

    /// Applies lifecycle and event handlers to the main navigation content
    func applyEventHandlers(_ content: some View) -> some View {
        content
            .onAppear {
                if sessionManager == nil {
                    sessionManager = externalSessionManager
                        ?? LoggingSessionManager(modelContext: modelContext)
                }
                sessionManager?.friendCallsigns = Set(
                    acceptedFriends.map { $0.friendCallsign.uppercased() }
                )
                refreshSessionQSOs()
                Task { await refreshPOTASpots() }
                // Load contact counts for suggestion weighting (background)
                let container = modelContext.container
                Task.detached {
                    let counts = CallsignSuggestionProvider.loadContactCounts(
                        container: container
                    )
                    await MainActor.run { suggestionContactCounts = counts }
                }
            }
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(60))
                    guard !Task.isCancelled else {
                        break
                    }
                    await refreshPOTASpots()
                }
            }
            .onChange(of: sessionManager?.activeSession?.frequency) { _, _ in
                dismissedWarnings.removeAll()
                if cachedPOTASpots.isEmpty {
                    Task { await refreshPOTASpots() }
                }
            }
            .onChange(of: sessionManager?.activeSession?.mode) { _, _ in
                dismissedWarnings.removeAll()
            }
            .onChange(of: sessionManager?.activeSession?.id) { _, _ in
                refreshSessionQSOs()
            }
            .onChange(of: externalSpotSelection) { _, newValue in
                if let selection = newValue {
                    handleSpotSelection(selection)
                    externalSpotSelection = nil
                }
            }
    }
}
