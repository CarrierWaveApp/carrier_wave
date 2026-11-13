import CarrierWaveCore
import CarrierWaveData
import UIKit

// MARK: - CW Keyer Integration

extension LoggerView {
    /// Whether the persistent CW keyer row should be visible.
    /// Uses CAT-reported mode when available, falls back to session mode.
    /// All observable properties are read before boolean logic to ensure
    /// SwiftUI tracks them all — `&&` short-circuit would skip observations.
    var cwKeyerVisible: Bool {
        let service = RadioService.shared
        let hasCWKeyer = service.bridgeHasCWKeyer
        let usbConnected = service.bridgeUSBConnected
        let radioMode = service.radioMode
        let sessionMode = sessionManager?.activeSession?.mode
        let mode = radioMode ?? sessionMode ?? ""
        let isCW = mode == "CW" || mode == "CW-R"
        let hasSlots = !service.cwKeyer.programmedSlots.isEmpty
        // Hide the keyer row entirely if there's no radio attached to the
        // bridge — keying without a CAT link is a no-op and the firmware
        // will reject it anyway.
        return hasCWKeyer && usbConnected && isCW && hasSlots
    }

    func cwPlaySlot(_ slot: Int, context: [String: String]) {
        let service = RadioService.shared
        guard let bridge = service.bridgeProtocol else {
            service.addLog(.info, "CW play: no bridge")
            return
        }
        guard service.bridgeUSBConnected else {
            service.addLog(.error, "CW play: no USB radio connected — refusing to key")
            return
        }
        service.cwSendingSlot = slot
        if bridge.hasDirectWriter {
            bridge.playCWSlotImmediate(UInt8(slot), context: context)
            service.addLog(.info, "CW play: slot=\(slot) sent (immediate)")
        } else {
            service.addLog(.error, "CW play: slot=\(slot) no directWriter, falling back to async")
            Task {
                try? await bridge.playCWSlot(UInt8(slot), context: context)
            }
        }
    }

    func cwSendText(_ text: String) {
        let service = RadioService.shared
        guard let bridge = service.bridgeProtocol else {
            service.addLog(.info, "CW send text: no bridge")
            return
        }
        guard service.bridgeUSBConnected else {
            service.addLog(.error, "CW send: no USB radio connected — refusing to key")
            return
        }
        if bridge.hasDirectWriter {
            bridge.sendCWImmediate(text)
            service.addLog(.info, "CW send: \"\(text)\" (immediate)")
        } else {
            Task {
                try? await bridge.sendCW(text)
            }
        }
    }

    func cwStop() {
        let service = RadioService.shared
        guard let bridge = service.bridgeProtocol else {
            return
        }
        if bridge.hasDirectWriter {
            bridge.stopCWImmediate()
        } else {
            service.addLog(.error, "CW stop: no directWriter, falling back to async")
            Task {
                try? await bridge.stopCW()
            }
        }
    }

    func cwSetSpeed(_ wpm: UInt8) {
        guard let bridge = RadioService.shared.bridgeProtocol else {
            return
        }
        Task {
            try? await bridge.setCWSpeed(wpm: wpm)
        }
    }

    func cwBuildContext() -> [String: String] {
        RadioService.shared.cwKeyer.buildContext(
            from: CWKeyerContext(
                callsign: callsignInput,
                myCall: UserDefaults.standard.string(forKey: "loggerDefaultCallsign") ?? "",
                myName: UserDefaults.standard.string(forKey: "loggerDefaultName") ?? "",
                serial: RadioService.shared.cwSerialNumber,
                rstSent: "599",
                name: "",
                exchange: UserDefaults.standard.string(forKey: "contestExchange") ?? ""
            )
        )
    }
}
