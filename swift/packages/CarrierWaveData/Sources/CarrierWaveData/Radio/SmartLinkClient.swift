import Foundation
import Network
import OSLog

private let logger = Logger(subsystem: "com.jsvana.CarrierWaveData", category: "SmartLink")

// MARK: - SmartLinkRadio

/// A Flex radio discovered via SmartLink WAN server.
public struct SmartLinkRadio: Identifiable, Sendable {
    public let id: String // serial number
    public let serial: String
    public let model: String
    public let nickname: String
    public let callsign: String
    public let publicIP: String
    public let status: String
    public let version: String
    public let publicTLSPort: UInt16
    public let publicUDPPort: UInt16
    public let publicUPnPTLSPort: UInt16
    public let publicUPnPUDPPort: UInt16

    /// Best TLS port to use (prefer manual forwarded, then UPnP)
    public var bestTLSPort: UInt16 {
        if publicTLSPort > 0 {
            return publicTLSPort
        }
        if publicUPnPTLSPort > 0 {
            return publicUPnPTLSPort
        }
        return 4_992
    }

    public var displayName: String {
        let name = nickname.replacingOccurrences(of: "_", with: " ")
        if name.isEmpty {
            return "\(model) (\(callsign))"
        }
        return "\(name) — \(model)"
    }
}

// MARK: - SmartLinkClient

