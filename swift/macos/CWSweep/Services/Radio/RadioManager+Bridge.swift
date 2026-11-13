import CarrierWaveData
import Foundation
import OSLog

private let bridgeLogger = Logger(subsystem: "com.jsvana.CWSweep", category: "Bridge")

// MARK: - Bridge Connection

extension RadioManager {
    /// Top-level bridge connect helper wired from `connect(profile:)`.
    /// Starts the bridge connect pipeline and kicks off state polling.
    func startBridgeConnection(profile: RadioProfile) async throws -> UUID {
        let id = try await connectBridge(profile: profile)
        Task { [weak self] in
            guard let self else {
                return
            }
            await pollActiveState()
        }
        return id
    }

    /// Connect to a CW Bridge over BLE.
    /// Runs the CWBP handshake, auto-detects the downstream radio, and
    /// hot-swaps the RadioSession with the detected protocol.
    @discardableResult
    func connectBridge(profile: RadioProfile) async throws -> UUID {
        guard let deviceUUID = profile.bridgeDeviceUUID else {
            throw BLETransportError.noTargetDevice
        }

        resetBridgeState()

        let bleTransport = BLERadioTransport()
        await bleTransport.setTarget(deviceUUID: deviceUUID)
        activeBridgeTransport = bleTransport

        let bridge = BridgeProtocol(transport: bleTransport)
        activeBridge = bridge

        let handler: any RadioProtocolHandler = CIVProtocolHandler(civAddress: 0xA4)
        let session = RadioSession(
            transport: bridge,
            protocolHandler: handler,
            frameType: .civ
        )
        await session.setSkipPolling(true)

        let sessionId = UUID()
        sessions[sessionId] = session
        activeBridgeSessionId = sessionId
        activeRadioId = sessionId

        let bridgePortPath = profile.bridgeDeviceName ?? "CW Bridge"
        connectedPortPath = bridgePortPath
        connectedRadioName = profile.name
        isConnected = false
        let assignedSlot = registerSlotState(sessionId: sessionId, profile: profile, portPath: bridgePortPath)
        if let slot = assignedSlot {
            slotStates[slot]?.bridge = BridgeSlotState(
                bridge: bridge,
                transport: bleTransport,
                sessionId: sessionId
            )
        }
        commandLog.append(direction: .status, text: "Connecting CW Bridge (\(profile.bridgeDeviceName ?? "?"))")

        bridgeStateTask?.cancel()
        bridgeStateTask = Task { [weak self] in
            await self?.observeBridgeBLE(
                transport: bleTransport,
                bridge: bridge,
                sessionId: sessionId,
                profile: profile
            )
        }

        return sessionId
    }

    /// Disconnect the active bridge, if any.
    func disconnectBridge() async {
        bridgeEventTask?.cancel()
        bridgeEventTask = nil
        bridgeStatusPollTask?.cancel()
        bridgeStatusPollTask = nil
        bridgeStateTask?.cancel()
        bridgeStateTask = nil

        if let bridge = activeBridge {
            await bridge.stop()
        }
        if let transport = activeBridgeTransport {
            await transport.disconnect()
        }

        if let id = activeBridgeSessionId {
            await disconnect(id: id)
        }

        resetBridgeState()
    }

    /// Request the bridge to re-scan for a connected radio.
    func requestBridgeRedetect() async {
        guard let bridge = activeBridge else {
            return
        }
        do {
            try await bridge.requestDetection()
            commandLog.append(direction: .tx, text: "Bridge: request detect")
        } catch {
            commandLog.append(direction: .status, text: "Bridge: detect request failed")
        }
    }

