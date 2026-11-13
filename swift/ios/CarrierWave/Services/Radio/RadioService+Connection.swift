import CarrierWaveData
import Foundation

// MARK: - BLE Connection

extension RadioService {
    /// Connect to BLE radio transport with CWBP bridge protocol.
    /// Idempotent — skips if already connected or in progress.
    func connectBLE() {
        guard let uuid = savedDeviceUUID else {
            return
        }
        // Don't tear down an active connection
        if stateTask != nil, connectionStatus == .connected || bridgeProtocol != nil {
            return
        }
        connectionStatus = .connecting("Starting")
        resetBridgeState()

        // Start state monitoring from BLE transport.
        // Each time BLE connects, create a fresh BridgeProtocol — its internal
        // AsyncStreams are single-use and cannot survive a reconnect cycle.
        stateTask?.cancel()
        stateTask = Task {
            await bleTransport.setTarget(deviceUUID: uuid)
            let stream = await bleTransport.stateStream()

            // Start BLE connect AFTER stream is listening to avoid race
            try? await bleTransport.connect()

            for await state in stream {
                self.connectionStatus = state
                if state == .connected {
                    // Tear down old bridge (streams are exhausted)
                    self.stopStatePolling()
                    self.sessionTask?.cancel()
                    self.bridgeEventTask?.cancel()
                    if let old = self.bridgeProtocol {
                        await old.stop()
                    }
                    self.resetBridgeState()

                    // Fresh bridge with new streams
                    let bridge = BridgeProtocol(transport: self.bleTransport)
                    self.bridgeProtocol = bridge
                    await bridge.start()
                    self.startBridgeEventMonitoring(bridge: bridge)
                    self.startSessionWithFallback(bridge: bridge)
                } else if case .disconnected = state {
                    self.stopStatePolling()
                    self.sessionTask?.cancel()
                    self.bridgeEventTask?.cancel()
                    if let old = self.bridgeProtocol {
                        await old.stop()
                    }
                    self.bridgeProtocol = nil
                    self.resetBridgeState()
                }
            }
        }
    }

    // Bridge event handling, session management, and state reset
    // are in RadioService+Bridge.swift

    /// Disconnect, recreate session, and reconnect if was connected
    func reconnectWithNewSession() {
        let wasConnected = isConnected
        if wasConnected {
            disconnect()
        }
        if wasConnected {
            connectToSavedDevice()
        }
    }

    /// Disconnect and recreate when transport type changes
    func disconnectAndRecreate() {
        let wasConnected = isConnected
        disconnect()
        if wasConnected {
            connectToSavedDevice()
        }
    }
}

// MARK: - WiFi Connection

extension RadioService {
    /// Connect via WiFi with stored credentials
    func connectWiFi() {
        guard let ipAddress = wifiIPAddress, !ipAddress.isEmpty else {
            return
        }

        // Tear down any existing connection before starting a new one.
        // The radio only allows one active session — a stale session blocks new connects.
        if session != nil || connectionStatus == .connected {
            addLog(.info, "Disconnecting previous session before reconnect")
            disconnect()
        }

        let newSession = buildWiFiSession(ipAddress: ipAddress)
        session = newSession
        connectionStatus = .connecting("WiFi")

        sessionTask?.cancel()
        sessionTask = Task {
            await newSession.setOnRawFrame { data in
                Task { @MainActor in
                    RadioService.shared.addLog(.received, "CI-V", data: data)
                }
            }
            do {
                try await newSession.start()
                self.addLog(.info, "Connected to radio")
                self.connectionStatus = .connected
                self.startStatePolling()
            } catch {
                self.addLog(.error, error.localizedDescription)
                self.connectionStatus = .error(error.localizedDescription)
            }
        }
    }

    private func buildWiFiSession(ipAddress: String) -> RadioSession {
        let username = (try? KeychainHelper.shared.readString(
            for: Keys.wifiKeychainUsername
        )) ?? ""
        let password = (try? KeychainHelper.shared.readString(
            for: Keys.wifiKeychainPassword
        )) ?? ""

        addLog(.info, "Connecting to \(ipAddress) (user: \(username))")

        let config = IcomWiFiConfig(
            ipAddress: ipAddress,
            username: username,
            password: password
        )
        let transport = IcomWiFiTransport(config: config) { msg, data in
            Task { @MainActor in
                RadioService.shared.addLog(
                    msg.hasPrefix("TX") ? .sent : .received,
                    msg,
                    data: data
                )
            }
        }
        return RadioSession(
            transport: transport,
            protocolHandler: CIVProtocolHandler(civAddress: configuredRigAddress),
            frameType: .civ
        )
    }

    /// Disconnect WiFi transport
    func disconnectWiFi() {
        disconnect()
    }

    /// Save WiFi configuration
    func saveWiFiConfig(ip ipAddress: String, username: String, password: String) {
        wifiIPAddress = ipAddress
        try? KeychainHelper.shared.save(username, for: Keys.wifiKeychainUsername)
        try? KeychainHelper.shared.save(password, for: Keys.wifiKeychainPassword)
    }
}

