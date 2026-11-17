import Darwin
import Foundation
import Network
import OSLog

private let logger = Logger(subsystem: "com.jsvana.CarrierWaveData", category: "TrackerDiscovery")

extension TrackerDiscoveryService {
    /// One UDP broadcast probe: the query protocol and its send / reply ports.
    struct BroadcastProbe {
        let protocolKind: RotatorProtocolKind
        let port: UInt16
        let replyPort: UInt16
    }

    /// Classify one host. S.A.T. first (TCP 4533), then PSR-100 (HTTP 8080).
    nonisolated static func probeHost(_ host: String) async -> DiscoveredTracker? {
        if let sat = await probeHamlibRotator(host) {
            return sat
        }
        if let psr = await probePSR100Web(host) {
            return psr
        }
        return nil
    }

    nonisolated static func probeHamlibRotator(_ host: String) async -> DiscoveredTracker? {
        let transport = RotctlTCPTransport(host: host, port: 4_533)
        defer { Task { await transport.disconnect() } }
        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask { try await transport.connect() }
                group.addTask {
                    try await Task.sleep(for: .milliseconds(900))
                    throw RotatorTransportError.timeout
                }
                try await group.next()
                group.cancelAll()
            }
            let query = RotatorProtocolCodec.positionQueries(protocolKind: .hamlibRotctl)[0]
            let reply = try await transport.send(query, expectReply: true, timeout: .milliseconds(900)) ?? ""
            guard RotatorProtocolCodec.parsePosition(reply) != nil || reply.uppercased().contains("RPRT") else {
                return nil
            }
        } catch {
            return nil
        }
        // Distinguish a real S.A.T. from a PC running rotctld by its web UI.
        let page = await fetchText(host: host, port: 80, timeout: .milliseconds(1_200)) ?? ""
        let upper = page.uppercased()
        let isSAT = upper.contains("S.A.T") || upper.contains("CSN")
        let kind: TrackerKind = isSAT ? .csnSAT : .hamlibRotctld
        let endpoint = TrackerEndpoint(kind: kind, host: host)
        return DiscoveredTracker(
            endpoint: endpoint,
            name: isSAT ? "CSN S.A.T." : "Hamlib rotctld",
            detail: isSAT ? "\(host) · rotctld 4533 · web UI" : "\(host) · rotctld 4533"
        )
    }

    nonisolated static func probePSR100Web(_ host: String) async -> DiscoveredTracker? {
        guard let page = await fetchText(host: host, port: 8_080, timeout: .milliseconds(1_200)) else {
            return nil
        }
        let upper = page.uppercased()
        guard upper.contains("PSR-100") || upper.contains("PSR100") else {
            return nil
        }
        let mk2 = upper.contains("MK2")
        let endpoint = TrackerEndpoint(kind: .psr100, host: host)
        return DiscoveredTracker(
            endpoint: endpoint,
            name: mk2 ? "PSR-100 Mk2" : "PSR-100",
            detail: "\(host) · web UI :8080 · HTTP control"
        )
    }

    /// Unicast `AZ EL` (EasyComm, 2390→2391) then `<PST>AZ?</PST>` (S.A.T.
    /// XML, 12000→12001) at one host — for a PSR-100 whose web UI is slow or
    /// off, and for rotors on other subnets that broadcasts can't reach.
    nonisolated static func probeUDPRotator(_ host: String) async -> DiscoveredTracker? {
        for protocolKind in [RotatorProtocolKind.easycommII, .csnSATxml] {
            let endpoint = TrackerEndpoint(kind: .psr100, host: host, protocolKind: protocolKind)
            let transport = UDPRotatorTransport(host: host, port: endpoint.port, replyPort: endpoint.replyPort)
            defer { Task { await transport.disconnect() } }
            guard await (try? transport.connect()) != nil else {
                continue
            }
            let query = RotatorProtocolCodec.positionQueries(protocolKind: protocolKind)[0]
            guard let reply = try? await transport.send(query, expectReply: true, timeout: .milliseconds(900)),
                  let detected = RotatorProtocolCodec.detectProtocol(fromReply: reply),
                  RotatorProtocolCodec.parsePosition(reply) != nil
            else {
                continue
            }
            let resolved = TrackerEndpoint(
                kind: .psr100, host: host, protocolKind: detected, port: endpoint.port, replyPort: endpoint.replyPort
            )
            return DiscoveredTracker(
                endpoint: resolved,
                name: "PSR-100",
                detail: "\(host) · \(detected.displayName) · UDP \(endpoint.port)"
            )
        }
        return nil
    }

    /// Minimal HTTP/1.0 GET with a hard timeout; returns the response body +
    /// headers as text (enough to fingerprint a device page).
    nonisolated static func fetchText(host: String, port: UInt16, timeout: Duration) async -> String? {
        var request = URLRequest(url: URL(string: "http://\(host):\(port)/")!)
        request.timeoutInterval = Double(timeout.components.seconds)
            + Double(timeout.components.attoseconds) / 1e18
        request.httpMethod = "GET"
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        do {
            let (data, _) = try await session.data(for: request)
            let head = Array(data.prefix(64 * 1_024))
            return String(bytes: head, encoding: .utf8) ?? String(bytes: head, encoding: .isoLatin1)
        } catch {
            return nil
        }
    }

    /// Broadcast an EasyComm `AZ EL` query to 2390 and a S.A.T. XML `AZ?` to
    /// 12000 on every network, then read replies on 2391 / 12001 for ~1.5 s.
    nonisolated static func broadcastProbe(networks: [LocalNetwork]) async -> [DiscoveredTracker] {
        let probes = [
            BroadcastProbe(protocolKind: .easycommII, port: 2_390, replyPort: 2_391),
            BroadcastProbe(protocolKind: .csnSATxml, port: 12_000, replyPort: 12_001),
        ]
        var found: [DiscoveredTracker] = []
        for probe in probes {
            let (protocolKind, port, replyPort) = (probe.protocolKind, probe.port, probe.replyPort)
            let replies = await broadcast(
                RotatorProtocolCodec.positionQueries(protocolKind: protocolKind)[0],
                to: networks.map(\.broadcastAddress),
                port: port,
                replyPort: replyPort
            )
            for (sender, text) in replies {
                guard let detected = RotatorProtocolCodec.detectProtocol(fromReply: text),
                      RotatorProtocolCodec.parsePosition(text) != nil
                else {
                    continue
                }
                let endpoint = TrackerEndpoint(
                    kind: .psr100,
                    host: sender,
                    protocolKind: detected,
                    port: port,
                    replyPort: replyPort
                )
                found.append(DiscoveredTracker(
                    endpoint: endpoint,
                    name: "PSR-100",
                    detail: "\(sender) · \(detected.displayName) · UDP \(port)"
                ))
            }
        }
        return found
    }

    /// Send one datagram to each broadcast address from a socket bound to
    /// `replyPort`, collecting `(senderIP, text)` replies for 1.5 s.
    nonisolated static func broadcast(
        _ payload: Data,
        to addresses: [String],
        port: UInt16,
        replyPort: UInt16
    ) async -> [(String, String)] {
        let fd = socket(AF_INET, SOCK_DGRAM, 0)
        guard fd >= 0 else {
            return []
        }
        defer { close(fd) }
        configureBroadcastSocket(fd, replyPort: replyPort)
        for address in addresses {
            var dest = sockaddr_in()
            dest.sin_family = sa_family_t(AF_INET)
            dest.sin_port = port.bigEndian
            dest.sin_addr.s_addr = inet_addr(address)
            _ = payload.withUnsafeBytes { bytes in
                withUnsafePointer(to: &dest) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        sendto(fd, bytes.baseAddress, payload.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
            }
        }
        var replies: [(String, String)] = []
        let deadline = ContinuousClock.now + .milliseconds(1_500)
        var buffer = [UInt8](repeating: 0, count: 1_024)
        while ContinuousClock.now < deadline {
            var from = sockaddr_in()
            var fromLen = socklen_t(MemoryLayout<sockaddr_in>.size)
            let n = withUnsafeMutablePointer(to: &from) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    recvfrom(fd, &buffer, buffer.count, 0, $0, &fromLen)
                }
            }
            if n > 0 {
                let text = String(bytes: buffer[0 ..< Int(n)], encoding: .utf8) ?? ""
                let sender = LocalNetwork.dotted(UInt32(bigEndian: from.sin_addr.s_addr))
                replies.append((sender, text))
            } else {
                await Task.yield()
            }
        }
        return replies
    }

    /// Enable broadcast / address reuse, bind to `replyPort`, and set a short
    /// receive timeout so the read loop can poll.
    nonisolated private static func configureBroadcastSocket(_ fd: Int32, replyPort: UInt16) {
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &on, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &on, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(fd, SOL_SOCKET, SO_REUSEPORT, &on, socklen_t(MemoryLayout<Int32>.size))
        var local = sockaddr_in()
        local.sin_family = sa_family_t(AF_INET)
        local.sin_port = replyPort.bigEndian
        local.sin_addr.s_addr = INADDR_ANY
        let bound = withUnsafePointer(to: &local) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        // If the reply port is busy (the rotator client owns it) fall back to
        // an ephemeral port — the PSR-100 answers the source port too.
        if bound != 0 {
            logger.info("broadcast probe: reply port \(replyPort) busy, using ephemeral")
        }
        var timeout = timeval(tv_sec: 0, tv_usec: 300_000)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    }
}
