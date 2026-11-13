import CarrierWaveCore
import CarrierWaveData
import Foundation
import OSLog

private let logger = Logger(subsystem: "com.jsvana.CWSweep", category: "RadioManager+Transport")

// MARK: - RadioManager+Transport

/// Network transport factories. Lifted out of RadioManager.swift so that
/// file stays under SwiftLint's 500-line cap. Each method builds the
/// transport + protocol handler pair that `connect(profile:)` plugs into a
/// `RadioSession`.
extension RadioManager {
    func createIcomWiFiTransport(
        for profile: RadioProfile
    ) throws -> (any RadioTransport, any RadioProtocolHandler) {
        guard let host = profile.networkHost, !host.isEmpty,
              let username = profile.icomWiFiUsername,
              let password = profile.icomWiFiPassword
        else {
            throw IcomWiFiError.notConnected
        }
        logger.info("Connecting: \(profile.name) via WiFi (RS-BA1) \(host)")
        let log = commandLog
        let transport = IcomWiFiTransport(
            config: IcomWiFiConfig(ipAddress: host, username: username, password: password)
        ) { msg, _ in
            Task { @MainActor in
                log.append(direction: msg.hasPrefix("TX") ? .tx : .rx, text: msg)
            }
        }
        icomWaterfall.startConsuming(from: transport.scopeFrames)
        return (transport, CIVProtocolHandler(civAddress: profile.civAddress ?? 0xA4))
    }

    /// Ask an Icom LAN/WiFi radio to stream scope waveform data (`27 11 01`).
    /// The IC-9700 only honours this over LAN or an unlinked 115200 USB port,
    /// never over the REMOTE jack, so a tracker on REMOTE is unaffected. We
    /// deliberately do not touch satellite mode, Sub band, or DR the way
    /// Icom's own RS-BA1 client does.
    ///
    /// Reads `27 10` / `27 11` first so disconnect can put back exactly what
    /// was there (see `CIVScopeRestorePlan`).
    func enableIcomScopeIfNeeded(
        profile: RadioProfile,
        session: RadioSession,
        sessionId: UUID
    ) async {
        guard profile.protocolType == .icomWiFi else {
            return
        }
        let address = profile.civAddress ?? 0xA4
        let plan = await CIVScopeRestorePlan(
            scopeDisplayOn: readIcomScopeFlag(CIVScope.readScopeDisplay, address: address, session: session),
            waveformOutputOn: readIcomScopeFlag(CIVScope.readWaveformOutput, address: address, session: session)
        )
        commandLog.append(
            direction: .status,
            text: "Scope state on connect: 27 10 = \(Self.describe(plan.scopeDisplayOn)), "
                + "27 11 = \(Self.describe(plan.waveformOutputOn))"
        )
        let frames = { (payloads: [[UInt8]]) in
            payloads.map { Data(CIVProtocol.buildFrame(to: address, command: CIVScope.command, data: $0)) }
        }
        do {
            for payload in plan.connectCommands {
                try await session.sendRaw(frames([payload])[0])
                commandLog.append(direction: .tx, text: Self.describeScopeCommand(payload))
            }
            icomScopeSession = (
                id: sessionId,
                restorePayloads: plan.disconnectCommands,
                restoreFrames: frames(plan.disconnectCommands)
            )
        } catch {
            commandLog.append(direction: .status, text: "Scope waveform enable failed: \(error)")
        }
    }

    /// Put the scope back the way `enableIcomScopeIfNeeded` found it before
    /// the session closes, so the next client (or the radio's own display)
    /// doesn't inherit our state.
    func disableIcomScopeIfNeeded(session: RadioSession, sessionId: UUID) async {
        guard let scope = icomScopeSession, scope.id == sessionId else {
            return
        }
        icomScopeSession = nil
        for (payload, frame) in zip(scope.restorePayloads, scope.restoreFrames) {
            do {
                try await session.sendRaw(frame)
                commandLog.append(direction: .tx, text: Self.describeScopeCommand(payload) + " (restore)")
            } catch {
                commandLog.append(
                    direction: .status,
                    text: "Scope restore failed: \(Self.describeScopeCommand(payload)): \(error)"
                )
            }
        }
    }

    private func readIcomScopeFlag(
        _ query: [UInt8],
        address: UInt8,
        session: RadioSession
    ) async -> Bool? {
        guard let subcommand = query.first else {
            return nil
        }
        let frame = Data(CIVProtocol.buildFrame(to: address, command: CIVScope.command, data: query))
        let reply = await session.sendCIVQuery(frame) {
            CIVScope.parseOnOffReply($0, subcommand: subcommand, radio: address) != nil
        }
        return reply.flatMap { CIVScope.parseOnOffReply($0, subcommand: subcommand, radio: address) }
    }

    private static func describe(_ flag: Bool?) -> String {
        flag.map { $0 ? "on" : "off" } ?? "unknown"
    }

    /// Command-log text for a `27 xx` payload, e.g. "27 10 01 (scope display on)".
    static func describeScopeCommand(_ payload: [UInt8]) -> String {
        let hex = ([CIVScope.command] + payload).map { String(format: "%02X", $0) }.joined(separator: " ")
        let name: String = switch payload.first {
        case 0x10: "scope display"
        case 0x11: "scope waveform output"
        default: "scope"
        }
        let state = payload.count > 1 ? (payload[1] == 0 ? " off" : " on") : ""
        return "\(hex) (\(name)\(state))"
    }

    func createSCULAN10Transport(
        for profile: RadioProfile
    ) throws -> (any RadioTransport, any RadioProtocolHandler) {
        guard let host = profile.networkHost, !host.isEmpty,
              let username = profile.sculan10Username,
              let password = profile.sculan10Password
        else {
            throw SCULAN10Error.notConnected
        }
        logger.info("Connecting: \(profile.name) via SCU-LAN10 \(host):\(profile.networkPort)")
        let transport = SCULAN10Transport(
            host: host,
            controlPort: profile.networkPort,
            username: username,
            password: password,
            logCallback: commandLog.makeCallback(),
            statusCallback: { [weak self] status in
                Task { @MainActor [weak self] in
                    self?.appendConnectionLog(status)
                }
            }
        )
        sculan10Waterfall.startConsuming(from: transport.scopeData)
        radioAudioBroadcaster.setFormat(
            .pcmInt16Mono16k,
            sourceLabel: "SCU-LAN10",
            radioID: host
        )
        radioAudioBroadcaster.startConsuming(from: transport.audioData)
        attachLocalAudioPlayer()
        activeSCULAN10 = transport
        return (transport, YaesuProtocolHandler())
    }

    func createFlexTransport(
        for profile: RadioProfile
    ) throws -> (any RadioTransport, any RadioProtocolHandler) {
        guard let host = profile.networkHost, !host.isEmpty else {
            throw FlexTransportError.notConnected
        }
        logger.info("Connecting: \(profile.name) via TCP \(host):\(profile.networkPort)")
        let transport = FlexRadioTransport(
            host: host,
            port: profile.networkPort,
            logCallback: commandLog.makeStringCallback()
        )
        let handler = FlexProtocolHandler(sliceIndex: profile.flexSliceIndex)
        // Kick off the panadapter UDP listener; the panadapter create
        // command is sent once the radio session is running (see
        // registerFlexSubscriptions).
        flexPanadapter.start(radioHost: host) { [weak self] in
            let center = self?.frequency ?? 0
            let span = FlexPanadapterService.defaultBandwidthMHz * 1_000
            return (centerMHz: center, spanKHz: span)
        }
        return (transport, handler)
    }
}
