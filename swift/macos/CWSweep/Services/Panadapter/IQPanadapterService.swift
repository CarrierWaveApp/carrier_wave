import CarrierWaveCwFfi
import Foundation
import OSLog

private let logger = Logger(subsystem: "com.jsvana.CWSweep", category: "IQPanadapter")

// MARK: - IQPanadapterService

/// Feeds the shared `WaterfallStore` from an external SDR (SoapySDR, rtl_tcp)
/// through the Rust `cw-sdr` pipeline. Independent of the CAT transport: the
/// rig's frequency / mode / RIT / TX state is pushed in via `updateTuning`,
/// and Rust maps the SDR spectrum onto RF (IF tap or direct RF) and returns
/// VFO-centered, normalized lines.
@MainActor
@Observable
final class IQPanadapterService {
    // MARK: Lifecycle

    init(store: WaterfallStore, defaults: UserDefaults = .standard) {
        self.store = store
        self.defaults = defaults
        settings = SDRInputSettings.load(from: defaults)
    }

    // MARK: Internal

    enum Status: Equatable {
        case off
        case waitingForRig
        case running
        case failed(String)

        // MARK: Internal

        var description: String {
            switch self {
            case .off: "Off"
            case .waitingForRig: "Waiting for radio (CAT) and SDR…"
            case .running: "Running"
            case let .failed(message): "Error: \(message)"
            }
        }
    }

    private(set) var settings: SDRInputSettings
    private(set) var status: Status = .off
    private(set) var isPausedForTransmit = false
    private(set) var noiseFloorDB: Float?

    /// Current CAT mode, as last pushed by `updateTuning` (for calibration UI).
    private(set) var currentMode = ""

    /// Strongest bin within ±`searchHz` of the center, as a Hz offset from
    /// the center frequency.
    nonisolated static func peakOffsetHz(line: [Float], spanHz: Double, searchHz: Double = 5_000) -> Double? {
        guard !line.isEmpty, spanHz > 0 else {
            return nil
        }
        let binHz = spanHz / Double(line.count)
        let center = Double(line.count) / 2
        let reach = Int((searchHz / binHz).rounded())
        let lower = max(0, Int(center) - reach)
        let upper = min(line.count - 1, Int(center) + reach)
        guard lower <= upper,
              let peak = (lower ... upper).max(by: { line[$0] < line[$1] })
        else {
            return nil
        }
        return (Double(peak) + 0.5 - center) * binHz
    }

    /// Start streaming if the saved settings enable it (called at launch).
    func startIfEnabled() {
        if settings.enabled {
            restart()
        }
    }

    /// Persist new settings and restart (or stop) the pipeline.
    func apply(_ newSettings: SDRInputSettings) {
        settings = newSettings
        settings.save(to: defaults)
        restart()
    }

    /// Push the focused rig's CAT state. Cheap to call on every poll; only
    /// changes cross the FFI boundary.
    func updateTuning(
        frequencyMHz: Double,
        mode: String,
        ritHz: Int,
        ritEnabled: Bool,
        transmitting: Bool
    ) {
        let tuning = Tuning(
            vfoHz: (frequencyMHz * 1_000_000).rounded(),
            mode: SDRInputSettings.modeKey(mode),
            ritHz: Double(ritHz),
            ritEnabled: ritEnabled,
            transmitting: transmitting
        )
        currentMode = tuning.mode
        isPausedForTransmit = transmitting && handle != nil
        guard tuning != lastTuning, frequencyMHz > 0 else {
            return
        }
        lastTuning = tuning
        handle?.setTuning(tuning: tuning.ffi)
    }

    /// Solve the IF calibration for the current mode: with the rig tuned
    /// exactly onto a known carrier (WWV, a beacon, a zero-beat CW signal),
    /// the strongest signal near the center of the newest line should sit
    /// on the VFO. Returns a user-facing result message.
    func calibrateOnStrongestSignal() -> String {
        guard settings.tuningKind == .ifTap else {
            return "Calibration applies to the IF-output mode only."
        }
        guard store.source == .sdr, let line = store.magnitudes.first, !line.isEmpty,
              let offsetHz = Self.peakOffsetHz(line: line, spanHz: store.spanKHz * 1_000)
        else {
            return "No SDR waterfall data yet."
        }
        // rf_displayed − rf_true = sign · (cal_true − cal) ⇒ cal_true = cal + sign · offset
        let sign: Double = settings.ifInverted ? -1 : 1
        let key = SDRInputSettings.modeKey(currentMode.isEmpty ? "*" : currentMode)
        var updated = settings
        updated.calibrationHzByMode[key] = settings.calibrationHz(forMode: key) + sign * offsetHz
        settings = updated
        settings.save(to: defaults)
        handle?.setTuningMode(tuningMode: settings.ffiTuningMode)
        let newCal = Int(updated.calibrationHzByMode[key] ?? 0)
        return "Moved the signal \(Int(offsetHz)) Hz onto the VFO. \(key) calibration is now \(newCal) Hz."
    }

