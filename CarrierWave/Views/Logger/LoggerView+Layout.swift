import CarrierWaveCore
import SwiftUI

// MARK: - LoggerView Layout

extension LoggerView {
    // MARK: - Callsign Lookup Display

    /// Callsign lookup display (card or error banner)
    @ViewBuilder
    var callsignLookupDisplay: some View {
        if let info = lookupResult, !callsignFieldFocused || callsignInput.isEmpty {
            LoggerCallsignCard(
                info: info,
                previousQSOCount: previousQSOCount,
                myGrid: sessionManager?.activeSession?.myGrid
                    ?? UserDefaults.standard.string(forKey: "loggerDefaultGrid")
            )
            .transition(
                .asymmetric(
                    insertion: .move(edge: .top).combined(with: .opacity),
                    removal: .opacity
                )
            )
        } else if let error = lookupError, shouldShowLookupError {
            CallsignLookupErrorBanner(error: error)
                .transition(
                    .asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .opacity
                    )
                )
        }
    }

    // MARK: - Portrait Layout

    var portraitLayout: some View {
        VStack(spacing: 0) {
            sessionHeader

            // Spot monitoring summary (always visible when session active)
            if let manager = sessionManager {
                SpotSummaryView(monitoringService: manager.spotMonitoringService)
                    .padding(.horizontal)
                    .padding(.top, 8)
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

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 12) {
                        // Only show QSO form when session is active
                        if sessionManager?.hasActiveSession == true {
                            callsignInputSection
                                .id("callsignInput")

                            // POTA duplicate/new band warning
                            if let status = potaDuplicateStatus {
                                POTAStatusBanner(status: status)
                                    .transition(
                                        .asymmetric(
                                            insertion: .move(edge: .top).combined(
                                                with: .opacity
                                            ),
                                            removal: .opacity
                                        )
                                    )
                            }

                            // Show callsign info or error when keyboard is not visible
                            callsignLookupDisplay

                            // Compact fields: State, RSTs, with More expansion
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

                        qsoListSection
                    }
                    .padding()
                    // Add bottom padding when a panel is open so Log QSO button remains accessible
                    .padding(.bottom, isAnyPanelOpen ? 280 : 0)
                }
                .onChange(of: editingQSO?.id) { _, newValue in
                    if newValue != nil {
                        withAnimation {
                            proxy.scrollTo("callsignInput", anchor: .top)
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
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: showRBNPanel)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: showSolarPanel)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: showWeatherPanel)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: showMapPanel)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: showPOTAPanel)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: showP2PPanel)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: showWebSDRPanel)
    }
}
