import Foundation

extension VimActionExecutor {
    func executeCommand(_ command: VimCommand) -> String? {
        // Sequential lookup instead of a long `??` chain: the chained form
        // trips the type checker's "unable to type-check in reasonable time"
        // limit on Xcode 26.3.
        let handlers: [(VimCommand) -> String?] = [
            executeRadioCommand,
            executeCWCommand,
            executeClusterCommand,
            executeActivationCommand,
            executeAlertCommand,
            executeRadioControlCommand,
            executeNavigationCommand,
            executeInfoCommand,
            executeMiscCommand,
        ]
        for handler in handlers {
            if let result = handler(command) {
                return result
            }
        }
        return nil
    }

    // MARK: Private

    private func executeRadioCommand(_ command: VimCommand) -> String? {
        switch command {
        case let .connect(node): "Connect: \(node)"
        case .disconnect: "Disconnected"
        case let .setWPM(wpm): executeSetWPM(wpm)
        case let .setPower(watts): "Power: \(watts)W"
        case let .park(ref): "Park: \(ref)"
        case let .summit(ref): "Summit: \(ref)"
        case let .splitUp(kHz): "Split: UP \(kHz)"
        case let .splitDown(kHz): "Split: DN \(kHz)"
        case .splitOff: "Split: OFF"
        case .exportADIF: "Export ADIF"
        case .importADIF: "Import ADIF"
        default: nil
        }
    }

    private func executeSetWPM(_ wpm: Int) -> String {
        let clamped = max(5, min(60, wpm))
        Task { await radioManager.setCWSpeed(clamped, fallback: winKeyer) }
        return "WPM: \(clamped)"
    }

    private func executeCWCommand(_ command: VimCommand) -> String? {
        switch command {
        case .cq:
            Task { await radioManager.sendCW("CQ CQ CQ", fallback: winKeyer) }
            return "CQ"
        case let .sendMemory(num): return "Send F\(num)"
        case let .sendText(text):
            Task { await radioManager.sendCW(text, fallback: winKeyer) }
            return "Sent: \(text)"
        case .agn:
            Task { await radioManager.sendCW("AGN", fallback: winKeyer) }
            return "AGN"
        case .tu:
            Task { await radioManager.sendCW("TU", fallback: winKeyer) }
            return "TU"
        default: return nil
        }
    }

    private func executeClusterCommand(_ command: VimCommand) -> String? {
        switch command {
        case .dx: "SH/DX"
        case .wwv: "SH/WWV"
        case .skimmer: "Skimmer toggle"
        case let .raw(text): "Raw: \(text)"
        default: nil
        }
    }

    private func executeActivationCommand(_ command: VimCommand) -> String? {
        switch command {
        case let .spot(comment): executeSpot(comment: comment)
        case .respot: executeSpot(comment: nil)
        case let .rove(ref): "Rove: \(ref)"
        case .endSession: "Session ended"
        case .upload: "Upload"
        default: nil
        }
    }

    private func executeSpot(comment: String?) -> String {
        Task { try? await spotService.postCurrentSpot(overrideComment: comment) }
        return "Spotting\u{2026}"
    }

    private func executeAlertCommand(_ command: VimCommand) -> String? {
        switch command {
        case let .alertAdd(spec): "Alert: +\(spec)"
        case .alertList: "Alerts"
        case .alertClear: "Alerts cleared"
        default: nil
        }
    }

    private func executeMiscCommand(_ command: VimCommand) -> String? {
        switch command {
        case .help: nil
        case .notes: "Notes"
        case let .unknown(text): "Unknown: \(text)"
        default: nil
        }
    }
}
