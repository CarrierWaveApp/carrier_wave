import CarrierWaveData
import CoreMotion
import SwiftUI
import UIKit

// MARK: - AntennaPointingView

/// Antenna-mount mode: lay the phone flat on the boom — screen up, top
/// edge toward the antenna tip — and read the screen from afar. The
/// boresight is the device +Y axis (out the top edge), 90° from the back
/// camera, so guidance is correct with the phone strapped flat instead of
/// held up to the sky. Guidance follows
/// G1000 conventions on the app's sky-dome theme (black, orange fly-to
/// markers): a compass-tape section with a target bug for azimuth, a
/// glideslope-style deviation scale for elevation, big left/right and
/// up/down corrections tinted with the semantic status color (red = far
/// off, orange = close, green = locked) that also frames the screen edge.
/// An optional AR overlay shows the live camera with the satellite marker
/// projected onto the sky. Once locked it shows the Doppler-corrected
/// downlink/uplink to tune plus the polarization hint. Below the horizon
/// it counts down to the next pass and steers toward the rise point so
/// the antenna can be pre-aimed.
struct AntennaPointingView: View {
    // MARK: Internal

    let model: SatelliteTrackerModel
    let motion: AntennaMotionService
    let onDismiss: () -> Void

    // `forecast`/`showQuickLog`/`pendingRecording` are internal (not
    // fileprivate) because the capture extension lives in
    // AntennaPointingView+Capture.swift.
    @State var forecast = SatellitePassForecast.empty
    @State var showQuickLog = false
    @State var pendingRecording: SatellitePassRecording?
    /// Next pass's sky arc for the below-horizon plot (+PassArc).
    @State var passArc = [SatelliteSkySample]()
    @State var passArcAnchor: Date?
    @State var showDuplexSheet = false
    @State var showRotatorSheet = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 15)) { timeline in
            let frame = makeFrame(at: timeline.date)
            ZStack {
                Color.black.ignoresSafeArea()
                if arEnabled, camera.isAuthorized {
                    cameraLayer
                }
                boresightLayer(frame)
                // Far-visible status: a thick semantic-color frame around
                // the whole screen instead of a full-bleed background.
                Rectangle()
                    .strokeBorder(statusColor(for: frame), lineWidth: 12)
                    .ignoresSafeArea()
                VStack(spacing: 0) {
                    header(frame)
                    if arEnabled, cameraDenied {
                        Text("Camera access denied — allow it in Settings to use the overlay")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    if let pointing = frame.pointingAzDeg, let guidance = frame.guidanceAzDeg {
                        PointingCompassTape(pointingAzDeg: pointing, targetAzDeg: guidance)
                            .padding(.top, 6)
                    }
                    Spacer()
                    centerContent(frame, at: timeline.date)
                    Spacer()
                    recordControls
                        .padding(.bottom, 10)
                    footer(frame)
                }
                .padding(20)
                // Nothing to tilt toward below the horizon: azimuth only.
                if let elError = frame.elErrorDeg, !isBelowHorizon(frame) {
                    HStack {
                        Spacer()
                        PointingElevationScale(elErrorDeg: elError)
                            .padding(.trailing, 8)
                    }
                }
            }
            .sensoryFeedback(.impact(weight: .heavy), trigger: frame.isLocked)
        }
        .statusBarHidden()
        .environment(\.colorScheme, .dark)
        .sheet(isPresented: $showQuickLog) {
            quickLogSheet
        }
        .sheet(isPresented: $showDuplexSheet) {
            SatelliteDuplexSheet(model: model)
        }
        .sheet(isPresented: $showRotatorSheet) {
            SatelliteRotatorSheet(model: model)
        }
        .trackerDetectedAlert(model: model)
        .onChange(of: arEnabled) { _, enabled in
            if enabled {
                Task {
                    await camera.start()
                    cameraDenied = !camera.isAuthorized
                }
            } else {
                camera.stop()
                cameraDenied = false
            }
        }
        .task {
            UIApplication.shared.isIdleTimerDisabled = true
            Self.lockPortrait()
            motion.start()
            // Relink the remembered rotator and feed it targets; detached so
            // a slow connect never delays the SGP4 sync loop below. Follow
            // stays off until the operator turns it on in the sheet.
            Task {
                await rotatorService.connectSavedIfNeeded()
                if rotatorService.rotator.isConnected {
                    rotatorService.start(model: model)
                }
            }
            if arEnabled {
                await camera.start()
                cameraDenied = !camera.isAuthorized
            }
            if let noradID = model.selectedNoradID {
                forecast = await model.passForecast(for: noradID)
                await refreshPassArc()
            }
            // The map's 5s SGP4 sync task cancels while this cover is up;
            // run our own so dead-reckoning stays anchored during a pass.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                await model.refreshPositions()
                await refreshPassArc()
            }
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            Self.unlockOrientation()
            motion.cancelBoomCalibration()
            camera.stop()
            // No background-audio mode — the recording ends with the
            // pointing session (persisted, so the quick log can replay it).
            SatellitePassRecorder.shared.stopIfRecording()
        }
    }

    // MARK: Fileprivate

    /// Lock threshold matches the sky dome's lock-on cone.
    fileprivate static let lockDeg = 5.0
    fileprivate static let nearDeg = 20.0

    @State fileprivate var camera = PointingCameraController()
    @State fileprivate var cameraDenied = false
    /// Camera passthrough with the projected satellite marker (persisted).
    @AppStorage("satellitePointingAROverlay") fileprivate var arEnabled = false

    /// Two-bridge FM duplex tuning; the header button tints while it runs.
    fileprivate let duplex = SatelliteDuplexController.shared
    /// LAN rotator (S.A.T. / PSR-100 / rotctld); the header button tints
    /// while the antenna follows the satellite.
    fileprivate let rotatorService = SatelliteRotatorService.shared
}

