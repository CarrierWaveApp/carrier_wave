import CarrierWaveData
import SwiftUI
import UIKit

// MARK: - CW Keyer Host View

extension KeyboardAccessoryBuilder {
    static func createKeyerHostView(callsignProvider: @escaping () -> String) -> UIView {
        let keyerRow = CWKeyerRow(
            keyerService: RadioService.shared.cwKeyer,
            onPlay: keyerOnPlay,
            onStop: keyerOnStop,
            onSendText: keyerOnSendText,
            onEdit: { _ in },
            onSpeedChange: keyerOnSpeedChange,
            context: { keyerContext(callsignProvider: callsignProvider) }
        )

        let host = UIHostingController(rootView: keyerRow)
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false
        host.view.heightAnchor.constraint(equalToConstant: 70).isActive = true
        return host.view
    }

    // MARK: Private

    private static func keyerOnPlay(slot: Int, context: [String: String]) {
        guard let bridge = RadioService.shared.bridgeProtocol else {
            return
        }
        guard RadioService.shared.bridgeUSBConnected else {
            RadioService.shared.addLog(.error, "CW play: no USB radio connected — refusing to key")
            return
        }
        RadioService.shared.cwSendingSlot = slot
        bridge.playCWSlotImmediate(UInt8(slot), context: context)
    }

    private static func keyerOnStop() {
        guard let bridge = RadioService.shared.bridgeProtocol else {
            return
        }
        bridge.stopCWImmediate()
    }

    private static func keyerOnSendText(_ text: String) {
        guard let bridge = RadioService.shared.bridgeProtocol else {
            return
        }
        guard RadioService.shared.bridgeUSBConnected else {
            RadioService.shared.addLog(.error, "CW send: no USB radio connected — refusing to key")
            return
        }
        let clamped = String(text.prefix(100))
        guard !clamped.isEmpty else {
            return
        }
        bridge.sendCWImmediate(clamped)
    }

    private static func keyerOnSpeedChange(_ wpm: UInt8) {
        guard let bridge = RadioService.shared.bridgeProtocol else {
            return
        }
        Task { try? await bridge.setCWSpeed(wpm: wpm) }
    }

    private static func keyerContext(callsignProvider: () -> String) -> [String: String] {
        RadioService.shared.cwKeyer.buildContext(
            from: CWKeyerContext(
                callsign: callsignProvider(),
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
