import CarrierWaveData
import Foundation

// MARK: - SCU-LAN10 Configuration + Connection

extension RadioService {
    /// SCU-LAN10 host (persisted)
    var sculan10IPAddress: String? {
        get { UserDefaults.standard.string(forKey: Keys.sculan10IPAddress) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.sculan10IPAddress) }
    }

    /// SCU-LAN10 control port (persisted, default 50000)
    var sculan10Port: UInt16 {
        get {
            let stored = UserDefaults.standard.integer(forKey: Keys.sculan10Port)
            return stored > 0 ? UInt16(stored) : 50_000
        }
        set { UserDefaults.standard.set(Int(newValue), forKey: Keys.sculan10Port) }
    }

    /// Connect to a Yaesu SCU-LAN10 over the LAN (4 UDP ports, Yaesu CAT).
    func connectSCULAN10() {
        guard let host = sculan10IPAddress, !host.isEmpty else {
            return
        }

        // The SCU-LAN10 allows one client — drop any stale session first.
        if session != nil || connectionStatus == .connected {
            addLog(.info, "Disconnecting previous session before reconnect")
            disconnect()
        }

        let newSession = buildSCULAN10Session(host: host)
        session = newSession
        connectionStatus = .connecting("SCU-LAN10")

        sessionTask?.cancel()
        sessionTask = Task {
            do {
                try await newSession.start()
                self.addLog(.info, "Connected to SCU-LAN10")
                self.connectionStatus = .connected
                self.startStatePolling()
            } catch {
                self.addLog(.error, error.localizedDescription)
                self.connectionStatus = .error(error.localizedDescription)
            }
        }
    }

    /// Disconnect SCU-LAN10 transport
    func disconnectSCULAN10() {
        disconnect()
    }

    /// Save SCU-LAN10 configuration (host/port in UserDefaults, credentials in Keychain)
    func saveSCULAN10Config(
        ip ipAddress: String,
        port: UInt16,
        username: String,
        password: String
    ) {
        sculan10IPAddress = ipAddress
        sculan10Port = port
        try? KeychainHelper.shared.save(username, for: Keys.sculan10KeychainUsername)
        try? KeychainHelper.shared.save(password, for: Keys.sculan10KeychainPassword)
    }

    private func buildSCULAN10Session(host: String) -> RadioSession {
        let username = (try? KeychainHelper.shared.readString(
            for: Keys.sculan10KeychainUsername
        )) ?? "defaultuser"
        let password = (try? KeychainHelper.shared.readString(
            for: Keys.sculan10KeychainPassword
        )) ?? "defaultuser"

        addLog(.info, "Connecting to SCU-LAN10 \(host):\(sculan10Port) (user: \(username))")

        let transport = SCULAN10Transport(
            host: host,
            controlPort: sculan10Port,
            username: username,
            password: password,
            logCallback: { direction, text in
                Task { @MainActor in
                    RadioService.shared.addLog(
                        direction == .tx ? .sent : .received,
                        text
                    )
                }
            },
            statusCallback: { msg in
                Task { @MainActor in
                    RadioService.shared.addLog(.info, msg)
                }
            }
        )
        return RadioSession(
            transport: transport,
            protocolHandler: YaesuProtocolHandler(),
            frameType: .kenwood
        )
    }
}