/// TLS client for FlexRadio SmartLink WAN server.
/// Handles radio discovery and connection brokering.
public actor SmartLinkClient {
    // MARK: Lifecycle

    public init() {}

    // MARK: Public

    public private(set) var isConnected = false
    public private(set) var discoveredRadios: [SmartLinkRadio] = []
    public private(set) var publicIP: String = ""

    /// Connect to SmartLink server and discover registered radios.
    public func connect(
        appName: String,
        idToken: String,
        onRadioListUpdated: (@Sendable ([SmartLinkRadio]) -> Void)? = nil,
        onLogMessage: (@Sendable (String) -> Void)? = nil
    ) async throws {
        self.onRadioListUpdated = onRadioListUpdated
        self.onLogMessage = onLogMessage
        self.appName = appName

        let tlsOptions = NWProtocolTLS.Options()
        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.enableFastOpen = true

        let params = NWParameters(tls: tlsOptions, tcp: tcpOptions)
        params.preferNoProxies = true

        let conn = NWConnection(
            host: NWEndpoint.Host(Self.hostName),
            port: NWEndpoint.Port(rawValue: Self.hostPort)!,
            using: params
        )

        connection = conn

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            nonisolated(unsafe) var resumed = false
            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if !resumed {
                        resumed = true
                        cont.resume()
                    }
                case let .failed(error):
                    if !resumed {
                        resumed = true
                        cont.resume(throwing: error)
                    }
                case .cancelled:
                    if !resumed {
                        resumed = true
                        cont.resume(throwing: SmartLinkError.disconnected)
                    }
                default:
                    break
                }
            }
            conn.start(queue: .global(qos: .userInitiated))
        }

        isConnected = true
        logger.info("Connected to SmartLink server")

        // Send registration
        let registerCmd = "application register name=\(appName) platform=iOS token=\(idToken)\n"
        try await send(registerCmd)

        // Start reading responses and pinging
        startReceiving()
        startPinging()
    }

    /// Request connection to a specific radio.
    /// Returns the WAN handle needed for `wan validate` on the radio connection.
    public func connectToRadio(serial: String, holePunchPort: Int = 0) async throws -> String {
        let cmd = "application connect serial=\(serial) hole_punch_port=\(holePunchPort)\n"

        // Set up continuation before sending so we don't miss the response
        return try await withCheckedThrowingContinuation { cont in
            self.connectReadyContinuation = cont

            Task {
                try await self.send(cmd)
                self.logger_connectSent(serial)
            }
        }
    }

    /// Disconnect from SmartLink server.
    public func disconnect() {
        pingTimer?.cancel()
        pingTimer = nil
        connection?.cancel()
        connection = nil
        isConnected = false
        discoveredRadios = []
        connectReadyContinuation = nil
        logger.info("Disconnected from SmartLink server")
    }

    // MARK: Private

    private static let hostName = "smartlink.flexradio.com"
    private static let hostPort: UInt16 = 443

    private var connection: NWConnection?
    private var appName = "CarrierWave"
    private var pingTimer: DispatchSourceTimer?
    private var buffer = ""
    private var onRadioListUpdated: (@Sendable ([SmartLinkRadio]) -> Void)?
    private var onLogMessage: (@Sendable (String) -> Void)?
    private var connectReadyContinuation: CheckedContinuation<String, Error>?

    private func logger_connectSent(_ serial: String) {
        logger.info("Sent connect request for \(serial)")
        onLogMessage?("Sent connect request for \(serial)")

        // Start a timeout task — cancel the continuation if no response
        Task {
            try await Task.sleep(for: .seconds(15))
            if let cont = connectReadyContinuation {
                connectReadyContinuation = nil
                cont.resume(throwing: SmartLinkError.connectionFailed("connect_ready timeout (15s)"))
            }
        }
    }

    private func send(_ text: String) async throws {
        guard let connection else {
            throw SmartLinkError.notConnected
        }
        let data = Data(text.utf8)
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error {
                    cont.resume(throwing: error)
                } else {
                    cont.resume()
                }
            })
        }
    }

    private func startReceiving() {
        guard let connection else {
            return
        }
        connection.receive(
            minimumIncompleteLength: 1,
            maximumLength: 16_384
        ) { [weak self] content, _, isComplete, error in
            Task {
                if let data = content, !data.isEmpty {
                    await self?.handleReceived(data)
                }
                if isComplete || error != nil {
                    await self?.handleDisconnect()
                } else {
                    await self?.startReceiving()
                }
            }
        }
    }

    private func handleReceived(_ data: Data) {
        guard let text = String(data: data, encoding: .utf8) else {
            return
        }
        buffer += text

        // Process complete lines
        while let newlineRange = buffer.range(of: "\n") {
            let line = String(buffer[buffer.startIndex ..< newlineRange.lowerBound])
            buffer = String(buffer[newlineRange.upperBound...])
            if !line.isEmpty {
                processLine(line)
            }
        }
    }

    private func processLine(_ line: String) {
        logger.debug("WAN: \(line)")
        onLogMessage?("WAN: \(line)")

        if line.hasPrefix("radio list") {
            parseRadioList(line)
        } else if line.hasPrefix("radio connect_ready") {
            parseConnectReady(line)
        } else if line.hasPrefix("application info") {
            if let ip = extractValue(from: line, key: "public_ip") {
                publicIP = ip
            }
        }
    }

    private func parseRadioList(_ line: String) {
        // Format: "radio list <radio1_kvpairs>|<radio2_kvpairs>|..."
        let content = String(line.dropFirst("radio list ".count))
        guard !content.isEmpty else {
            discoveredRadios = []
            onRadioListUpdated?([])
            return
        }

        let radioStrings = content.split(separator: "|")
        var radios: [SmartLinkRadio] = []

        for radioStr in radioStrings {
            let kvString = String(radioStr)
            let serial = extractValue(from: kvString, key: "serial") ?? ""
            guard !serial.isEmpty else {
                continue
            }

            let radio = SmartLinkRadio(
                id: serial,
                serial: serial,
                model: extractValue(from: kvString, key: "model") ?? "Unknown",
                nickname: extractValue(from: kvString, key: "nickname") ?? "",
                callsign: extractValue(from: kvString, key: "callsign") ?? "",
                publicIP: extractValue(from: kvString, key: "ip") ?? "",
                status: extractValue(from: kvString, key: "status") ?? "",
                version: extractValue(from: kvString, key: "version") ?? "",
                publicTLSPort: UInt16(extractValue(from: kvString, key: "public_tls_port") ?? "") ?? 0,
                publicUDPPort: UInt16(extractValue(from: kvString, key: "public_udp_port") ?? "") ?? 0,
                publicUPnPTLSPort: UInt16(extractValue(from: kvString, key: "public_upnp_tls_port") ?? "") ?? 0,
                publicUPnPUDPPort: UInt16(extractValue(from: kvString, key: "public_upnp_udp_port") ?? "") ?? 0
            )
            radios.append(radio)
        }

        discoveredRadios = radios
        onRadioListUpdated?(radios)
        logger.info("Discovered \(radios.count) radio(s) via SmartLink")
    }

    private func parseConnectReady(_ line: String) {
        // Handle value can contain "|" (e.g. auth0|token), so don't split on pipe
        let handleKey = "handle="
        guard let range = line.range(of: handleKey) else {
            logger.error("connect_ready missing handle: \(line)")
            return
        }
        let handle = String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        guard !handle.isEmpty else {
            logger.error("connect_ready empty handle: \(line)")
            return
        }
        logger.info("Connect ready, handle=\(handle)")
        connectReadyContinuation?.resume(returning: handle)
        connectReadyContinuation = nil
    }

    private func handleDisconnect() {
        isConnected = false
        pingTimer?.cancel()
        pingTimer = nil
        connection = nil
        logger.info("SmartLink server disconnected")
    }

    private func startPinging() {
        let timer = DispatchSource.makeTimerSource(
            flags: .strict,
            queue: .global(qos: .utility)
        )
        timer.schedule(
            deadline: .now() + .seconds(5),
            repeating: .seconds(10),
            leeway: .milliseconds(100)
        )
        timer.setEventHandler { [weak self] in
            Task { [weak self] in
                try? await self?.send("ping from client\n")
            }
        }
        timer.resume()
        pingTimer = timer
    }

    private func extractValue(from line: String, key: String) -> String? {
        let pattern = "\(key)="
        guard let range = line.range(of: pattern) else {
            return nil
        }
        let valueStart = range.upperBound
        let remaining = line[valueStart...]
        let valueEnd = remaining.firstIndex(where: { $0 == " " || $0 == "|" }) ?? remaining.endIndex
        let value = String(remaining[valueStart ..< valueEnd])
        return value.isEmpty ? nil : value
    }
}

// MARK: - SmartLinkError

public enum SmartLinkError: LocalizedError {
    case notConnected
    case disconnected
    case connectionFailed(String)

    // MARK: Public

    public var errorDescription: String? {
        switch self {
        case .notConnected:
            "Not connected to SmartLink server"
        case .disconnected:
            "SmartLink server disconnected"
        case let .connectionFailed(reason):
            "SmartLink connection failed: \(reason)"
        }
    }
}