// MARK: - Subviews

private extension AntennaPointingView {
    /// Optional camera passthrough with a legibility scrim. On a flat
    /// mount the camera faces 90° from the boom, so this is context only.
    @ViewBuilder
    var cameraLayer: some View {
        PointingCameraPreview(session: camera.session)
            .ignoresSafeArea()
        Color.black.opacity(0.25)
            .ignoresSafeArea()
    }

    /// Boom-boresight targeting display: the satellite marker projected
    /// along the antenna axis plus the fixed center crosshair, on whenever
    /// the bird is up so it's visibly in the target when locked. Nothing to
    /// aim at below the horizon, so no reticle there.
    @ViewBuilder
    func boresightLayer(_ frame: PointingFrame) -> some View {
        if case .belowHorizon = frame.phase {
            EmptyView()
        } else if let matrix = motion.rotationMatrix, let azimuth = frame.targetAzDeg,
                  let elevation = frame.targetElDeg
        {
            PointingARMarker(
                matrix: matrix,
                boomAxis: motion.boomAxis,
                azDeg: azimuth,
                elDeg: elevation,
                isLocked: frame.isLocked,
                name: frame.name
            )
            .ignoresSafeArea()
            PointingARCrosshair()
        } else {
            PointingARCrosshair()
        }
    }

