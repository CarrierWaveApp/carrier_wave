import CarrierWaveData
import UIKit

// MARK: - Bridge Protocol Integration

extension RadioService {
    /// Monitor bridge events and update RadioService state.
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

    /// Handle a single bridge event.
    func handleBridgeEvent(_ event: BridgeEvent, bridge: BridgeProtocol) {
        switch event {
        case let .handshakeComplete(fwVersion, capabilities):
            addLog(.info, "Bridge handshake OK (fw \(fwVersion))")
            bridgeFirmwareVersion = fwVersion
            bridgeIsFramed = true
            let caps = BridgeFrame.Capabilities(rawValue: capabilities)
            bridgeHasCWKeyer = caps.contains(.cwKeyer)
            bridgeHasSatDoppler = caps.contains(.satDoppler)
            let slotsCount = cwKeyer.programmedSlots.count
            let mode = radioMode ?? "nil"
            addLog(.info, "CW keyer: has=\(bridgeHasCWKeyer) slots=\(slotsCount) mode=\(mode)")
            if bridgeHasCWKeyer {
                syncCWSlotsTobridge(bridge: bridge)
            }
            startBridgeStatusPolling(bridge: bridge)
        case .usbConnected:
            addLog(.info, "Bridge: USB connected")
            bridgeUSBConnected = true
        case .usbDisconnected:
            addLog(.info, "Bridge: USB disconnected")
            bridgeUSBConnected = false
            bridgeDetectedRadio = nil
            bridgeDetecting = false
        case .detecting:
            addLog(.info, "Bridge: detecting radio...")
            bridgeDetecting = true
        case let .radioDetected(protoType, _, rawID):
            handleRadioDetected(protoType: protoType, rawID: rawID, bridge: bridge)
        case .detectionFailed:
            bridgeDetecting = false
            addLog(.info, "Bridge: radio detection failed")
        case .ready:
            addLog(.info, "Bridge: ready")
        case let .bridgeError(msg):
            addLog(.error, "Bridge error: \(msg)")
        case let .setVerifyResult(result):
            handleSetVerifyResult(result)
        case let .cwAck(result, bufferDepth):
            handleCWAck(result: result, bufferDepth: bufferDepth)
        case let .cwProgress(bufferDepth, flags):
            handleCWProgress(bufferDepth: bufferDepth, flags: flags)
        case let .cwSpeedChanged(wpm):
            addLog(.info, "Encoder WPM changed: \(wpm)")
            cwKeyer.wpm = Int(wpm)
        case let .cwStatus(wpm, bufferDepth, flags, slotCount):
            handleCWStatus(wpm: wpm, bufferDepth: bufferDepth, flags: flags, slotCount: slotCount)
        case .satAck,
             .satStatus:
            handleSatBridgeEvent(event)
        }
    }

    private func handleSatBridgeEvent(_ event: BridgeEvent) {
        switch event {
        case let .satAck(scheduleID, seq, result, stepsLoaded):
            addLog(.info, "Sat ack: id=\(scheduleID) seq=\(seq) \(result) loaded=\(stepsLoaded)")
        case let .satStatus(status):
            satBridgeStatus = status
            addLog(.info, "Sat status: \(status.state) step=\(status.stepIndex) t=\(status.tMs)ms")
        default:
            break
        }
    }

    private func handleRadioDetected(
        protoType: BridgeFrame.RadioProtocolType,
        rawID: String,
        bridge: BridgeProtocol
    ) {
        bridgeDetecting = false
        addLog(.info, "Bridge: radio detected — \(rawID) (proto=\(protoType))")
        guard let result = RigProtocolDetector.detect(bridgeID: rawID, protocolType: protoType) else {
            return
        }
        bridgeDetectedRadio = result.radioName
        addLog(.info, "Auto-configured: \(result.radioName) (\(result.rigProtocol))")

        // Yaesu radios report a 4-digit model ID (FT-891 = ID0650, FTX-1 =
        // ID0840); Kenwood/Elecraft report 3 digits (e.g. ID019). Match any
        // "ID" + 4 digits — mirror of `is_yaesu_id` in the firmware's detect.rs.
        // Yaesu speaks Kenwood-compatible CAT but needs (a) slow polling — fast
        // CAT clicks the DSP and floods BLE — and (b) a Yaesu mode-response
        // parse ("MD0<char>;" vs Kenwood "MD<digit>;").
        let isYaesu = rawID.count == 6
            && rawID.hasPrefix("ID")
            && rawID.dropFirst(2).allSatisfy(\.isNumber)

        // Rebuild the session when the protocol OR the Yaesu-ness changed, so
        // the handler is constructed with the right mode parser even when the
        // protocol family (Kenwood) stays the same.
        let needsRestart = rigProtocol != result.rigProtocol || radioIsYaesu != isYaesu
        rigProtocol = result.rigProtocol
        radioIsYaesu = isYaesu
        if needsRestart {
            restartSession(bridge: bridge, frameType: result.frameType)
        }

        if isYaesu {
            Task {
                await session?.setSlowPolling(true)
            }
            addLog(.info, "Yaesu detected: slow polling enabled (500ms)")
        }
    }