// MARK: - Flex Connection

extension RadioService {
    /// Connect to a FlexRadio via SmartSDR TCP API
    func connectFlex() {
        guard let ipAddress = flexIPAddress, !ipAddress.isEmpty else {
            return
        }

        let port = flexPort
        let slice = flexSliceIndex
        addLog(.info, "Connecting to Flex at \(ipAddress):\(port) slice \(slice)")

        let transport = FlexRadioTransport(
            host: ipAddress,
            port: port
        ) { direction, text in
            Task { @MainActor in
                RadioService.shared.addLog(
                    direction == "TX" ? .sent : .received,
                    text
                )
            }
        }

        let handler = FlexProtocolHandler(sliceIndex: slice)
        let newSession = RadioSession(
            transport: transport,
            protocolHandler: handler,
            frameType: .smartsdr
        )

        session = newSession
        connectionStatus = .connecting("Flex TCP")

        sessionTask?.cancel()
        sessionTask = Task {
            await newSession.setSkipPolling(true)
            do {
                try await newSession.start()

                // Send client identification and subscribe to status
                let setupCmd = handler.encodeClientSetup(programName: "CarrierWave")
                try await newSession.sendRaw(setupCmd)
                for subCmd in handler.encodeSubscriptions() {
                    try await newSession.sendRaw(subCmd)
                }

                self.addLog(.info, "Connected to Flex radio")
                self.connectionStatus = .connected
                self.startStatePolling()
            } catch {
                self.addLog(.error, error.localizedDescription)
                self.connectionStatus = .error(error.localizedDescription)
            }
        }
    }

    /// Save Flex radio configuration
    func saveFlexConfig(ip ipAddress: String, port: UInt16, sliceIndex: Int) {
        flexIPAddress = ipAddress
        flexPort = port
        flexSliceIndex = sliceIndex
    }
}

// MARK: - SmartLink Connection

extension RadioService {
    /// Login to SmartLink with email/password
    func smartLinkLogin(email: String, password: String) {
        isSmartLinkConnecting = true
        addLog(.info, "SmartLink logging in as \(email)")

        smartLinkTask?.cancel()
        smartLinkTask = Task {
            do {
                let tokens = try await smartLinkAuth.login(
                    email: email,
                    password: password
                )
                self.smartLinkEmail = email
                try? KeychainHelper.shared.save(
                    tokens.refreshToken,
                    for: Keys.smartLinkKeychainRefreshToken
                )
                self.addLog(.info, "SmartLink login successful")
                await self.smartLinkDiscover(idToken: tokens.idToken)
            } catch {
                self.addLog(.error, "SmartLink login: \(error.localizedDescription)")
                self.isSmartLinkConnecting = false
            }
        }
    }

    /// Discover radios using a stored refresh token
    func smartLinkRefreshAndDiscover() {
        guard let refreshToken = try? KeychainHelper.shared.readString(
            for: Keys.smartLinkKeychainRefreshToken
        ) else {
            return
        }
        isSmartLinkConnecting = true
        addLog(.info, "SmartLink refreshing token")

        smartLinkTask?.cancel()
        smartLinkTask = Task {
            do {
                let tokens = try await smartLinkAuth.refreshIdToken(
                    refreshToken: refreshToken
                )
                await self.smartLinkDiscover(idToken: tokens.idToken)
            } catch {
                self.addLog(.error, "SmartLink refresh: \(error.localizedDescription)")
                self.isSmartLinkConnecting = false
            }
        }
    }

    /// Connect to SmartLink server and discover radios
    private func smartLinkDiscover(idToken: String) async {
        do {
            try await smartLinkClient.connect(
                appName: "CarrierWave",
                idToken: idToken,
                onRadioListUpdated: { [weak self] radios in
                    Task { @MainActor in
                        self?.smartLinkRadios = radios
                    }
                },
                onLogMessage: { [weak self] msg in
                    Task { @MainActor in
                        self?.addLog(.received, msg)
                    }
                }
            )
            isSmartLinkConnecting = false
            addLog(.info, "SmartLink connected, discovering radios")
        } catch {
            addLog(.error, "SmartLink: \(error.localizedDescription)")
            isSmartLinkConnecting = false
        }
    }

    /// Connect to a SmartLink-discovered radio
    func connectSmartLink(radio: SmartLinkRadio) {
        addLog(.info, "SmartLink connecting to \(radio.displayName)")
        connectionStatus = .connecting("SmartLink")

        sessionTask?.cancel()
        sessionTask = Task {
            do {
                let wanHandle = try await brokerSmartLinkConnection(radio: radio)
                try await startSmartLinkSession(radio: radio, wanHandle: wanHandle)
                self.addLog(.info, "Connected to Flex via SmartLink")
                self.connectionStatus = .connected
                self.startStatePolling()
            } catch {
                self.addLog(.error, "SmartLink: \(error.localizedDescription)")
                self.connectionStatus = .error(error.localizedDescription)
            }
        }
    }