    /// Reset all bridge-related state fields.
    func resetBridgeState() {
        bridgeStatusPollTask?.cancel()
        bridgeStatusPollTask = nil
        bridgeFirmwareVersion = nil
        bridgeCapabilities = 0
        bridgeUSBConnected = false
        bridgeDetectedRadio = nil
        bridgeDetecting = false
        bridgeIsFramed = false
        bridgeHasCWKeyer = false
        bridgeCWSendingSlot = nil
        bridgeCWSpeed = 25
        bridgeCWFlags = []
        bridgeCWBufferDepth = 0
        activeBridge = nil
        activeBridgeTransport = nil
        activeBridgeSessionId = nil
        clearBridgeSlotStates()
    }
}

// MARK: - BLE / Bridge Event Monitoring

extension RadioManager {
    private func observeBridgeBLE(
        transport: BLERadioTransport,
        bridge: BridgeProtocol,
        sessionId: UUID,
        profile: RadioProfile
    ) async {
        let stateStream = await transport.stateStream()
        do {
            try await transport.connect()
        } catch {
            commandLog.append(
                direction: .status,
                text: "BLE connect failed: \(error.localizedDescription)"
            )
            return
        }

        for await state in stateStream {
            guard !Task.isCancelled else {
                break
            }
            switch state {
            case .connected:
                await handleBridgeBLEConnected(
                    bridge: bridge,
                    sessionId: sessionId,
                    profile: profile
                )
            case .disconnected:
                await handleBridgeBLEDisconnected()
            case let .error(message):
                commandLog.append(direction: .status, text: "Bridge: \(message)")
            default:
                break
            }
        }
    }

    private func handleBridgeBLEConnected(
        bridge: BridgeProtocol,
        sessionId: UUID,
        profile: RadioProfile
    ) async {
        isConnected = true
        commandLog.append(direction: .status, text: "BLE link up — starting handshake")

        await bridge.start()
        startBridgeEventMonitoring(
            bridge: bridge,
            sessionId: sessionId,
            profile: profile
        )

        if let session = sessions[sessionId] {
            do {
                try await session.start()
            } catch {
                bridgeLogger.error("Bridge session.start failed: \(error)")
            }
        }
    }

    private func handleBridgeBLEDisconnected() async {
        commandLog.append(direction: .status, text: "Bridge: BLE disconnected")
        isConnected = false
        bridgeIsFramed = false
        bridgeHasCWKeyer = false
        mirrorBridgeStateToSlot()
    }

    func startBridgeEventMonitoring(
        bridge: BridgeProtocol,
        sessionId: UUID,
        profile: RadioProfile
    ) {
        bridgeEventTask?.cancel()
        bridgeEventTask = Task { [weak self] in
            for await event in bridge.bridgeEvents {
                guard !Task.isCancelled else {
                    break
                }
                await self?.handleBridgeEvent(
                    event,
                    bridge: bridge,
                    sessionId: sessionId,
                    profile: profile
                )
            }
        }
    }

