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
    /// Retries for ~3 minutes: after Sweep dies without logging out, the
    /// radio keeps that session and ignores logins for a minute or two.
    func autoConnectKnownIcom(host: String) async {
        guard let credentials = IcomKnownRadios.credentials(for: host),
              !icomAutoConnectTried.contains(host)
        else {
            return
        }
        icomAutoConnectTried.insert(host)
        for (attempt, delay) in [0, 5, 10, 20, 30, 30, 30, 30, 30].enumerated() {
            try? await Task.sleep(for: .seconds(delay))
            guard !isConnectedToIcom(host: host), nextAvailableSlot() != nil else {
                return
            }
            logger.info("Auto-connecting known Icom radio at \(host, privacy: .public) (try \(attempt + 1))")
            do {
                try await connectIcomLAN(host: host, credentials: credentials)
                return
            } catch let IcomWiFiError.authenticationFailed(stage) where stage.contains("rejected") {
                commandLog.append(direction: .status, text: "Auto-connect to \(host): saved login rejected")
                return
            } catch {
                commandLog.append(
                    direction: .status,
                    text: "Auto-connect to \(host) failed (try \(attempt + 1)): \(error.localizedDescription)"
                )
            }
        }
    }
}