    /// Refresh token, reconnect to SmartLink, and broker radio connection.
    private func brokerSmartLinkConnection(radio: SmartLinkRadio) async throws -> String {
        guard let refreshToken = try? KeychainHelper.shared.readString(
            for: Keys.smartLinkKeychainRefreshToken
        ) else {
            throw SmartLinkError.notConnected
        }

        addLog(.info, "Refreshing token for connect")
        let tokens = try await smartLinkAuth.refreshIdToken(refreshToken: refreshToken)

        // Always reconnect with fresh token — stale connections cause silent failures
        await smartLinkClient.disconnect()
        addLog(.info, "Reconnecting to SmartLink server")
        try await smartLinkClient.connect(
            appName: "CarrierWave",
            idToken: tokens.idToken,
            onLogMessage: { [weak self] msg in
                Task { @MainActor in self?.addLog(.received, msg) }
            }
        )

        addLog(.info, "Requesting connection to \(radio.serial)")
        let wanHandle = try await smartLinkClient.connectToRadio(serial: radio.serial)
        addLog(.info, "Got WAN handle: \(wanHandle)")
        return wanHandle
    }

    /// Connect to the radio via TLS and send wan validate + subscriptions.
    private func startSmartLinkSession(radio: SmartLinkRadio, wanHandle: String) async throws {
        let tlsPort = radio.bestTLSPort
        addLog(.info, "TLS connecting to \(radio.publicIP):\(tlsPort)")

        let transport = FlexRadioTransport(
            host: radio.publicIP,
            port: tlsPort,
            useTLS: true
        ) { direction, text in
            Task { @MainActor in
                RadioService.shared.addLog(direction == "TX" ? .sent : .received, text)
            }
        }

        let handler = FlexProtocolHandler(sliceIndex: flexSliceIndex)
        let newSession = RadioSession(
            transport: transport, protocolHandler: handler, frameType: .smartsdr
        )

        session = newSession
        await newSession.setSkipPolling(true)
        try await newSession.start()
        addLog(.info, "TLS connected to radio")

        // wan validate MUST be the first command
        try await newSession.sendRaw(handler.encodeWanValidate(handle: wanHandle))
        addLog(.info, "Sent wan validate")

        // Normal setup
        try await newSession.sendRaw(handler.encodeClientSetup(programName: "CarrierWave"))
        for subCmd in handler.encodeSubscriptions() {
            try await newSession.sendRaw(subCmd)
        }
    }

    /// Logout from SmartLink
    func smartLinkLogout() {
        smartLinkTask?.cancel()
        smartLinkTask = nil
        Task { await smartLinkClient.disconnect() }
        Task { await smartLinkAuth.logout() }
        try? KeychainHelper.shared.delete(for: Keys.smartLinkKeychainRefreshToken)
        smartLinkEmail = nil
        smartLinkRadios = []
        addLog(.info, "SmartLink logged out")
    }
}

// MARK: - State Polling

extension RadioService {
    func startStatePolling() {
        stopStatePolling()
        pollTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled else {
                    break
                }
                await pollRadioState()
            }
        }
    }

    func stopStatePolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    func pollRadioState() async {
        guard let session else {
            return
        }

        let state = await session.state

        // Detect transport disconnect (stream ended, keepalive timeout, etc.)
        if !state.isConnected, connectionStatus == .connected {
            addLog(.error, "Transport disconnected")
            connectionStatus = .disconnected
            stopStatePolling()
            return
        }

        let freq = state.frequency
        let mode = state.mode

        guard freq > 0 || !mode.isEmpty else {
            return
        }

        // Check feedback suppression
        let now = Date()

        if freq > 0 {
            let suppressFreq = shouldSuppressFrequency(freq, at: now)
            if !suppressFreq, radioFrequencyMHz != freq {
                radioFrequencyMHz = freq
                onRadioFrequencyChanged?(freq)
            }
        }

        if !mode.isEmpty {
            let suppressMode = shouldSuppressMode(mode, at: now)
            if !suppressMode, radioMode != mode {
                radioMode = mode
                onRadioModeChanged?(mode)
            }
        }
    }
}

// MARK: - Feedback Loop Prevention

extension RadioService {
    func shouldSuppressFrequency(_ freq: Double, at now: Date) -> Bool {
        guard let lastFreq = lastAppSetFrequency,
              let lastTime = lastAppSetTime,
              now.timeIntervalSince(lastTime) < feedbackSuppressionWindow
        else {
            return false
        }
        // Suppress if within 100 Hz of what we just set
        return abs(freq - lastFreq) < 0.0001
    }

    func shouldSuppressMode(_ mode: String, at now: Date) -> Bool {
        guard let lastMode = lastAppSetMode,
              let lastTime = lastAppSetTime,
              now.timeIntervalSince(lastTime) < feedbackSuppressionWindow
        else {
            return false
        }
        return mode == lastMode
    }
}