    private func handleBridgeEvent(
        _ event: BridgeEvent,
        bridge: BridgeProtocol,
        sessionId: UUID,
        profile: RadioProfile
    ) async {
        switch event {
        case let .handshakeComplete(fwVersion, capabilities):
            commandLog.append(direction: .status, text: "Bridge handshake OK (fw \(fwVersion))")
            bridgeFirmwareVersion = fwVersion
            bridgeCapabilities = capabilities
            bridgeIsFramed = true
            let caps = BridgeFrame.Capabilities(rawValue: capabilities)
            bridgeHasCWKeyer = caps.contains(.cwKeyer)
            startBridgeStatusPolling(bridge: bridge)
        case .usbConnected:
            commandLog.append(direction: .status, text: "Bridge: USB connected")
            bridgeUSBConnected = true
        case .usbDisconnected:
            commandLog.append(direction: .status, text: "Bridge: USB disconnected")
            bridgeUSBConnected = false
            bridgeDetectedRadio = nil
            bridgeDetecting = false
        case .detecting:
            commandLog.append(direction: .status, text: "Bridge: detecting radio...")
            bridgeDetecting = true
        case let .radioDetected(protoType, _, rawID):
            await handleRadioDetected(
                protoType: protoType,
                rawID: rawID,
                bridge: bridge,
                sessionId: sessionId,
                profile: profile
            )
        case .detectionFailed:
            bridgeDetecting = false
            commandLog.append(direction: .status, text: "Bridge: radio detection failed")
        case .ready:
            commandLog.append(direction: .status, text: "Bridge: ready")
        case let .bridgeError(message):
            commandLog.append(direction: .status, text: "Bridge error: \(message)")
        case let .setVerifyResult(result):
            commandLog.append(direction: .status, text: "Set-verify: \(result)")
        case let .cwAck(result, bufferDepth):
            handleBridgeCWAck(result: result, bufferDepth: bufferDepth)
        case let .cwProgress(bufferDepth, flags):
            handleBridgeCWProgress(bufferDepth: bufferDepth, flags: flags)
        case let .cwSpeedChanged(wpm):
            bridgeCWSpeed = wpm
            commandLog.append(direction: .rx, text: "CW speed: \(wpm) WPM")
        case let .cwStatus(wpm, bufferDepth, flags, slotCount):
            handleBridgeCWStatus(wpm: wpm, bufferDepth: bufferDepth, flags: flags, slotCount: slotCount)
        }
        mirrorBridgeStateToSlot()
    }

    private func handleBridgeCWStatus(
        wpm: UInt8,
        bufferDepth: UInt8,
        flags: BridgeFrame.CWProgressFlags,
        slotCount: UInt8
    ) {
        bridgeCWSpeed = wpm
        bridgeCWBufferDepth = bufferDepth
        bridgeCWFlags = flags
        let msg = "CW status: \(wpm) WPM, buf=\(bufferDepth), slots=\(slotCount)"
        commandLog.append(direction: .status, text: msg)
        if !flags.contains(.txActive) {
            bridgeCWSendingSlot = nil
        }
    }

    private func handleRadioDetected(
        protoType: BridgeFrame.BridgeRadioProtocolType,
        rawID: String,
        bridge: BridgeProtocol,
        sessionId: UUID,
        profile: RadioProfile
    ) async {
        bridgeDetecting = false
        let result = BridgeRigDetector.detect(rawID: rawID, protocolType: protoType)
        bridgeDetectedRadio = result.radioName
        connectedRadioName = result.radioName
        commandLog.append(
            direction: .status,
            text: "Bridge: detected \(result.radioName) (\(result.protocolType.rawValue))"
        )

        await restartSessionAfterDetection(
            bridge: bridge,
            sessionId: sessionId,
            detected: result
        )
    }

    private func restartSessionAfterDetection(
        bridge: BridgeProtocol,
        sessionId: UUID,
        detected: BridgeRigDetector.Result
    ) async {
        // Cancel — but DON'T stop — the old session before replacing it.
        // session.stop() would tear down the shared BLE transport, killing
        // the bridge link. cancelTasks() just stops its receive + poll
        // tasks so the new session is the sole consumer of
        // bridge.receivedData; otherwise both sessions race for chunks and
        // each gets truncated frames, making decodeFrequency return wildly
        // wrong values.
        if let oldSession = sessions[sessionId] {
            await oldSession.cancelTasks()
        }
        sessions.removeValue(forKey: sessionId)

        let handler: any RadioProtocolHandler = switch detected.protocolType {
        case .civ,
             .icomWiFi:
            CIVProtocolHandler(civAddress: detected.civAddress ?? 0xA4)
        case .kenwood:
            KenwoodProtocolHandler()
        case .elecraft:
            ElecraftProtocolHandler()
        case .yaesu:
            YaesuProtocolHandler()
        default:
            CIVProtocolHandler(civAddress: detected.civAddress ?? 0xA4)
        }

        let frameType: FrameAssembler.FrameType =
            detected.protocolType == .civ ? .civ : .kenwood

        let session = RadioSession(
            transport: bridge,
            protocolHandler: handler,
            frameType: frameType
        )

        // Yaesu radios need slow polling — fast CAT commands cause DSP clicks
        if detected.protocolType == .yaesu {
            await session.setSlowPolling(true)
        }

        sessions[sessionId] = session

        do {
            try await session.start()
            commandLog.append(
                direction: .status,
                text: "Bridge: session restarted (\(detected.protocolType.rawValue))"
            )
        } catch {
            bridgeLogger.error("Bridge session restart failed: \(error)")
        }
    }

