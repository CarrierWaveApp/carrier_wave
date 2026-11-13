//
//  FT8AudioEngine+Interruption.swift
//  CarrierWave
//

import AVFoundation
import OSLog

// MARK: - FT8AudioEngine + Interruption Handling

extension FT8AudioEngine {
    func observeInterruptions() {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            // Extract Sendable values from notification before crossing actor boundary
            guard let userInfo = notification.userInfo,
                  let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt
            else {
                return
            }
            let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt
            Task { await self?.handleInterruption(type: typeValue, options: optionsValue) }
        }
    }

    func handleInterruption(type typeValue: UInt, options optionsValue: UInt?) {
        guard let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }

        switch type {
        case .began:
            Self.interruptionLog.info("Audio session interrupted — stopping engine")
            // Save callback before stop() clears it, so we can resume later
            savedSlotCallback = onSlotReady
            stop()

        case .ended:
            let shouldResume = optionsValue.map {
                AVAudioSession.InterruptionOptions(rawValue: $0).contains(.shouldResume)
            } ?? false

            if shouldResume, let callback = savedSlotCallback {
                Self.interruptionLog.info("Audio interruption ended — resuming")
                savedSlotCallback = nil
                do {
                    // Re-activate the audio session before restarting the engine.
                    // After an interruption (alarm, phone call), the session is
                    // deactivated and the input node format may have changed.
                    // Without this, installTapOnBus throws an unrecoverable
                    // NSException (SIGABRT) because the engine's audio graph
                    // is stale.
                    try configure()
                    try start(onSlotReady: callback)
                } catch {
                    Self.interruptionLog.error("Failed to restart after interruption: \(error)")
                }
            } else {
                savedSlotCallback = nil
            }

        @unknown default:
            break
        }
    }

    // MARK: Private

    private static let interruptionLog = Logger(
        subsystem: "com.jsvana.CarrierWave",
        category: "FT8AudioEngine.Interruption"
    )
}
