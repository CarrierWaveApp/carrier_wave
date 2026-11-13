import CoreMotion

// MARK: - AntennaMotionService

/// Publishes device attitude for the Satellites sky dome and pointing
/// screen. Two boresights: the sky dome's "pointing" direction is the back
/// camera (device −Z — raise the phone and look at the sky through it);
/// the antenna-mount "boom" direction defaults to device +Y (out the top
/// edge — the phone lies flat on the boom with the screen up, so the
/// boresight is 90° from the camera) and can be trimmed to the true boom
/// axis via the gyro twist calibration, since a strapped phone is rarely
/// perfectly parallel to the boom.
@MainActor
@Observable
final class AntennaMotionService {
    // MARK: Lifecycle

    init() {
        boomAxis = Self.loadBoomAxis()
    }

    // MARK: Internal

    enum BoomCalibrationOutcome: Equatable {
        case calibrated(trimDeg: Double)
        case failed
    }

    /// Attitude matrix mapping reference-frame vectors into the device
    /// frame (reference: X = north, Y = west, Z = up).
    private(set) var rotationMatrix: CMRotationMatrix?
    private(set) var isRunning = false
    private(set) var usesTrueNorth = true

    /// Antenna boom axis in the device frame — nominally +Y (out the top
    /// edge), replaced by the gyro-calibrated axis after a twist cal.
    private(set) var boomAxis = SIMD3<Double>(0, 1, 0)

    private(set) var isCalibratingBoom = false
    /// 0…1 while calibrating: fraction of the required twist samples.
    private(set) var boomCalibrationProgress = 0.0
    private(set) var boomCalibrationOutcome: BoomCalibrationOutcome?
    private(set) var boomCalibrationOutcomeAt: Date?

    var isAvailable: Bool {
        manager.isDeviceMotionAvailable
    }

    /// Elevation of the back camera direction (device −Z) above the
    /// horizon, in degrees. Drives the tilt-up sky-dome trigger.
    var pointingElevationDeg: Double? {
        guard let matrix = rotationMatrix else {
            return nil
        }
        return asin(max(-1, min(1, -matrix.m33))) * 180 / .pi
    }

    /// Compass azimuth of the back-camera pointing direction (device −Z),
    /// in degrees clockwise from north. Degenerate (nil) at the zenith.
    var pointingAzimuthDeg: Double? {
        guard let matrix = rotationMatrix else {
            return nil
        }
        // Reference axes: X = north, Y = west, Z = up. Device −Z expressed
        // in the reference frame is the negated third row of the matrix.
        let north = -matrix.m31
        let east = matrix.m32
        guard abs(north) > 1e-6 || abs(east) > 1e-6 else {
            return nil
        }
        let azimuth = atan2(east, north) * 180 / .pi
        return azimuth < 0 ? azimuth + 360 : azimuth
    }

    /// Angle between the calibrated boom axis and nominal +Y, degrees.
    var boomTrimDeg: Double {
        acos(max(-1, min(1, boomAxis.y))) * 180 / .pi
    }

    /// Elevation of the antenna boom axis above the horizon, in degrees.
    /// Boresight for the pointing screen: the phone lies flat on the boom,
    /// screen up, top toward the tip.
    var boomElevationDeg: Double? {
        boomAxisReference.map { asin(max(-1, min(1, $0.z))) * 180 / .pi }
    }

    /// Compass azimuth of the boom axis, in degrees clockwise from north.
    /// Degenerate (nil) at the zenith.
    var boomAzimuthDeg: Double? {
        guard let ref = boomAxisReference else {
            return nil
        }
        let north = ref.x
        let east = -ref.y
        guard abs(north) > 1e-6 || abs(east) > 1e-6 else {
            return nil
        }
        let azimuth = atan2(east, north) * 180 / .pi
        return azimuth < 0 ? azimuth + 360 : azimuth
    }

    /// Tilt of the device X axis away from horizontal, in degrees —
    /// the polarization roll for antenna elements mounted along X
    /// (0° ≈ horizontal, ±90° ≈ vertical).
    var elementTiltDeg: Double? {
        guard let matrix = rotationMatrix else {
            return nil
        }
        return asin(max(-1, min(1, matrix.m13))) * 180 / .pi
    }

    /// Compass heading the device is "facing", in degrees clockwise from
    /// north. Drives the heading-up map rotation.
    ///
    /// Blends the horizontal projections of the top-of-screen axis (+Y,
    /// dominant when flat) and the back-camera axis (−Z, dominant when
    /// raised). Under a pure tilt-up both project onto the same azimuth,
    /// with magnitudes that crossfade — so the heading stays stable through
    /// the whole raise instead of spinning as +Y alone goes degenerate near
    /// vertical, and it matches the sky dome's pointing azimuth on handoff.
    var screenHeadingDeg: Double? {
        guard let matrix = rotationMatrix else {
            return nil
        }
        // Reference axes are X = north, Y = west, Z = up; device +Y in the
        // reference frame is row 2, device −Z is the negated row 3.
        let north = matrix.m21 - matrix.m31
        let east = -matrix.m22 + matrix.m32
        guard abs(north) > 1e-6 || abs(east) > 1e-6 else {
            return nil
        }
        let heading = atan2(east, north) * 180 / .pi
        return heading < 0 ? heading + 360 : heading
    }