    /// Clear the calibration for the current mode.
    func resetCalibration() {
        var updated = settings
        updated.calibrationHzByMode[SDRInputSettings.modeKey(currentMode)] = nil
        settings = updated
        settings.save(to: defaults)
        handle?.setTuningMode(tuningMode: settings.ffiTuningMode)
    }

    // MARK: Private

    /// CAT snapshot with value equality, for change detection.
    private struct Tuning: Equatable {
        let vfoHz: Double
        let mode: String
        let ritHz: Double
        let ritEnabled: Bool
        let transmitting: Bool

        var ffi: FfiRigTuning {
            FfiRigTuning(
                vfoHz: vfoHz,
                mode: mode,
                ritHz: ritHz,
                ritEnabled: ritEnabled,
                transmitting: transmitting
            )
        }
    }

    private let store: WaterfallStore
    private let defaults: UserDefaults
    private var handle: PanadapterHandle?
    private var lastTuning: Tuning?
    /// Incremented per start so callbacks from a stopped pipeline are ignored.
    private var generation = 0

    private func restart() {
        stopPipeline()
        guard settings.enabled else {
            store.setExclusiveSource(nil)
            status = .off
            return
        }
        generation += 1
        let expected = generation
        let listener = PanadapterEventListener { [weak self] event in
            Task { @MainActor [weak self] in
                self?.process(event, generation: expected)
            }
        }
        store.setExclusiveSource(.sdr)
        status = .waitingForRig
        let sourceName = settings.sourceKind.rawValue
        logger.info("Starting SDR panadapter (\(sourceName))")
        let started = PanadapterHandle.start(
            device: settings.ffiDevice,
            tuningMode: settings.ffiTuningMode,
            display: settings.ffiDisplay,
            listener: listener
        )
        handle = started
        if let lastTuning {
            started.setTuning(tuning: lastTuning.ffi)
        }
    }

    private func stopPipeline() {
        generation += 1
        if let old = handle {
            // `stop` joins the worker thread; keep that off the main actor.
            Task.detached { old.stop() }
        }
        handle = nil
        isPausedForTransmit = false
        noiseFloorDB = nil
        store.setReceiving(false, source: .sdr)
        if store.source == .sdr {
            store.clear(producer: .sdr)
        }
    }

    private func process(_ event: PanadapterEvent, generation eventGeneration: Int) {
        guard eventGeneration == generation else {
            return
        }
        switch event {
        case let .line(values, centerHz, spanHz, floorDB):
            if status != .running {
                status = .running
                store.setReceiving(true, source: .sdr)
            }
            noiseFloorDB = floorDB
            store.append(line: values, centerMHz: centerHz / 1_000_000, spanKHz: spanHz / 1_000, source: .sdr)
        case let .error(message):
            logger.error("SDR panadapter error: \(message)")
            status = .failed(message)
        case .stopped:
            handle = nil
            store.setReceiving(false, source: .sdr)
            if case .failed = status {
                return
            }
            status = .off
        }
    }
}

// MARK: - PanadapterEvent

/// Sendable copy of a listener callback, for hopping to the main actor.
enum PanadapterEvent: Sendable {
    case line(values: [Float], centerHz: Double, spanHz: Double, noiseFloorDB: Float)
    case error(String)
    case stopped
}

// MARK: - PanadapterEventListener

/// Receives callbacks on the Rust worker thread and forwards them.
final class PanadapterEventListener: PanadapterListener {
    // MARK: Lifecycle

    init(deliver: @escaping @Sendable (PanadapterEvent) -> Void) {
        self.deliver = deliver
    }

    // MARK: Internal

    func onLine(line: FfiSpectrumLine) {
        deliver(.line(
            values: line.values,
            centerHz: line.centerHz,
            spanHz: line.spanHz,
            noiseFloorDB: line.noiseFloorDb
        ))
    }

    func onError(message: String) {
        deliver(.error(message))
    }

    func onStopped() {
        deliver(.stopped)
    }

    // MARK: Private

    private let deliver: @Sendable (PanadapterEvent) -> Void
}
