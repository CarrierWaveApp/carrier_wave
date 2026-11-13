import CarrierWaveData
import CoreLocation
import SwiftUI

// MARK: - SatellitesRootView

/// Live satellite map: SatNOGS TLEs propagated on-device with SGP4 by the
/// shared Rust engine.
/// Hosted as a hidden-by-default tab (gated by the `.satellites` experiment).
struct SatellitesRootView: View {
    // MARK: Internal

    /// Slider range: ±12 h of simulated time.
    static let scrubRange: TimeInterval = 12 * 60 * 60
    /// Released within this window of "now" snaps back to live.
    static let scrubSnapWindow: TimeInterval = 300

    // Internal (not fileprivate): the filtering extension lives in
    // SatellitesRootView+Filtering.swift.
    @State var model = SatelliteTrackerModel()
    @State var nextPasses = [UpcomingSatellitePass]()
    /// Mode + band + elevation filters shared with the pass lists
    /// (empty/0 = all); internal for the filtering extension.
    @AppStorage(SatelliteModeFilter.storageKey) var modeFilterRaw = ""
    @AppStorage(SatelliteModeFilter.uplinkBandKey) var uplinkBandRaw = ""
    @AppStorage(SatelliteModeFilter.downlinkBandKey) var downlinkBandRaw = ""
    @AppStorage(SatelliteModeFilter.minPeakElevationKey) var minPeakElevation = 0
    @AppStorage(SatelliteModeFilter.heardRecentlyKey) var heardRecentlyOnly = false
    @AppStorage(SatelliteModeFilter.favoritesOnlyKey) var favoritesOnly = false
    @AppStorage(SatelliteModeFilter.horizonMaskKey) var skySectorsRaw = ""

    @State var pointAfterList = false
    @State var showPointing = false

