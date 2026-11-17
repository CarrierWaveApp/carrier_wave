import CarrierWaveData
import Foundation
import OSLog

private let radioManagerLogger = Logger(subsystem: "com.jsvana.CWSweep", category: "RadioManager")

// MARK: - RadioManager+ConnectionSetup

extension RadioManager {
    func createTransportAndHandler(
        for profile: RadioProfile
    ) throws -> (any RadioTransport, any RadioProtocolHandler) {
        if profile.protocolType == .scuLan10 {
            return try createSCULAN10Transport(for: profile)
        }

        if profile.protocolType == .icomWiFi {
            return try createIcomWiFiTransport(for: profile)
        }

        if profile.protocolType == .flex {
            return try createFlexTransport(for: profile)
        }

        let proto = profile.protocolType.rawValue
        radioManagerLogger.info(
            "Connecting: \(profile.name) via \(profile.serialPortPath) (\(proto), \(profile.baudRate) baud)"
        )
        let transport = SerialRadioTransport(
            profile: profile,
            logCallback: commandLog.makeCallback()
        )
        let handler: any RadioProtocolHandler = switch profile.protocolType {
        case .civ:
            CIVProtocolHandler(civAddress: profile.civAddress ?? 0x94)
        case .kenwood:
            KenwoodProtocolHandler()
        case .elecraft:
            ElecraftProtocolHandler()
        case .yaesu:
            YaesuProtocolHandler()
        case .flex:
            FlexProtocolHandler()
        case .scuLan10:
            YaesuProtocolHandler()
        case .icomWiFi:
            CIVProtocolHandler(civAddress: profile.civAddress ?? 0xA4)
        case .cwBridge:
            fatalError("CW Bridge uses BLE transport, not serial — use startBridgeConnection()")
        }
        return (transport, handler)
    }

    func registerFlexSubscriptions(
        handler: any RadioProtocolHandler,
        session: RadioSession
    ) async throws {
        guard let flexHandler = handler as? FlexProtocolHandler else {
            return
        }
        let setupCmd = flexHandler.encodeClientSetupForSweep()
        try await session.sendRaw(setupCmd)
        for subCmd in flexHandler.encodeSubscriptions() {
            try await session.sendRaw(subCmd)
        }
        // Once the standard subscriptions are in flight, request the
        // panadapter stream. The service has already bound a UDP port; we
        // send `client udpport` and `display pan create` over the same TCP
        // session and start matching VITA-49 stream IDs to the assigned
        // handle as response lines come back.
        await flexPanadapter.attach(session: session, handler: flexHandler)
        radioManagerLogger.info("Flex subscriptions registered")
    }

    func updateConnectionState(id: UUID, profile: RadioProfile) {
        if activeRadioId == nil {
            activeRadioId = id
        }

        isConnected = true
        let portPath = profile.isNetworkRadio
            ? profile.networkHost ?? ""
            : profile.serialPortPath
        connectedPortPath = portPath
        connectedRadioName = profile.name
        // Bind this session to the next free slot. Bridge sessions register
        // their own slot in `connectBridge(...)` because the slot needs to
        // exist before the BLE handshake task starts mutating its bridge
        // state.
        if slotForSession(id) == nil {
            _ = registerSlotState(sessionId: id, profile: profile, portPath: portPath)
        }
        let connectTarget = profile.isNetworkRadio
            ? "\(profile.networkHost ?? ""):\(profile.networkPort)"
            : profile.serialPortPath
        commandLog.append(
            direction: .status,
            text: "Connected to \(profile.name) on \(connectTarget)"
        )
    }
}
