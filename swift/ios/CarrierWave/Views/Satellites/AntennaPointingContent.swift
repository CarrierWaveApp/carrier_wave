import CarrierWaveCore
import CarrierWaveData
import SwiftUI

// MARK: - PointingFrame

/// Everything one render frame of the pointing screen needs, computed from
/// the dead-reckoned satellite position and the device attitude.
struct PointingFrame {
    enum Phase: Equatable {
        case noData(reason: String)
        case belowHorizon(nextPass: SatellitePass?)
        case tracking(isLocked: Bool)
    }

    var phase: Phase
    var name = ""
    var detailName: String?
    var targetAzDeg: Double?
    var targetElDeg: Double?
    /// Boresight azimuth from the attitude, for the compass tape.
    var pointingAzDeg: Double?
    /// Azimuth the guidance instruments steer toward: the satellite, or its
    /// rise point when it's below the horizon.
    var guidanceAzDeg: Double?
    /// Guidance errors: how far to swing (+ = right) and tilt (+ = up).
    var azErrorDeg: Double?
    var elErrorDeg: Double?
    var offAxisDeg: Double?
    var downlinkMHz: Double?
    var uplinkMHz: Double?
    var dopplerShiftKHz: Double?
    var mode: String?

    var isLocked: Bool {
        if case let .tracking(locked) = phase {
            return locked
        }
        return false
    }
}

// MARK: - PointingTuningReadout

/// Doppler-corrected tuning block: downlink, uplink, mode, Doppler shift.
/// One size in every tracking state.
struct PointingTuningReadout: View {
    // MARK: Internal

    let frame: PointingFrame

    var body: some View {
        VStack(spacing: 14) {
            if let downlink = frame.downlinkMHz {
                frequencyLine(prefix: "↓", megahertz: downlink, size: 64)
            }
            if let uplink = frame.uplinkMHz {
                frequencyLine(prefix: "↑", megahertz: uplink, size: 40)
            }
            HStack(spacing: 10) {
                if let mode = frame.mode {
                    Text(mode)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .background(ModeColors.color(for: mode).opacity(0.35))
                        .clipShape(Capsule())
                }
                if let shift = frame.dopplerShiftKHz {
                    Text(String(format: "Doppler %+.1f kHz", shift))
                        .monospacedDigit()
                }
            }
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(.white.opacity(0.9))
        }
    }

    // MARK: Private

    private func frequencyLine(prefix: String, megahertz: Double, size: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(prefix)
                .font(.system(size: size * 0.6, weight: .black))
            Text(String(format: "%.3f", megahertz))
                .font(.system(size: size, weight: .black, design: .monospaced))
        }
        .foregroundStyle(.white)
        .lineLimit(1)
        .minimumScaleFactor(0.5)
    }
}

// MARK: - PointingTrackingContent

/// Tracking layout with a stable frame: the correction readout's slot and
/// the polarization hint line stay allocated in both states (invisible
/// rather than removed) and the tuning block has one size — so the
/// frequency readout never moves when lock is gained or lost.
struct PointingTrackingContent: View {
    // MARK: Internal

    let frame: PointingFrame
    let isLocked: Bool
    let tint: Color
    /// Curated downlink polarization from the engine's table, if known.
    let polarization: FfiSatPolarization?
    let motion: AntennaMotionService

    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                if let azError = frame.azErrorDeg, let elError = frame.elErrorDeg {
                    PointingCorrectionReadout(
                        azErrorDeg: azError,
                        elErrorDeg: elError,
                        tint: tint
                    )
                    .opacity(isLocked ? 0 : 1)
                }
                if isLocked {
                    Label("ON TARGET", systemImage: "scope")
                        .font(.system(size: 24, weight: .black))
                        .foregroundStyle(.green)
                }
            }
            PointingTuningReadout(frame: frame)
            if let hint = polarizationHint {
                Text(hint)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .opacity(isLocked ? 1 : 0)
            }
        }
    }

    // MARK: Private

    /// Circular birds get the static hint; linear ones the live roll.
    private var polarizationHint: String? {
        if let polarization, polarization.isCircular {
            return polarization.pointingHint
        }
        guard let tilt = motion.elementTiltDeg else {
            return nil
        }
        return String(format: "Roll %.0f° — twist to peak, flip 90° if it fades", tilt)
    }
}

// MARK: - PointingCalibrationContent

/// Boom-axis calibration in progress: the operator twists the antenna
/// back and forth while the gyro's rotation axis is averaged into the
/// true boom axis.
struct PointingCalibrationContent: View {
    let progress: Double

    var body: some View {
        VStack(spacing: 14) {
            Text("TWIST THE ANTENNA")
                .font(.system(size: 24, weight: .black))
                .foregroundStyle(.orange)
            Text("Roll it back and forth around the boom")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white.opacity(0.9))
            ProgressView(value: min(1, progress))
                .tint(.orange)
                .frame(maxWidth: 220)
        }
        .multilineTextAlignment(.center)
    }
}

// MARK: - PointingBelowHorizonContent

/// Below the horizon: countdown to the next pass. The compass tape and
/// elevation scale steer toward the rise point for pre-aiming.
struct PointingBelowHorizonContent: View {
    // MARK: Internal

    let nextPass: SatellitePass?
    let now: Date

    var body: some View {
        VStack(spacing: 14) {
            Text("BELOW HORIZON")
                .font(.system(size: 24, weight: .black))
                .foregroundStyle(.white.opacity(0.8))
            if let nextPass {
                Text(countdown(to: nextPass))
                    .font(.system(size: 80, weight: .black))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                Text("Rises \(SatellitePassRow.compassLabel(nextPass.aosAzimuthDeg))"
                    + String(format: " · max %.0f°", nextPass.peakElevationDeg))
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
            } else {
                Text("No pass in the next 48 hours")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
            }
        }
    }

    // MARK: Private

    /// mm:ss inside the last hour for a live countdown, h/m beyond.
    private func countdown(to pass: SatellitePass) -> String {
        let interval = pass.aos.timeIntervalSince(now)
        guard interval > 0 else {
            return "RISING"
        }
        if interval < 3_600 {
            return String(format: "%d:%02d", Int(interval) / 60, Int(interval) % 60)
        }
        let minutes = Int(interval / 60)
        return "\(minutes / 60)h \(String(format: "%02d", minutes % 60))m"
    }
}
