import CarrierWaveData
import SwiftUI

// MARK: - LoggerView Layout

extension LoggerView {
    // MARK: - Callsign Lookup Display

    /// Grid string for callsign card distance calculation
    private var lookupMyGrid: String? {
        sessionManager?.activeSession?.myGrid
            ?? UserDefaults.standard.string(forKey: "loggerDefaultGrid")
    }

    /// Callsign lookup display (card, multi-card, or error banner)
    @ViewBuilder
    var callsignLookupDisplay: some View {
        if !multiLookupResults.isEmpty, compactFieldFocus == nil {
            // Multi-callsign: show chips + expandable card (visible while typing)
            MultiCallsignLookupView(
                lookupStates: multiLookupResults,
                selectedIndex: $selectedMultiLookupIndex,
                myGrid: lookupMyGrid
            )
            // Fade rather than slide-from-top so the callsign field never jumps
            // under the user's thumb while they're typing.
            .transition(.opacity)
        } else if let info = lookupResult,
                  !callsignFieldFocused || callsignInput.isEmpty,
                  compactFieldFocus == nil
        {
            LoggerCallsignCard(
                info: info,
                previousQSOCount: previousQSOCount,
                myGrid: lookupMyGrid,
                potaSpots: potaSpotMatches,
                sotaSpot: sotaSpotForCallsign(info.callsign)
            )
            .transition(.opacity)
        } else if let error = lookupError, shouldShowLookupError {
            if callsignFieldFocused {
                CompactLookupErrorBar(error: error)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .transition(.opacity)
            } else {
                CallsignLookupErrorBanner(error: error)
                    .transition(.opacity)
            }
        }
    }

    // MARK: - Portrait Layout

