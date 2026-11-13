import CarrierWaveData
import UIKit

// MARK: - RadioLink bridge events + session

/// CWBP event handling, radio detection, and the CAT session for a
/// `RadioLink` — split from the class body for the 300-line type limit.
extension RadioLink {
    // MARK: - Bridge events

    func startBridgeEventMonitoring(bridge: BridgeProtocol) {
        bridgeEventTask?.cancel()
        bridgeEventTask = Task {
            for await event in bridge.bridgeEvents {
                guard !Task.isCancelled else {
                    break
                }
                self.handleBridgeEvent(event, bridge: bridge)
            }
        }
    }

    private func handleBridgeEvent(_ event: BridgeEvent, bridge: BridgeProtocol) {
        switch event {
        case let .handshakeComplete(fwVersion, _):
            bridgeFirmwareVersion = fwVersion
            RadioService.shared.addLog(.info, "\(label) bridge handshake OK (fw \(fwVersion))")
            startBridgeStatusPolling(bridge: bridge)
        case .usbConnected:
            bridgeUSBConnected = true
        case .usbDisconnected:
            bridgeUSBConnected = false
            detectedRadio = nil
        case let .radioDetected(protoType, _, rawID):
            handleRadioDetected(protoType: protoType, rawID: rawID, bridge: bridge)
        case .detectionFailed:
            detectedRadio = nil
        case let .bridgeError(message):
            lastError = "\(label): \(message)"
        case let .setVerifyResult(result):
            if result == .fail {
                lastError = "\(label): set-verify failed"
            }
        case .detecting,
             .ready,
             .cwAck,
             .cwProgress,
             .cwSpeedChanged,
             .cwStatus,
             .satAck, // satellite executor traffic is consumed by RadioService+Bridge
             .satStatus:
            break
        }
    }

    private func handleRadioDetected(
        protoType: BridgeFrame.RadioProtocolType,
        rawID: String,
        bridge: BridgeProtocol
    ) {
        guard let result = RigProtocolDetector.detect(bridgeID: rawID, protocolType: protoType) else {
            return
        }
        detectedRadio = result.radioName
        bridgeUSBConnected = true
        RadioService.shared.addLog(.info, "\(label) bridge: radio detected — \(result.radioName) (\(rawID))")
        let isYaesu = rawID.count == 6
            && rawID.hasPrefix("ID")
            && rawID.dropFirst(2).allSatisfy(\.isNumber)
        let needsRestart = rigProtocol != result.rigProtocol || radioIsYaesu != isYaesu
        rigProtocol = result.rigProtocol
        radioIsYaesu = isYaesu
        if needsRestart {
            startSession(bridge: bridge, frameType: result.frameType)
        }
        if isYaesu {
            Task { await session?.setSlowPolling(true) }
        }
    }

    private func startBridgeStatusPolling(bridge: BridgeProtocol) {
        statusPollTask?.cancel()
        statusPollTask = Task { [weak self] in
            try? await bridge.requestStatus()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled, self != nil else {
                    break
                }
                try? await bridge.requestStatus()
            }
        }
    }

    // MARK: - Session

    func startSession(bridge: BridgeProtocol, frameType: FrameAssembler.FrameType) {
        stopPolling()
        sessionTask?.cancel()
        let handler: any RadioProtocolHandler = rigProtocol == .kenwood
            ? KenwoodProtocolHandler(isYaesu: radioIsYaesu)
            : CIVProtocolHandler(civAddress: 0xA4)
        let newSession = RadioSession(transport: bridge, protocolHandler: handler, frameType: frameType)
        session = newSession
        sessionTask = Task {
            try? await newSession.start()
            self.startPolling()
        }
    }

    private func startPolling() {
        stopPolling()
        pollTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled, let session = self.session else {
                    break
                }
                let state = await session.state
                if state.frequency > 0 {
                    self.frequencyMHz = state.frequency
                }
                if !state.mode.isEmpty {
                    self.mode = state.mode
                }
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }
}
