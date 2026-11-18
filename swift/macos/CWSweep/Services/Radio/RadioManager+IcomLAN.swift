import CarrierWaveData
import Foundation
import OSLog

private let logger = Logger(subsystem: "com.jsvana.CWSweep", category: "IcomLAN")

// MARK: - IcomLANError

enum IcomLANError: LocalizedError {
    case noRadioInfo

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case .noRadioInfo: "The radio logged in but didn't say which model it is."
        }
    }
}

// MARK: - RadioManager + Icom LAN

/// Discovery-driven Icom LAN/WiFi connect: log in first, read the model from
/// the radio's `0xA8` packet, then build the CI-V handler with the right
/// address. No model picker, and credentials are remembered in the Keychain.
extension RadioManager {
    /// True when a session is already talking to this host.
    func isConnectedToIcom(host: String) -> Bool {
        slotStates.values.contains { $0.profile.protocolType == .icomWiFi && $0.profile.networkHost == host }
    }

    /// Log in to the Icom radio at `host`, detect its model, and start a
    /// session. On success the model and credentials are remembered.
    @discardableResult
    func connectIcomLAN(host: String, credentials: IcomLANCredentials) async throws -> UUID {
        let transport = makeIcomWiFiTransport(
            host: host,
            username: credentials.username,
            password: credentials.password
        )
        do {
            try await transport.connect()
        } catch {
            logger.warning("Login to \(host, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
        guard let info = await transport.connectedRadioInfo else {
            await transport.disconnect()
            throw IcomLANError.noRadioInfo
        }
        let model = RadioModel.icomLAN(info)
        let civHex = String(format: "%02X", info.civAddress)
        let mac = info.macAddress ?? "none"
        logger.info(
            """
            Detected \(model.name, privacy: .public) (reported "\(info.name, privacy: .public)", \
            CI-V \(civHex, privacy: .public), MAC \(mac, privacy: .public)) at \(host, privacy: .public)
            """
        )
        commandLog.append(
            direction: .status,
            text: String(format: "Detected %@ (CI-V %02X) at %@", model.name, info.civAddress, host)
        )
        let profile = RadioProfile.fromIcomWiFi(
            model: model,
            host: host,
            username: credentials.username,
            password: credentials.password
        )
        let id = try await connect(
            profile: profile,
            prebuilt: (transport, CIVProtocolHandler(civAddress: info.civAddress))
        )
        IcomKnownRadios.remember(info, host: host)
        IcomKnownRadios.saveCredentials(credentials, host: host)
        return id
    }

    /// Disconnect only the session talking to this Icom host.
    func disconnectIcom(host: String) async {
        for (slot, state) in slotStates
            where state.profile.protocolType == .icomWiFi && state.profile.networkHost == host
        {
            if let id = slots[slot] {
                await disconnect(id: id)
            }
        }
    }

    /// Discovery callback: reconnect a radio we've logged into before, once
    /// per launch, if there's a free slot and it isn't already connected.
    ///
    /// After any remote session ends (ours on quit, or a crash) the IC-9700
    /// goes nearly silent on the network for ~50–90 s, answering only the
    /// odd packet. Each attempt re-sends pkt3 every second for 5 s, so
    /// retrying back-to-back for up to 3 minutes catches the first moment it
    /// answers instead of sleeping through it.
    func autoConnectKnownIcom(host: String) async {
        guard let credentials = IcomKnownRadios.credentials(for: host),
              !icomAutoConnectTried.contains(host)
        else {
            return
        }
        icomAutoConnectTried.insert(host)
        let deadline = Date().addingTimeInterval(180)
        var attempt = 0
        while Date() < deadline {
            guard !isConnectedToIcom(host: host), nextAvailableSlot() != nil else {
                return
            }
            attempt += 1
            logger.info("Auto-connecting known Icom radio at \(host, privacy: .public) (try \(attempt))")
            do {
                try await connectIcomLAN(host: host, credentials: credentials)
                return
            } catch let IcomWiFiError.authenticationFailed(stage) where stage.contains("rejected") {
                commandLog.append(direction: .status, text: "Auto-connect to \(host): saved login rejected")
                return
            } catch {
                if attempt == 1 {
                    commandLog.append(
                        direction: .status,
                        text: "\(host) isn't answering yet (radios pause for about a minute after a "
                            + "session ends); retrying for up to 3 minutes"
                    )
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
        commandLog.append(direction: .status, text: "Auto-connect to \(host) gave up after 3 minutes")
    }
}