    /// Begin the boom-axis twist calibration: while the user twists the
    /// antenna back and forth, the gyro's instantaneous rotation axis IS
    /// the boom axis in the device frame. Finishes itself once enough
    /// fast-twist samples are collected.
    func startBoomCalibration() {
        calibrationSamples.removeAll()
        boomCalibrationProgress = 0
        boomCalibrationOutcome = nil
        boomCalibrationOutcomeAt = nil
        isCalibratingBoom = true
    }

    func cancelBoomCalibration() {
        isCalibratingBoom = false
        calibrationSamples.removeAll()
        boomCalibrationProgress = 0
    }

    /// Drop any calibration and return to the nominal +Y boresight.
    func resetBoomAxis() {
        boomAxis = SIMD3(0, 1, 0)
        UserDefaults.standard.removeObject(forKey: Self.boomAxisKey)
        boomCalibrationOutcome = nil
        boomCalibrationOutcomeAt = nil
    }

    func start() {
        guard !isRunning, manager.isDeviceMotionAvailable else {
            return
        }
        let frames = CMMotionManager.availableAttitudeReferenceFrames()
        let frame: CMAttitudeReferenceFrame =
            frames.contains(.xTrueNorthZVertical) ? .xTrueNorthZVertical : .xMagneticNorthZVertical
        usesTrueNorth = frame == .xTrueNorthZVertical
        manager.deviceMotionUpdateInterval = 1.0 / 30.0
        manager.startDeviceMotionUpdates(using: frame, to: .main) { [weak self] motion, _ in
            guard let self, let motion else {
                return
            }
            rotationMatrix = motion.attitude.rotationMatrix
            if isCalibratingBoom {
                ingestCalibrationSample(motion.rotationRate)
            }
        }
        isRunning = true
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
        rotationMatrix = nil
        isRunning = false
        cancelBoomCalibration()
    }

    // MARK: Private

    private static let boomAxisKey = "satelliteBoomAxis"
    /// ~2 s of active twisting at 30 Hz.
    private static let calibrationSampleTarget = 60
    /// Ignore gyro samples slower than this (rad/s) — they carry more
    /// hand-wobble than twist.
    private static let calibrationMinRateRadPerSec = 0.8
    /// Reject a calibrated axis further than this from nominal +Y: the
    /// user rotated about something other than the boom.
    private static let calibrationMaxTrimDeg = 30.0

    private let manager = CMMotionManager()
    private var calibrationSamples: [SIMD3<Double>] = []

    /// Boom axis expressed in the reference frame (X=north, Y=west, Z=up):
    /// the device→reference rows of the attitude matrix weighted by the
    /// device-frame axis components.
    private var boomAxisReference: SIMD3<Double>? {
        guard let matrix = rotationMatrix else {
            return nil
        }
        let axis = boomAxis
        return SIMD3(
            axis.x * matrix.m11 + axis.y * matrix.m21 + axis.z * matrix.m31,
            axis.x * matrix.m12 + axis.y * matrix.m22 + axis.z * matrix.m32,
            axis.x * matrix.m13 + axis.y * matrix.m23 + axis.z * matrix.m33
        )
    }

    private static func loadBoomAxis() -> SIMD3<Double> {
        let fallback = SIMD3<Double>(0, 1, 0)
        guard let stored = UserDefaults.standard.string(forKey: boomAxisKey) else {
            return fallback
        }
        let parts = stored.split(separator: ",").compactMap { Double($0) }
        guard parts.count == 3 else {
            return fallback
        }
        var axis = SIMD3(parts[0], parts[1], parts[2])
        let magnitude = (axis.x * axis.x + axis.y * axis.y + axis.z * axis.z).squareRoot()
        guard magnitude > 1e-6 else {
            return fallback
        }
        axis /= magnitude
        let trim = acos(max(-1, min(1, axis.y))) * 180 / .pi
        return trim < calibrationMaxTrimDeg ? axis : fallback
    }

    private func ingestCalibrationSample(_ rate: CMRotationRate) {
        var sample = SIMD3(rate.x, rate.y, rate.z)
        let magnitude = (sample.x * sample.x + sample.y * sample.y + sample.z * sample.z).squareRoot()
        guard magnitude > Self.calibrationMinRateRadPerSec else {
            return
        }
        sample /= magnitude
        // The twist alternates direction; fold both into the +Y hemisphere.
        if sample.y < 0 {
            sample = -sample
        }
        calibrationSamples.append(sample)
        boomCalibrationProgress =
            Double(calibrationSamples.count) / Double(Self.calibrationSampleTarget)
        if calibrationSamples.count >= Self.calibrationSampleTarget {
            finishCalibration()
        }
    }

    private func finishCalibration() {
        isCalibratingBoom = false
        var sum = SIMD3<Double>(0, 0, 0)
        for sample in calibrationSamples {
            sum += sample
        }
        let count = Double(calibrationSamples.count)
        calibrationSamples.removeAll()
        let magnitude = (sum.x * sum.x + sum.y * sum.y + sum.z * sum.z).squareRoot()
        let mean = sum / max(magnitude, 1e-9)
        let trim = acos(max(-1, min(1, mean.y))) * 180 / .pi
        // Coherent (samples clustered on one axis) and plausibly boom-like.
        guard magnitude > count * 0.9, trim < Self.calibrationMaxTrimDeg else {
            boomCalibrationOutcome = .failed
            boomCalibrationOutcomeAt = Date()
            return
        }
        boomAxis = mean
        UserDefaults.standard.set("\(mean.x),\(mean.y),\(mean.z)", forKey: Self.boomAxisKey)
        boomCalibrationOutcome = .calibrated(trimDeg: trim)
        boomCalibrationOutcomeAt = Date()
    }
}