    var portraitLayout: some View {
        VStack(spacing: 0) {
            sessionHeader

            // Spot monitoring summary (always visible when session active)
            if let manager = sessionManager {
                SpotSummaryView(
                    monitoringService: manager.spotMonitoringService,
                    callsign: manager.activeSession?.myCallsign
                        ?? UserDefaults.standard.string(forKey: "loggerDefaultCallsign"),
                    myGrid: manager.activeSession?.myGrid
                        ?? UserDefaults.standard.string(forKey: "loggerDefaultGrid")
                )
                .padding(.horizontal)
                .padding(.top, 8)
            }

            // Network health warning
            if !networkHealthDismissed,
               NetworkHealthMonitor.shared.health != .healthy
            {
                NetworkHealthBanner(
                    health: NetworkHealthMonitor.shared.health,
                    onDismiss: {
                        withAnimation { networkHealthDismissed = true }
                    }
                )
                .padding(.horizontal)
                .padding(.top, 4)
                .transition(.opacity)
            }

            // Frequency warning banner (license violations + activity warnings)
            FrequencyWarningBannerContainer(
                warning: computeCurrentWarning(
                    spotCount: cachedPOTASpots.count,
                    inputText: callsignInput
                ),
                onDismiss: { message in
                    dismissedWarnings.insert(message)
                }
            )

            // Spot-vs-QSO mismatch banner
            if !spotMismatchesDismissed {
                SpotContactMismatchBannerContainer(
                    mismatches: spotMismatches,
                    onDismiss: {
                        withAnimation { spotMismatchesDismissed = true }
                    },
                    onTapMismatch: { mismatch in
                        if let qso = sessionQSOs.first(where: { $0.id == mismatch.qsoId }) {
                            startEditingCallsign(qso)
                            callsignInput = mismatch.spotCallsign
                        }
                    }
                )
            }

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 12) {
                        // Only show QSO form when session is active
                        if sessionManager?.hasActiveSession == true {
                            if sessionManager?.activeSession?.mode == "FT8",
                               let manager = ft8Manager
                            {
                                FT8SessionView(
                                    ft8Manager: manager,
                                    sessionManager: sessionManager,
                                    parkReference: sessionManager?.activeSession?.parkReference
                                )
                            } else {
                                callsignInputSection
                                    .id("callsignInput")

                                // Duplicate/new band warning
                                if let status = duplicateStatus {
                                    DuplicateStatusBanner(status: status)
                                        .transition(.opacity)
                                }

                                if isContestSession {
                                    // Contest mode: unified strike card
                                    // (callsign + membership + dupe +
                                    // exchange inputs + score) in place
                                    // of the separate QRZ + exchange
                                    // cards. Keeps name + identifier
                                    // above the keyboard fold during
                                    // 100-QSO/hour CWT sessions.
                                    contestStrikeCard

                                    // Reminder + constraint badges live
                                    // outside the strike card so they
                                    // don't push inputs off-screen.
                                    clubNumberReminder
                                    contestConstraintBadges
                                } else {
                                    // Standard logger: full QRZ card.
                                    callsignLookupDisplay
                                }

                                // Compact fields: RSTs, QTH, with More
                                // expansion. CWT exchanges are nearly
                                // always 599/599 so this row is rarely
                                // needed during contest, but stays
                                // available for non-default cases.
                                if !hideFieldEntryForm {
                                    compactFieldsSection
                                }

                                // Cancel button when editing a QSO
                                if editingQSO != nil {
                                    Button {
                                        cancelEditingCallsign()
                                    } label: {
                                        Text("Cancel Edit")
                                            .font(.subheadline)
                                    }
                                    .buttonStyle(.bordered)
                                    .accessibilityLabel("Cancel editing callsign")
                                }
                            }
                        }

                        qsoListSection
                    }
                    .padding()
                    // Add bottom padding when a panel is open so Log QSO button remains accessible
                    .padding(.bottom, isAnyPanelOpen ? 280 : 0)
                }
                .onScrollGeometryChange(for: Bool.self) { geometry in
                    geometry.contentOffset.y > 50
                } action: { _, shouldPin in
                    commandBarPinned = shouldPin
                }
                .overlay(alignment: .top) {
                    if commandBarPinned,
                       sessionManager?.hasActiveSession == true,
                       sessionManager?.activeSession?.mode != "FT8"
                    {
                        VStack(spacing: 4) {
                            callsignInputSection
                                .fixedSize(horizontal: false, vertical: true)

                            callsignLookupDisplay
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 4)
                        .background(Color(.systemGroupedBackground))
                    }
                }
                .onChange(of: editingQSO?.id) { _, newValue in
                    if newValue != nil {
                        withAnimation {
                            proxy.scrollTo("callsignInput", anchor: .top)
                        }
                    }
                }
            }

            // Persistent CW keyer row (when bridge connected in CW mode)
            if cwKeyerVisible {
                Divider()
                CWKeyerRow(
                    keyerService: RadioService.shared.cwKeyer,
                    onPlay: { slot, ctx in cwPlaySlot(slot, context: ctx) },
                    onStop: { cwStop() },
                    onSendText: { text in cwSendText(text) },
                    onEdit: { cwSlotEditorID = $0; showCWSlotEditor = true },
                    onSpeedChange: { wpm in cwSetSpeed(wpm) },
                    context: { cwBuildContext() }
                )
                .sheet(isPresented: $showCWSlotEditor) {
                    if let slotID = cwSlotEditorID {
                        NavigationStack {
                            CWMessageEditorView(
                                slotID: slotID,
                                keyerService: RadioService.shared.cwKeyer
                            )
                            .toolbar {
                                ToolbarItem(placement: .topBarTrailing) {
                                    Button("Done") {
                                        cwSlotEditorID = nil
                                        showCWSlotEditor = false
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Persistent command strip on iPad (keyboard accessory has numbers only)
            if horizontalSizeClass == .regular,
               sessionManager?.hasActiveSession == true
            {
                IPadCommandStrip(onCommand: { command in
                    executeCommand(command)
                })
            }
        }
        .onChange(of: sessionManager?.activeSession?.mode) { _, newMode in
            if newMode == "FT8" {
                if ft8Manager == nil, let session = sessionManager {
                    ft8Manager = FT8SessionManager(
                        myCallsign: session.activeSession?.myCallsign ?? "",
                        myGrid: session.activeSession?.myGrid ?? "",
                        modelContext: modelContext,
                        qsoLogger: session,
                        initialBand: session.activeSession?.band
                    )
                }
                if !ft8SetupComplete {
                    showFT8SetupWizard = true
                }
            } else {
                if let manager = ft8Manager {
                    Task { await manager.stop() }
                    ft8Manager = nil
                }
            }
        }
        .onChange(of: sessionManager?.activeSession?.band) { _, newBand in
            guard let newBand,
                  let manager = ft8Manager,
                  let resolved = FT8Constants.resolveBand(newBand),
                  manager.selectedBand != resolved
            else {
                return
            }
            manager.selectedBand = resolved
        }
        .onChange(of: sessionManager?.webSDRSession.state) { oldState, newState in
            // Auto-show WebSDR panel when SDR starts connecting
            guard let newState else {
                return
            }
            let wasInactive = oldState == nil || oldState == .idle
            let nowActive = newState == .connecting || newState == .recording
            if wasInactive, nowActive {
                present(.webSDR)
            }
        }
    }

    // MARK: - Panel Overlays

    /// Panel overlays for RBN, Solar, Weather
    var panelOverlays: some View {
        VStack {
            if showRBNPanel {
                SwipeToDismissPanel(isPresented: $showRBNPanel) {
                    RBNPanelView(
                        callsign: sessionManager?.activeSession?.myCallsign
                            ?? UserDefaults.standard.string(forKey: "loggerDefaultCallsign")
                            ?? "UNKNOWN",
                        targetCallsign: rbnTargetCallsign
                    ) {
                        showRBNPanel = false
                        rbnTargetCallsign = nil
                    }
                }
                .padding()
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if showSolarPanel {
                SwipeToDismissPanel(isPresented: $showSolarPanel) {
                    SolarPanelView {
                        showSolarPanel = false
                    }
                }
                .padding()
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if showWeatherPanel {
                SwipeToDismissPanel(isPresented: $showWeatherPanel) {
                    WeatherPanelView(
                        grid: sessionManager?.activeSession?.myGrid
                            ?? UserDefaults.standard.string(forKey: "loggerDefaultGrid")
                    ) {
                        showWeatherPanel = false
                    }
                }
                .padding()
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if showMapPanel {
                SwipeToDismissPanel(isPresented: $showMapPanel) {
                    SessionMapPanelView(
                        sessionQSOs: sessionQSOs,
                        myGrid: sessionManager?.activeSession?.myGrid
                            ?? UserDefaults.standard.string(forKey: "loggerDefaultGrid"),
                        roveStops: sessionManager?.activeSession?.isRove == true
                            ? (sessionManager?.activeSession?.roveStops ?? [])
                            : []
                    ) {
                        showMapPanel = false
                    }
                }
                .padding()
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if showPOTAPanel {
                SwipeToDismissPanel(isPresented: $showPOTAPanel) {
                    POTASpotsView(
                        userCallsign: sessionManager?.activeSession?.myCallsign,
                        initialBand: sessionManager?.activeSession?.band,
                        initialMode: sessionManager?.activeSession?.mode,
                        onDismiss: { showPOTAPanel = false },
                        onSelectSpot: { spot in
                            handleSpotSelection(.pota(spot))
                            showPOTAPanel = false
                        },
                        onSelectSOTASpot: { spot in
                            handleSpotSelection(.sota(spot))
                            showPOTAPanel = false
                        }
                    )
                }
                .padding()
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if showP2PPanel {
                SwipeToDismissPanel(isPresented: $showP2PPanel) {
                    P2PPanelView(
                        userCallsign: sessionManager?.activeSession?.myCallsign ?? "",
                        userGrid: sessionManager?.activeSession?.myGrid
                            ?? UserDefaults.standard.string(forKey: "loggerDefaultGrid") ?? "",
                        initialBand: sessionManager?.activeSession?.band,
                        initialMode: sessionManager?.activeSession?.mode,
                        onDismiss: { showP2PPanel = false },
                        onSelectOpportunity: { opportunity in
                            handleSpotSelection(.p2p(opportunity))
                            showP2PPanel = false
                        }
                    )
                }
                .padding()
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if showWebSDRPanel, let session = sessionManager {
                SwipeToDismissPanel(isPresented: $showWebSDRPanel) {
                    WebSDRPanelView(
                        webSDRSession: session.webSDRSession,
                        myGrid: session.activeSession?.myGrid,
                        frequencyMHz: session.activeSession?.frequency,
                        mode: session.activeSession?.mode,
                        loggingSessionId: session.activeSession?.id,
                        modelContext: modelContext,
                        onDismiss: { showWebSDRPanel = false }
                    )
                }
                .padding()
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? .none : .spring(response: 0.3, dampingFraction: 0.7), value: showRBNPanel)
        .animation(reduceMotion ? .none : .spring(response: 0.3, dampingFraction: 0.7), value: showSolarPanel)
        .animation(reduceMotion ? .none : .spring(response: 0.3, dampingFraction: 0.7), value: showWeatherPanel)
        .animation(reduceMotion ? .none : .spring(response: 0.3, dampingFraction: 0.7), value: showMapPanel)
        .animation(reduceMotion ? .none : .spring(response: 0.3, dampingFraction: 0.7), value: showPOTAPanel)
        .animation(reduceMotion ? .none : .spring(response: 0.3, dampingFraction: 0.7), value: showP2PPanel)
        .animation(reduceMotion ? .none : .spring(response: 0.3, dampingFraction: 0.7), value: showWebSDRPanel)
    }
}