    var body: some View {
        content
            .navigationTitle("Satellites")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Three items max — five icons overflowed the nav bar (the
                // title collapsed to "…"). The workflow pair (satellite list +
                // upcoming passes) stays visible; the rest live in a menu.
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showUpcoming = true
                    } label: {
                        Image(systemName: "calendar.badge.clock")
                    }
                    .disabled(model.state != .loaded)
                    .accessibilityLabel("Upcoming passes")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showList = true
                    } label: {
                        Image(systemName: "list.bullet")
                    }
                    .disabled(model.searchItems.isEmpty)
                    .accessibilityLabel("Satellite list")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showFilterSheet = true
                        } label: {
                            Label(
                                "Filter Satellites",
                                systemImage: "line.3.horizontal.decrease.circle"
                            )
                        }
                        Button {
                            showAlertSettings = true
                        } label: {
                            Label("Pass Alerts", systemImage: "bell")
                        }
                        Button {
                            showMutual = true
                        } label: {
                            Label("Mutual Pass Planner", systemImage: "person.2")
                        }
                        .disabled(model.state != .loaded)
                        Button {
                            showCommunity = true
                        } label: {
                            Label("Community Activity", systemImage: "chart.bar.xaxis")
                        }
                        .disabled(model.state != .loaded)
                        Button {
                            showRotatorSheet = true
                        } label: {
                            Label("Rotator & Trackers", systemImage: "dial.medium")
                        }
                        Button {
                            Task { await model.load(forceRefresh: true) }
                        } label: {
                            Label("Refresh Orbital Data", systemImage: "arrow.clockwise")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("More satellite actions")
                }
            }
            // Presenting the pointing cover while the sheet is still
            // dismissing is dropped by SwiftUI, so it opens on dismiss.
            .sheet(isPresented: $showList, onDismiss: openPointingIfPending) {
                SatelliteListSheet(
                    model: model,
                    motion: motion,
                    onSelect: { model.select($0) },
                    onPoint: { noradID in
                        model.select(noradID)
                        pointAfterList = true
                    }
                )
            }
            .sheet(isPresented: $showUpcoming) {
                SatelliteUpcomingPassesSheet(model: model) { noradID in
                    model.select(noradID)
                }
            }
            .sheet(isPresented: $showMutual) {
                MutualPassPlannerSheet(model: model)
            }
            .sheet(
                isPresented: $showCommunity,
                onDismiss: { communityInitialRow = nil },
                content: {
                    SatelliteCommunityActivitySheet(
                        model: model,
                        initialRowID: communityInitialRow,
                        onSelect: { noradID in model.select(noradID) }
                    )
                }
            )
            .sheet(isPresented: $showCommunityReport) {
                SatelliteCommunityReportSheet(model: model, rows: model.selectedCommunityRows)
            }
            .sheet(isPresented: $showAlertSettings) {
                SatelliteAlertSettingsSheet { noradID in
                    model.searchItems.first { $0.noradID == noradID }?.name
                }
            }
            .sheet(isPresented: $showFilterSheet) {
                SatelliteFilterSheet()
            }
            .sheet(isPresented: $showRotatorSheet) {
                SatelliteRotatorSheet(model: model)
            }
            .trackerDetectedAlert(model: model)
            .onDisappear {
                SatelliteRotatorService.shared.stopDetection()
            }
            .onReceive(
                NotificationCenter.default.publisher(for: .didReceiveSatellitePassAlert)
            ) { notification in
                if let noradID = notification.userInfo?["noradID"] as? Int {
                    model.select(noradID)
                }
                SatellitePassActivityController.shared.start(
                    fromUserInfo: notification.userInfo
                )
            }
            .sheet(isPresented: $showPassList) {
                if let selected = model.selectedPosition {
                    SatellitePassListSheet(
                        model: model,
                        position: selected,
                        transmitters: model.transmitters(for: selected.noradID)
                    )
                    .presentationDetents([.medium, .large])
                }
            }
            .fullScreenCover(isPresented: $showPointing) {
                AntennaPointingView(model: model, motion: motion) {
                    showPointing = false
                }
            }
            .sheet(isPresented: $showQuickLog) {
                if let selected = model.selectedPosition {
                    SatelliteQuickLogSheet(
                        satName: selected.name,
                        detailName: selected.detailName,
                        transmitters: model.transmitters(for: selected.noradID),
                        pass: nil,
                        observerGrid: model.observerCoordinate.map {
                            MaidenheadConverter.grid(from: $0, precision: .six)
                        },
                        recording: pendingRecording,
                        onLogged: { _ in }
                    )
                }
            }
            .onChange(of: gpsService.currentCoordinate?.latitude) {
                updateObserver()
            }
            // The tilt-up trigger lives in a zero-size child so the 30 Hz
            // attitude stream re-renders only that child — observing it here
            // rebuilt this whole body (toolbar included) every sample, which
            // detached the open ellipsis Menu's items and ate their taps.
            .background {
                SkyDomeTiltTrigger(motion: motion) { elevation in
                    updateSkyDome(pointingElevation: elevation)
                }
            }
            .task {
                updateObserver()
                gpsService.requestGrid()
                // Hands-free rotator detection while the satellites tab is up.
                SatelliteRotatorService.shared.startDetection(model: model)
                await model.load()
                // Fresh TLEs are also the alert scheduler's input.
                SatellitePassAlertScheduler.shared.reschedule(trigger: "tle-refresh")
                nextPasses = await model.upcomingPasses(withinHours: 12)
                // SGP4 truth sync every 5s; the map's display link
                // dead-reckons continuous motion between syncs. The
                // next-passes strip refreshes opportunistically every ~5 min.
                var tick = 0
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(5))
                    await model.refreshPositions()
                    tick += 1
                    if tick.isMultiple(of: 60) {
                        nextPasses = await model.upcomingPasses(withinHours: 12)
                    }
                }
            }
    }

    // MARK: Fileprivate

    /// Raise the phone past this pointing elevation to enter the sky dome…
    fileprivate static let domeEnterElevationDeg = 0.0
    /// …and drop below this to leave it (hysteresis).
    fileprivate static let domeExitElevationDeg = -10.0

    @State fileprivate var motion = AntennaMotionService()
    @State fileprivate var gpsService = GridLocationService()
    @State fileprivate var showList = false
    @State fileprivate var showPassList = false
    @State fileprivate var showUpcoming = false
    @State fileprivate var showCommunity = false
    @State fileprivate var communityInitialRow: String?
    @State fileprivate var showCommunityReport = false
    @State fileprivate var showMutual = false
    @State fileprivate var showQuickLog = false
    @State fileprivate var showAlertSettings = false
    @State fileprivate var showFilterSheet = false
    @State fileprivate var showRotatorSheet = false
    @State fileprivate var pendingRecording: SatellitePassRecording?
    @State fileprivate var showDome = false
    @State fileprivate var domeSuppressed = false
    @AppStorage("myGrid") fileprivate var myGrid = ""
    @AppStorage("loggerDefaultGrid") fileprivate var loggerDefaultGrid = ""
    /// When true the map stays north-up instead of rotating with the device.
    @AppStorage("satelliteMapHeadingLocked") fileprivate var mapHeadingLocked = false
}

// MARK: - SkyDomeTiltTrigger

/// Invisible observer of the pointing elevation: isolates the 30 Hz
/// attitude dependency from `SatellitesRootView`'s body so only this
/// zero-size view re-renders per sample; the parent re-renders only when
/// the callback actually flips dome state.
private struct SkyDomeTiltTrigger: View {
    let motion: AntennaMotionService
    let onElevationChange: (Double) -> Void

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onChange(of: motion.pointingElevationDeg ?? -90) { _, elevation in
                onElevationChange(elevation)
            }
    }
}

// MARK: - Map content + overlays