    func header(_ frame: PointingFrame) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 1) {
                Text(frame.name)
                    .font(.system(size: 26, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                if let detail = frame.detailName {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
            }
            Spacer()
            headerButton(
                "gyroscope",
                tint: motion.isCalibratingBoom ? .orange : .white,
                label: motion.isCalibratingBoom ? "Cancel boom calibration" : "Calibrate boom axis"
            ) {
                if motion.isCalibratingBoom {
                    motion.cancelBoomCalibration()
                } else {
                    motion.startBoomCalibration()
                }
            }
            headerButton(
                "antenna.radiowaves.left.and.right",
                tint: duplex.isTuning ? .orange : .white,
                label: duplex.isTuning ? "Duplex radios (tuning)" : "Duplex radios"
            ) {
                showDuplexSheet = true
            }
            headerButton(
                "dial.medium",
                tint: rotatorService.rotator.isFollowing ? .orange : .white,
                label: rotatorService.rotator.isFollowing ? "Rotator (following)" : "Rotator & trackers"
            ) {
                showRotatorSheet = true
            }
            headerButton(
                arEnabled ? "video.fill" : "video",
                tint: arEnabled ? .orange : .white,
                label: arEnabled ? "Turn off camera overlay" : "Turn on camera overlay"
            ) {
                arEnabled.toggle()
            }
            headerButton("xmark", size: 20, label: "Exit pointing mode", action: onDismiss)
        }
    }

    /// One 44 pt round header control on the sky-dome theme.
    func headerButton(
        _ systemImage: String,
        tint: Color = .white,
        size: CGFloat = 18,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .background(.black.opacity(0.25), in: Circle())
        }
        .accessibilityLabel(label)
    }

    @ViewBuilder
    func centerContent(_ frame: PointingFrame, at date: Date) -> some View {
        if motion.isCalibratingBoom {
            PointingCalibrationContent(progress: motion.boomCalibrationProgress)
        } else if let outcome = motion.boomCalibrationOutcome,
                  let stamped = motion.boomCalibrationOutcomeAt,
                  date.timeIntervalSince(stamped) < 4
        {
            calibrationOutcome(outcome)
        } else {
            phaseContent(frame, at: date)
        }
    }

    @ViewBuilder
    func calibrationOutcome(_ outcome: AntennaMotionService.BoomCalibrationOutcome) -> some View {
        switch outcome {
        case let .calibrated(trimDeg):
            Label(String(format: "BOOM SET — TRIM %.1f°", trimDeg), systemImage: "checkmark.circle.fill")
                .font(.system(size: 24, weight: .black))
                .foregroundStyle(.green)
        case .failed:
            Text("Calibration failed — twist only around the boom")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.orange)
                .multilineTextAlignment(.center)
        }
    }

    @ViewBuilder
    func phaseContent(_ frame: PointingFrame, at date: Date) -> some View {
        switch frame.phase {
        case let .noData(reason):
            Text(reason)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
        case let .belowHorizon(nextPass):
            VStack(spacing: 20) {
                PointingBelowHorizonContent(nextPass: nextPass, now: date)
                passArcPlot(frame, at: date)
                quickLogButton
            }
        case let .tracking(isLocked):
            PointingTrackingContent(
                frame: frame,
                isLocked: isLocked,
                tint: statusColor(for: frame),
                polarization: model.selectedNoradID.flatMap { model.polarization(for: $0) },
                motion: motion
            )
        }
    }

    func footer(_ frame: PointingFrame) -> some View {
        VStack(spacing: 4) {
            if let azimuth = frame.targetAzDeg, let elevation = frame.targetElDeg {
                Text(
                    isBelowHorizon(frame)
                        ? String(format: "AZ %03.0f°", azimuth)
                        : String(format: "AZ %03.0f°   EL %+.0f°", azimuth, elevation)
                )
                .font(.system(size: 22, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.9))
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(.regularMaterial, in: Capsule())
            }
            if motion.boomTrimDeg > 0.5 {
                Text(String(format: "Boom trim %.1f°", motion.boomTrimDeg))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
    }

    /// Semantic status color (design language): green = locked, orange =
    /// close, red = far off, blue = informational (below horizon).
    func statusColor(for frame: PointingFrame) -> Color {
        switch frame.phase {
        case .noData:
            return .gray
        case .belowHorizon:
            return .blue
        case let .tracking(isLocked):
            if isLocked {
                return .green
            }
            return (frame.offAxisDeg ?? 180) < Self.nearDeg ? .orange : .red
        }
    }
}

// MARK: - Frame computation

private extension AntennaPointingView {
    func makeFrame(at date: Date) -> PointingFrame {
        guard let position = model.selectedPosition else {
            return PointingFrame(phase: .noData(reason: "No satellite selected"))
        }
        var frame = PointingFrame(phase: .noData(reason: "Waiting for motion + location…"))
        frame.name = position.name
        frame.detailName = position.detailName
        applyTuning(&frame, position: position)
        guard let azimuth = position.azimuthDeg,
              let elevation = position.elevationDeg,
              let matrix = motion.rotationMatrix,
              let pointingAz = motion.boomAzimuthDeg,
              let pointingEl = motion.boomElevationDeg
        else {
            return frame
        }
        let elapsed = date.timeIntervalSince(model.positionsSyncedAt)
        let azNow = Self.wrapAzimuth(azimuth + position.azRateDegPerSec * elapsed)
        let elNow = elevation + position.elRateDegPerSec * elapsed
        frame.targetAzDeg = azNow
        frame.targetElDeg = elNow
        frame.pointingAzDeg = pointingAz
        let projector = SkyProjector(
            matrix: matrix,
            size: CGSize(width: 1, height: 1),
            boomAxis: motion.boomAxis
        )
        let guidanceAz: Double
        let guidanceEl: Double
        if elNow <= 0 {
            let nextPass = forecast.passes.first { $0.los > date }
            guidanceAz = nextPass?.aosAzimuthDeg ?? azNow
            guidanceEl = 0
            frame.phase = .belowHorizon(nextPass: nextPass)
        } else {
            guidanceAz = azNow
            guidanceEl = elNow
            let offAxis = projector.boomOffAxisDeg(azDeg: azNow, elDeg: elNow)
            frame.offAxisDeg = offAxis
            frame.phase = .tracking(isLocked: offAxis < Self.lockDeg)
        }
        frame.guidanceAzDeg = guidanceAz
        frame.azErrorDeg = Self.wrap180(guidanceAz - pointingAz)
        frame.elErrorDeg = guidanceEl - pointingEl
        return frame
    }

    /// Doppler-corrected tuning from the primary (active, downlink-bearing)
    /// transmitter and the propagated slant-range rate.
    func applyTuning(_ frame: inout PointingFrame, position: SatellitePosition) {
        let transmitters = model.transmitters(for: position.noradID)
        guard let primary = SatelliteDuplexController.primaryTransmitter(in: transmitters) else {
            return
        }
        frame.mode = primary.mode
        let factor = SatelliteDuplexController.dopplerFactor(rangeRateKmPerSec: position.rangeRateKmPerSec)
        if let downlink = primary.downlinkLow {
            frame.downlinkMHz = Double(downlink) * (1 + factor) / 1_000_000
            frame.dopplerShiftKHz = Double(downlink) * factor / 1_000
        }
        if let uplink = primary.uplinkLow {
            frame.uplinkMHz = Double(uplink) * (1 - factor) / 1_000_000
        }
    }

    /// Pin the UI to portrait while the phone is boom-mounted: twisting
    /// the antenna for polarization rolls the phone through landscape,
    /// which must not rotate the instruments mid-pass.
    static func lockPortrait() {
        AppDelegate.orientationLock = .portrait
        applyOrientationChange(.portrait)
    }

    static func unlockOrientation() {
        AppDelegate.orientationLock = nil
        applyOrientationChange(nil)
    }

    private static func applyOrientationChange(_ mask: UIInterfaceOrientationMask?) {
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            if let mask {
                scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask))
            }
            scene.keyWindow?.rootViewController?
                .setNeedsUpdateOfSupportedInterfaceOrientations()
        }
    }

    static func wrapAzimuth(_ degrees: Double) -> Double {
        var value = degrees.truncatingRemainder(dividingBy: 360)
        if value < 0 {
            value += 360
        }
        return value
    }

    static func wrap180(_ degrees: Double) -> Double {
        var value = degrees.truncatingRemainder(dividingBy: 360)
        if value > 180 {
            value -= 360
        }
        if value < -180 {
            value += 360
        }
        return value
    }
}