    private func handleBridgeCWAck(
        result: BridgeFrame.CWAckResult,
        bufferDepth: UInt8
    ) {
        bridgeCWBufferDepth = bufferDepth
        switch result {
        case .okay,
             .queued:
            commandLog.append(direction: .status, text: "CW ack: \(result) (buf=\(bufferDepth))")
        case .fail,
             .unsupported,
             .badSlot,
             .emptySlot:
            commandLog.append(direction: .status, text: "CW ack: \(result)")
            bridgeCWSendingSlot = nil
        }
    }

    private func handleBridgeCWProgress(
        bufferDepth: UInt8,
        flags: BridgeFrame.CWProgressFlags
    ) {
        bridgeCWBufferDepth = bufferDepth
        bridgeCWFlags = flags
        if flags.contains(.complete) {
            commandLog.append(direction: .status, text: "CW send complete")
            bridgeCWSendingSlot = nil
        }
    }
}

// MARK: - CW Keyer Commands

extension RadioManager {
    /// Send a CW text string through the bridge keyer (framed mode required).
    func bridgeSendCW(_ text: String) async {
        guard let bridge = activeBridge else {
            return
        }
        do {
            try await bridge.sendCW(text)
            commandLog.append(direction: .tx, text: "CW send: \(text)")
        } catch {
            commandLog.append(direction: .status, text: "CW send failed: \(error.localizedDescription)")
        }
    }

    /// Stop any active CW transmission.
    func bridgeStopCW() async {
        guard let bridge = activeBridge else {
            return
        }
        try? await bridge.stopCW()
        bridgeCWSendingSlot = nil
        commandLog.append(direction: .tx, text: "CW stop")
    }

    /// Set the bridge keyer speed (WPM).
    func bridgeSetCWSpeed(_ wpm: UInt8) async {
        guard let bridge = activeBridge else {
            return
        }
        bridgeCWSpeed = wpm
        try? await bridge.setCWSpeed(wpm: wpm)
        commandLog.append(direction: .tx, text: "CW speed: \(wpm) WPM")
    }

    /// Store text in a CW memory slot (1-8) on the bridge.
    func bridgeSetCWSlot(_ slot: UInt8, text: String) async {
        guard let bridge = activeBridge else {
            return
        }
        try? await bridge.setCWSlot(slot, text: text)
    }

    /// Play a stored CW memory slot with optional template context.
    func bridgePlayCWSlot(_ slot: UInt8, context: [String: String] = [:]) async {
        guard let bridge = activeBridge else {
            return
        }
        bridgeCWSendingSlot = Int(slot)
        do {
            try await bridge.playCWSlot(slot, context: context)
            commandLog.append(direction: .tx, text: "CW slot \(slot) play")
        } catch {
            bridgeCWSendingSlot = nil
        }
    }

    /// Request CW engine status from the bridge.
    func bridgeRequestCWStatus() async {
        guard let bridge = activeBridge else {
            return
        }
        try? await bridge.requestCWStatus()
    }

    /// Whether the active radio connection is a CW Bridge with keyer capability.
    var isBridgeKeyerAvailable: Bool {
        activeBridge != nil && bridgeHasCWKeyer
    }

    /// Whether the bridge keyer is currently transmitting.
    var bridgeCWIsSending: Bool {
        bridgeCWFlags.contains(.txActive) || bridgeCWSendingSlot != nil
    }
}