    private func handleSetVerifyResult(_ result: BridgeFrame.SetResultCode) {
        switch result {
        case .okay:
            addLog(.info, "Set-verify: OK")
        case .fail:
            addLog(.error, "Set-verify: FAILED")
        case .unsupported:
            addLog(.info, "Set-verify: unsupported by radio")
        }
    }

    private func handleCWAck(result: BridgeFrame.CWAckResult, bufferDepth: UInt8) {
        switch result {
        case .okay,
             .queued:
            addLog(.info, "CW ack: \(result) (buf=\(bufferDepth))")
        case .fail,
             .unsupported,
             .badSlot,
             .emptySlot:
            addLog(.error, "CW ack: \(result)")
            cwSendingSlot = nil
        }
    }

    private func handleCWProgress(bufferDepth: UInt8, flags: BridgeFrame.CWProgressFlags) {
        if flags.contains(.complete) {
            addLog(.info, "CW send complete")
            cwSendingSlot = nil
        } else {
            addLog(.info, "CW progress: buf=\(bufferDepth)")
        }
    }

    private func handleCWStatus(wpm: UInt8, bufferDepth: UInt8, flags: BridgeFrame.CWProgressFlags, slotCount: UInt8) {
        addLog(.info, "CW status: \(wpm) WPM, buf=\(bufferDepth), slots=\(slotCount)")
        cwKeyer.wpm = Int(wpm)
        if !flags.contains(.txActive) {
            cwSendingSlot = nil
        }
    }

    /// Start a session using the current protocol settings.
    /// Used as immediate fallback before detection results arrive.
    func startSessionWithFallback(bridge: BridgeProtocol) {
        // Cancel existing polling/session tasks — but don't call session.stop()
        // which would disconnect the shared BLE transport.
        stopStatePolling()
        sessionTask?.cancel()

        let frameType: FrameAssembler.FrameType = rigProtocol == .kenwood ? .kenwood : .civ
        let handler: any RadioProtocolHandler = rigProtocol == .kenwood
            ? KenwoodProtocolHandler(isYaesu: radioIsYaesu)
            : CIVProtocolHandler(civAddress: configuredRigAddress)

        let newSession = RadioSession(
            transport: bridge,
            protocolHandler: handler,
            frameType: frameType
        )
        session = newSession

        sessionTask = Task {
            try? await newSession.start()
            self.startStatePolling()
        }
    }

    /// Restart the session with a new frame type after detection.
    /// Note: don't call session.stop() — it disconnects the shared BLE transport.
    /// Cancelling sessionTask is sufficient to stop the old session's tasks.
    func restartSession(
        bridge: BridgeProtocol,
        frameType: FrameAssembler.FrameType
    ) {
        stopStatePolling()
        sessionTask?.cancel()

        let handler: any RadioProtocolHandler = rigProtocol == .kenwood
            ? KenwoodProtocolHandler(isYaesu: radioIsYaesu)
            : CIVProtocolHandler(civAddress: configuredRigAddress)

        let newSession = RadioSession(
            transport: bridge,
            protocolHandler: handler,
            frameType: frameType
        )
        session = newSession

        sessionTask = Task {
            try? await newSession.start()
            self.startStatePolling()
        }
    }

    /// Push all programmed CW slots and speed to the bridge.
    func syncCWSlotsTobridge(bridge: BridgeProtocol) {
        Task {
            try? await bridge.setCWSpeed(wpm: UInt8(cwKeyer.wpm))
            for slot in cwKeyer.programmedSlots {
                try? await bridge.setCWSlot(UInt8(slot.id), text: slot.text)
            }
            addLog(.info, "CW keyer synced (\(cwKeyer.programmedSlots.count) slots, \(cwKeyer.wpm) WPM)")
        }
    }

    /// Reset all bridge-related state.
    func resetBridgeState() {
        bridgeStatusPollTask?.cancel()
        bridgeStatusPollTask = nil
        bridgeFirmwareVersion = nil
        bridgeUSBConnected = false
        bridgeDetectedRadio = nil
        bridgeDetecting = false
        bridgeIsFramed = false
        bridgeHasCWKeyer = false
        bridgeHasSatDoppler = false
        satBridgeStatus = nil
        cwSendingSlot = nil
    }

    /// Begin a periodic interrogation of the bridge for current state. The
    /// firmware pushes one cached status frame at handshake time, but that
    /// can race the iOS event-stream wiring or be missed entirely on a
    /// silent BLE reconnect — polling closes that gap so the keyer row /
    /// USB indicator settle to the correct value within a few seconds.
    ///
    /// Cancels any prior poll task. Stops on cancel or transport reset.
    func startBridgeStatusPolling(bridge: BridgeProtocol) {
        bridgeStatusPollTask?.cancel()
        bridgeStatusPollTask = Task { [weak self] in
            // First interrogation: kick immediately so missed initial state
            // settles before the first 3 s tick.
            try? await bridge.requestStatus()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else {
                    break
                }
                guard let self, bridgeIsFramed else {
                    break
                }
                try? await bridge.requestStatus()
            }
        }
    }
}
