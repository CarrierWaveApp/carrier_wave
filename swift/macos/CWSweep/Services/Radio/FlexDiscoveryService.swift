import Foundation
import Network
import OSLog

private let logger = Logger(subsystem: "com.jsvana.CWSweep", category: "FlexDiscovery")

// MARK: - DiscoveredFlexRadio

/// A Flex radio discovered on the local network via VITA-49 broadcast
struct DiscoveredFlexRadio: Identifiable, Hashable {
    let model: String
    let serial: String
    let version: String
    let nickname: String
    let callsign: String
    let ipAddress: String
    let port: UInt16

    /// Unique ID from serial number
    var id: String {
        serial
    }

    /// Display name combining model and nickname/serial
    var displayName: String {
        let label = nickname.isEmpty ? serial : nickname
        return "\(model) (\(label))"
    }
}

// MARK: - FlexDiscoveryService

/// Listens for FlexRadio VITA-49 discovery broadcasts on UDP port 4992.
/// Discovered radios are published as an observable list for the UI.
@MainActor
@Observable
final class FlexDiscoveryService {
    // MARK: Internal

    private(set) var discoveredRadios: [DiscoveredFlexRadio] = []
    private(set) var isListening = false

    func startListening() {
        guard !isListening else {
            return
        }
        isListening = true

        listenerTask = Task.detached { [weak self] in
            await self?.runListener()
        }
        logger.info("Flex discovery started")
    }

    func stopListening() {
        listenerTask?.cancel()
        listenerTask = nil
        listener?.cancel()
        listener = nil
        isListening = false
        logger.info("Flex discovery stopped")
    }

    /// Manually add a Flex radio by IP address (for radios outside broadcast domain)
    func addManualRadio(host: String, port: UInt16 = 4_992) {
        let radio = DiscoveredFlexRadio(
            model: "FlexRadio",
            serial: "manual-\(host)",
            version: "",
            nickname: host,
            callsign: "",
            ipAddress: host,
            port: port
        )
        if !discoveredRadios.contains(where: { $0.ipAddress == host }) {
            discoveredRadios.append(radio)
        }
    }

    // MARK: Private

    private var listener: NWListener?
    private var listenerTask: Task<Void, Never>?
    /// Timestamps of last discovery per serial, for expiry
    private var lastSeen: [String: Date] = [:]

    private func runListener() async {
        do {
            let params = NWParameters.udp
            params.allowLocalEndpointReuse = true
            let newListener = try NWListener(using: params, on: 4_992)

            await MainActor.run {
                self.listener = newListener
            }

            newListener.newConnectionHandler = { [weak self] conn in
                Task { self?.handleDiscoveryConnection(conn) }
            }

            newListener.start(queue: .global(qos: .utility))
            logger.info("UDP discovery listener started on port 4992")

            // Also try receiving VITA-49 broadcasts on port 4991
            await listenVITA49()
        } catch {
            logger.error("Failed to start discovery listener: \(error)")
        }
    }

    private func listenVITA49() async {
        do {
            let params = NWParameters.udp
            params.allowLocalEndpointReuse = true
            let vita49Listener = try NWListener(using: params, on: 4_991)

            vita49Listener.newConnectionHandler = { [weak self] conn in
                Task { self?.handleDiscoveryConnection(conn) }
            }

            vita49Listener.start(queue: .global(qos: .utility))
            logger.info("VITA-49 discovery listener started on port 4991")

            // Keep alive until cancelled
            while !Task.isCancelled {
                try await Task.sleep(for: .seconds(10))
                pruneStaleRadios()
            }
        } catch {
            logger.error("Failed to start VITA-49 listener: \(error)")
        }
    }

    nonisolated private func handleDiscoveryConnection(_ conn: NWConnection) {
        conn.start(queue: .global(qos: .utility))
        conn.receiveMessage { [weak self] content, _, _, _ in
            if let data = content {
                Task { @MainActor in
                    self?.processDiscoveryPacket(data)
                }
            }
            conn.cancel()
        }
    }

    private func processDiscoveryPacket(_ data: Data) {
        // Try parsing as VITA-49 discovery payload
        // The payload is a key=value string like:
        // "model=FLEX-6600 serial=1234-5678 version=3.4.0 name=My_Radio callsign=W1AW ip=192.168.1.100 port=4992"
        guard let payload = extractDiscoveryPayload(from: data) else {
            return
        }

        let kvPairs = parseKeyValuePairs(payload)

        guard let model = kvPairs["model"],
              let serial = kvPairs["serial"],
              let ip = kvPairs["ip"]
        else {
            logger.debug("Incomplete discovery packet: \(payload)")
            return
        }

        let version = kvPairs["version"] ?? ""
        // Underscores replace spaces in the discovery payload
        let nickname = (kvPairs["name"] ?? "").replacingOccurrences(of: "_", with: " ")
        let callsign = kvPairs["callsign"] ?? ""
        let port = UInt16(kvPairs["port"] ?? "4992") ?? 4_992

        let radio = DiscoveredFlexRadio(
            model: model,
            serial: serial,
            version: version,
            nickname: nickname,
            callsign: callsign,
            ipAddress: ip,
            port: port
        )

        lastSeen[serial] = Date()

        if let idx = discoveredRadios.firstIndex(where: { $0.serial == serial }) {
            discoveredRadios[idx] = radio
        } else {
            discoveredRadios.append(radio)
            logger.info("Discovered Flex radio: \(model) (\(serial)) at \(ip):\(port)")
        }
    }

    /// Extract the discovery payload string from a VITA-49 packet or raw text
    private func extractDiscoveryPayload(from data: Data) -> String? {
        // Try as plain text first (some Flex firmwares send plain discovery)
        if let text = String(data: data, encoding: .utf8),
           text.contains("model=")
        {
            return text
        }

        // VITA-49 packet: skip 28-byte header to get payload
        // Header: 4 bytes header, 4 bytes stream ID, 8 bytes class ID, 12 bytes timestamps
        guard data.count > 28 else {
            return nil
        }
        let payloadData = data.subdata(in: 28 ..< data.count)
        if let text = String(data: payloadData, encoding: .utf8),
           text.contains("model=")
        {
            return text
        }

        return nil
    }

    private func parseKeyValuePairs(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        let pairs = text.split(separator: " ")
        for pair in pairs {
            let kv = pair.split(separator: "=", maxSplits: 1)
            if kv.count == 2 {
                result[String(kv[0])] = String(kv[1])
            }
        }
        return result
    }

    /// Remove radios not seen in the last 30 seconds
    private func pruneStaleRadios() {
        let threshold = Date().addingTimeInterval(-30)
        let staleSerials = lastSeen.filter { $0.value < threshold }.map(\.key)
        for serial in staleSerials {
            lastSeen.removeValue(forKey: serial)
            discoveredRadios.removeAll { $0.serial == serial }
        }
    }
}