private extension SatellitesRootView {
    @ViewBuilder
    var content: some View {
        switch model.state {
        case .idle,
             .loading:
            ProgressView("Loading orbital data…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .failed(message):
            ContentUnavailableView {
                Label("Couldn't Load Satellites", systemImage: "globe.americas")
            } description: {
                Text(message)
            } actions: {
                Button("Retry") {
                    Task { await model.load(forceRefresh: true) }
                }
                .buttonStyle(.borderedProminent)
            }
        case .loaded:
            mapContent
        }
    }

    var mapContent: some View {
        SatelliteAzimuthalMapView(
            positions: filteredPositions,
            track: model.selectedTrack,
            communityStatus: model.communityStatusByNorad,
            reporters: model.selectedReporters,
            observer: model.observerCoordinate,
            positionsSyncedAt: model.positionsSyncedAt,
            followsHeading: !mapHeadingLocked,
            motion: motion,
            selectedNoradID: Binding(
                get: { model.selectedNoradID },
                set: { model.select($0) }
            )
        )
        .ignoresSafeArea(edges: .bottom)
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 8) {
                RotatorStatusChip { showRotatorSheet = true }
                headingLockButton
            }
        }
        .overlay(alignment: .bottom) {
            VStack(spacing: 8) {
                if model.selectedPosition == nil {
                    NextPassesStrip(passes: stripPasses) { noradID in
                        model.select(noradID)
                    }
                }
                if let selected = model.selectedPosition {
                    SatelliteInfoCard(
                        position: selected,
                        transmitters: model.transmitters(for: selected.noradID),
                        look: model.selectedLook,
                        amsatStatus: model.amsatStatus(for: selected.noradID),
                        reports: model.selectedReports,
                        communityActivity: model.communityActivity,
                        communityRows: model.selectedCommunityRows,
                        onOpenCommunity: { rowID in
                            communityInitialRow = rowID
                            showCommunity = true
                        },
                        onReportCommunity: { showCommunityReport = true },
                        polarization: model.polarization(for: selected.noradID),
                        nextPassProvider: { [noradID = selected.noradID] in
                            await model.passForecast(for: noradID).passes.first
                        },
                        onShowPasses: { showPassList = true },
                        onPoint: { showPointing = true },
                        onLog: {
                            pendingRecording = SatellitePassRecorder.shared
                                .recentRecording(noradID: selected.noradID)
                            showQuickLog = true
                        },
                        onDismiss: { model.select(nil) }
                    )
                }
                timeScrubber
                statusBar
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .overlay {
            if showDome {
                SatelliteSkyDomeView(model: model, motion: motion) {
                    domeSuppressed = true
                    withAnimation(.easeInOut(duration: 0.3)) {
                        showDome = false
                    }
                }
                .transition(.opacity)
            }
        }
        .onAppear {
            motion.start()
        }
        .onDisappear {
            // The pointing cover removes this view from the hierarchy but
            // still needs live attitude — keep motion running for it.
            if !showPointing {
                motion.stop()
            }
        }
    }

    /// Toggle between heading-up (map rotates with the device compass)
    /// and locked north-up.
    var headingLockButton: some View {
        Button {
            mapHeadingLocked.toggle()
        } label: {
            Image(systemName: mapHeadingLocked ? "lock.rotation" : "lock.open.rotation")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(mapHeadingLocked ? Color.primary : Color.accentColor)
                .frame(width: 40, height: 40)
                .background(.regularMaterial, in: Circle())
        }
        .accessibilityLabel(mapHeadingLocked ? "Rotate map with device" : "Lock map north-up")
        .padding(.trailing)
        .padding(.top, 8)
    }

    /// Observer priority: live GPS fix, then profile grid, then logger grid.
    func updateObserver() {
        if let coordinate = gpsService.currentCoordinate {
            model.setObserver(coordinate)
            // Persist the fix so the alert scheduler can predict headlessly
            // (background refresh, app foreground) without GPS.
            UserDefaults.standard.set(
                "\(coordinate.latitude),\(coordinate.longitude)",
                forKey: SatellitePassAlertScheduler.lastObserverKey
            )
        } else if let coordinate = MaidenheadConverter.coordinate(from: myGrid) {
            model.setObserver(coordinate)
        } else if let coordinate = MaidenheadConverter.coordinate(from: loggerDefaultGrid) {
            model.setObserver(coordinate)
        }
    }

    func updateSkyDome(pointingElevation: Double) {
        if showDome {
            if pointingElevation < Self.domeExitElevationDeg {
                withAnimation(.easeInOut(duration: 0.3)) {
                    showDome = false
                }
            }
        } else if pointingElevation > Self.domeEnterElevationDeg, !domeSuppressed, model.state == .loaded {
            withAnimation(.easeInOut(duration: 0.3)) {
                showDome = true
            }
        }
        if domeSuppressed, pointingElevation < Self.domeExitElevationDeg {
            domeSuppressed = false
        }
    }
}
