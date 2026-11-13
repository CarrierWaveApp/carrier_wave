import CarrierWaveData
import Combine
import Foundation
import Observation

// MARK: - PropagationAutoCQController

/// Drives the optional "Auto-CQ" path of a propagation check.
///
/// CW mode: timer-based loop that delegates to the existing CW Bridge keyer
/// via `RadioService.shared.bridgeProtocol?.sendCWImmediate(_:)`. Aborts on
/// radio disconnect.
///
/// FT8 mode: v1 surfaces guidance — the user starts FT8 CQ from the existing
/// FT8 panel and this check watches PSK Reporter in parallel. (Direct
/// hijacking of an in-flight FT8SessionManager is out of scope for v1; the
/// CQ trigger is owned by the FT8 view that has the model context and QSO
/// logger wired up.)
@MainActor
@Observable
final class PropagationAutoCQController {
    // MARK: Lifecycle

    init() {}

    // MARK: Internal

    enum FaultReason {
        case radioDisconnected
        case userStopped
    }

    private(set) var isRunning = false
    private(set) var lastFault: FaultReason?
    private(set) var lastTransmittedAt: Date?
    private(set) var transmissionsSent = 0

    /// Whether Auto-CQ for the given mode can be started right now.
    static func isAvailable(for mode: PropagationTransmitMode) -> Bool {
        switch mode {
        case .passive: false
        case .autoCW:
            // CW Bridge with an attached USB radio + CW keyer firmware.
            RadioService.shared.bridgeProtocol != nil
                && RadioService.shared.bridgeUSBConnected
                && RadioService.shared.bridgeHasCWKeyer
        case .autoFT8:
            // FT8 v1: guidance-only (no programmatic trigger from this controller).
            // Surface as "available" so the banner instructions appear, even if
            // we don't drive TX directly.
            true
        }
    }

    /// Reason text for the start sheet / live banner if Auto-CQ isn't usable.
    static func unavailableReason(for mode: PropagationTransmitMode) -> String? {
        switch mode {
        case .passive:
            nil
        case .autoCW:
            if RadioService.shared.bridgeProtocol == nil {
                "No CW Bridge connected. Connect your bridge and try again."
            } else if !RadioService.shared.bridgeUSBConnected {
                "Bridge is connected but no radio is plugged into the USB port."
            } else if !RadioService.shared.bridgeHasCWKeyer {
                "This bridge firmware doesn't support the CW keyer. Update firmware to enable Auto-CQ."
            } else {
                nil
            }
        case .autoFT8:
            nil
        }
    }

    /// Start Auto-CQ for the configured mode.
    /// - Parameters:
    ///   - mode: Transmit mode (only `.autoCW` is actively driven; `.autoFT8`
    ///     no-ops and lets the user trigger CQ from the FT8 view).
    ///   - callsign: Callsign to transmit in the CQ message.
    ///   - intervalSeconds: Seconds between CQ calls (default 30).
    ///   - onRadioFault: Invoked if the radio link drops mid-CQ — caller
    ///     should mark the artifact as `radio-fault`.
    func start(
        mode: PropagationTransmitMode,
        callsign: String,
        intervalSeconds: TimeInterval = 30,
        onRadioFault: @escaping @MainActor () -> Void
    ) {
        guard !isRunning else {
            return
        }
        isRunning = true
        lastFault = nil
        transmissionsSent = 0

        switch mode {
        case .passive:
            isRunning = false
        case .autoCW:
            startCWLoop(
                callsign: callsign,
                intervalSeconds: intervalSeconds,
                onRadioFault: onRadioFault
            )
        case .autoFT8:
            // Guidance-only path. Caller renders the banner; we don't pump TX.
            break
        }
    }

    /// Stop Auto-CQ. Cancels the timer and sends a CW stop frame if applicable.
    func stop() {
        cancellables.removeAll()
        if RadioService.shared.bridgeProtocol != nil {
            RadioService.shared.bridgeProtocol?.stopCWImmediate()
        }
        isRunning = false
        lastFault = .userStopped
    }

    // MARK: Private

    private var cancellables = Set<AnyCancellable>()

    private func startCWLoop(
        callsign: String,
        intervalSeconds: TimeInterval,
        onRadioFault: @escaping @MainActor () -> Void
    ) {
        let trimmed = callsign.uppercased()
        let message = "CQ CQ DE \(trimmed) \(trimmed) K"

        // Fire one immediately, then on a timer.
        sendCWFrame(message: message, onRadioFault: onRadioFault)

        Timer.publish(every: intervalSeconds, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else {
                    return
                }
                guard isRunning else {
                    return
                }
                sendCWFrame(message: message, onRadioFault: onRadioFault)
            }
            .store(in: &cancellables)
    }

    private func sendCWFrame(
        message: String,
        onRadioFault: @escaping @MainActor () -> Void
    ) {
        guard let bridge = RadioService.shared.bridgeProtocol,
              RadioService.shared.bridgeUSBConnected
        else {
            isRunning = false
            cancellables.removeAll()
            lastFault = .radioDisconnected
            RadioService.shared.addLog(.error, "Auto-CQ: radio link lost; aborting")
            onRadioFault()
            return
        }
        bridge.sendCWImmediate(message)
        lastTransmittedAt = Date()
        transmissionsSent += 1
    }
}
