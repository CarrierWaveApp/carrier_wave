//
//  FT8AudioEngine+RouteChange.swift
//  CarrierWave
//

import AVFoundation
import OSLog

// MARK: - FT8AudioEngine + Route Change Handling

extension FT8AudioEngine {
    func observeRouteChanges() {
        routeChangeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            guard let userInfo = notification.userInfo,
                  let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt
            else {
                return
            }
            Task { await self?.handleRouteChange(reasonValue: reasonValue) }
        }
    }

    func handleRouteChange(reasonValue: UInt) {
        guard let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }

        // Only act on changes that swap the input device — ignore category
        // changes, override changes, etc.
        switch reason {
        case .newDeviceAvailable,
             .oldDeviceUnavailable,
             .routeConfigurationChange:
            break
        default:
            return
        }

        guard isRunning, let callback = onSlotReady else {
            Self.routeLog.info("Route changed (reason=\(reasonValue)) — engine not running, ignoring")
            return
        }

        let session = AVAudioSession.sharedInstance()
        let inputName = session.currentRoute.inputs.first?.portName ?? "<unknown>"
        Self.routeLog.info(
            "Route changed (reason=\(reasonValue)) — re-tapping input \(inputName) at \(session.sampleRate) Hz"
        )

        // Clear level-metering state — bandpass delay lines and the overload
        // tracker both carry samples from the previous device. Without this,
        // a hot line-in dongle's residue keeps the "audio clipping" banner
        // latched after the user swaps to the built-in mic. See expert
        // diagnosis in docs/bugs (FT8 stuck-clipping investigation).
        resetLevelMetering()
        onRouteChange?()

        // The input node's format may have changed. Re-install the tap so
        // decimation uses the new device's sample rate. installTap throws an
        // NSException if a stale tap is still attached.
        do {
            engine.inputNode.removeTap(onBus: 0)
            try setupInputTap()
        } catch {
            Self.routeLog.error("Route change retap failed: \(error) — restarting engine")
            savedSlotCallback = callback
            stop()
            do {
                try configure()
                try start(onSlotReady: callback)
            } catch {
                Self.routeLog.error("Route change full restart failed: \(error)")
            }
        }
    }

    // MARK: Private

    private static let routeLog = Logger(
        subsystem: "com.jsvana.CarrierWave",
        category: "FT8AudioEngine.RouteChange"
    )
}
