import Darwin
import Foundation
import Network
import OSLog

private let logger = Logger(subsystem: "com.jsvana.CarrierWaveData", category: "TrackerDiscovery")

// MARK: - TrackerDiscoveryService

/// Finds CSN S.A.T. trackers and WA4MCM PSR-100 rotors on the local network.
///
/// Neither unit advertises over Bonjour, so discovery is an active sweep of
/// every IPv4 /24 this device sits on:
/// - **S.A.T.**: a TCP connect to the Hamlib rotator port (4533) that answers
///   `p` with a position. The web UI on port 80 is fetched to tell a real
///   S.A.T. ("CSN" / "S.A.T." in the page) from a PC running `rotctld`.
/// - **PSR-100 Mk2**: its web UI on port 8080 mentions "PSR-100". A UDP
///   `AZ EL` / `<PST>AZ?</PST>` broadcast probe (reply ports 2391 / 12001)
///   catches units whose web page didn't load in time and tells us which
///   protocol the rotor is set to.
///
/// A sweep is bounded (about 500 hosts × short timeouts, 48 in flight) and
/// typically finishes in under ten seconds.
@MainActor
@Observable
public final class TrackerDiscoveryService {
    // MARK: Lifecycle

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        extraNetworks = defaults.stringArray(forKey: Keys.extraNetworks) ?? []
        knownHosts = Set(defaults.stringArray(forKey: Keys.knownHosts) ?? [])
    }

    // MARK: Public

    /// Networks beyond this device's own, swept every time (CIDR strings such
    /// as "192.168.20.0/24"). Learned automatically from any unit found by
    /// address, or added by hand for a rotor on an IoT VLAN. Persisted.
    public private(set) var extraNetworks: [String]
    /// Addresses that once answered (or were saved as the rotator); probed
    /// directly on every sweep so a unit on another subnet is found even when
    /// its network isn't swept. Persisted.
    public private(set) var knownHosts: Set<String>

    public private(set) var discovered: [DiscoveredTracker] = []
    public private(set) var isScanning = false
    public private(set) var lastScanAt: Date?
    public private(set) var lastError: String?
    /// Networks the last sweep covered, e.g. ["192.168.1.0/24"].
    public private(set) var scannedNetworks: [String] = []

    /// Sweep the LAN once. Safe to call again; a sweep already running is
    /// left alone.
    public func scan() async {
        guard !isScanning else {
            return
        }
        isScanning = true
        lastError = nil
        defer {
            isScanning = false
            lastScanAt = Date()
        }
        var networks = Self.localNetworks()
        for cidr in extraNetworks {
            if let extra = LocalNetwork(cidr: cidr),
               !networks.contains(where: { $0.address & $0.mask == extra.address & extra.mask })
            {
                networks.append(extra)
            }
        }
        scannedNetworks = networks.map(\.cidr)
        guard !networks.isEmpty else {
            lastError = "No IPv4 network interface found — join Wi-Fi or plug in Ethernet."
            return
        }
        // Remembered addresses first (other subnets, fixed IPs), then the sweep.
        let swept = Set(networks.flatMap(\.hosts))
        let hosts = knownHosts.sorted().filter { !swept.contains($0) } + networks.flatMap(\.hosts)
        var found: [String: DiscoveredTracker] = [:]

        // UDP broadcast probes run alongside the sweep.
        let broadcastTask = Task.detached(priority: .utility) {
            await Self.broadcastProbe(networks: networks)
        }

        await withTaskGroup(of: DiscoveredTracker?.self) { group in
            var iterator = hosts.makeIterator()
            var inFlight = 0
            func enqueue(_ host: String) {
                group.addTask(priority: .utility) {
                    await Self.probeHost(host)
                }
            }
            while inFlight < Self.maxConcurrentProbes, let host = iterator.next() {
                enqueue(host)
                inFlight += 1
            }
            while let result = await group.next() {
                inFlight -= 1
                if let result {
                    found[result.id] = result
                    discovered = Array(found.values).sorted { $0.host < $1.host }
                }
                if let host = iterator.next() {
                    enqueue(host)
                    inFlight += 1
                }
            }
        }
        for tracker in await broadcastTask.value {
            if found[tracker.id] == nil {
                found[tracker.id] = tracker
            } else if tracker.kind == .psr100 {
                // The broadcast reply tells us which protocol the rotor is
                // actually set to; prefer it over the HTTP default.
                found[tracker.id]?.endpoint.protocolKind = tracker.endpoint.protocolKind
                found[tracker.id]?.endpoint.port = tracker.endpoint.port
                found[tracker.id]?.endpoint.replyPort = tracker.endpoint.replyPort
            }
        }
        let results = Array(found.values).sorted { $0.host < $1.host }
        discovered = results
        logger.info("tracker sweep found \(results.count) unit(s) on \(networks.count) network(s)")
    }

    /// Probe one address and work out what it is (S.A.T. on 4533, PSR-100 web
    /// UI on 8080, then unicast EasyComm / S.A.T.-XML UDP queries). On a hit
    /// the unit joins `discovered`; `nil` means nothing answered.
    @discardableResult
    public func identify(host: String) async -> DiscoveredTracker? {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        var found = await Self.probeHost(trimmed)
        if found == nil {
            found = await Self.probeUDPRotator(trimmed)
        }
        guard let found else {
            return nil
        }
        discovered.removeAll { $0.host == found.host }
        discovered.append(found)
        discovered.sort { $0.host < $1.host }
        remember(host: found.host)
        return found
    }

    /// Remember an address (and its /24) so later sweeps find the unit
    /// hands-free even though it lives on another subnet.
    public func remember(host: String) {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }
        var changed = false
        if !knownHosts.contains(trimmed) {
            knownHosts.insert(trimmed)
            defaults.set(knownHosts.sorted(), forKey: Keys.knownHosts)
            changed = true
        }
        if let network = LocalNetwork(cidr: trimmed), !Self.isLocal(network), !extraNetworks.contains(network.cidr) {
            extraNetworks.append(network.cidr)
            changed = true
        }
        if changed {
            defaults.set(extraNetworks, forKey: Keys.extraNetworks)
        }
    }

    /// Add a network to sweep ("192.168.20.0/24"; a bare address means its
    /// /24). Returns the normalized CIDR, or nil when unparsable.
    @discardableResult
    public func addNetwork(_ text: String) -> String? {
        guard let network = LocalNetwork(cidr: text.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return nil
        }
        if !extraNetworks.contains(network.cidr) {
            extraNetworks.append(network.cidr)
            defaults.set(extraNetworks, forKey: Keys.extraNetworks)
        }
        return network.cidr
    }

    public func removeNetwork(_ cidr: String) {
        extraNetworks.removeAll { $0 == cidr }
        defaults.set(extraNetworks, forKey: Keys.extraNetworks)
        // Drop remembered hosts that lived only on that network.
        if let network = LocalNetwork(cidr: cidr) {
            knownHosts = knownHosts.filter { host in
                guard let address = LocalNetwork.parseAddress(host) else {
                    return true
                }
                return address & network.mask != network.address & network.mask
            }
            defaults.set(knownHosts.sorted(), forKey: Keys.knownHosts)
        }
    }

    public func forgetHost(_ host: String) {
        knownHosts.remove(host)
        defaults.set(knownHosts.sorted(), forKey: Keys.knownHosts)
    }

    /// Add a unit the sweep can't see (other subnet, VPN) by address.
    public func addManual(host: String, kind: TrackerKind, protocolKind: RotatorProtocolKind? = nil) {
        let endpoint = TrackerEndpoint(kind: kind, host: host, protocolKind: protocolKind)
        let tracker = DiscoveredTracker(
            endpoint: endpoint,
            name: kind.displayName,
            detail: "\(host) · added manually"
        )
        discovered.removeAll { $0.id == tracker.id }
        discovered.append(tracker)
        discovered.sort { $0.host < $1.host }
    }

    // MARK: Internal

    /// One IPv4 interface's network, truncated to a /24 when the mask is
    /// wider so a sweep stays bounded.
    struct LocalNetwork: Sendable, Equatable {
        // MARK: Lifecycle

        init(interface: String, address: UInt32, mask: UInt32) {
            self.interface = interface
            self.address = address
            self.mask = mask
        }

        /// "192.168.20.0/24" → network; a bare "192.168.20.89" → its /24. Prefix
        /// lengths narrower than /24 are widened to /24 (we never sweep more
        /// than 254 hosts per network).
        init?(cidr: String) {
            let parts = cidr.split(separator: "/", maxSplits: 1).map(String.init)
            guard let first = parts.first, let address = Self.parseAddress(first) else {
                return nil
            }
            var prefix = 24
            if parts.count == 2 {
                guard let given = Int(parts[1]), (8 ... 32).contains(given) else {
                    return nil
                }
                prefix = max(given, 24)
            }
            let mask: UInt32 = prefix == 32 ? 0xFFFF_FFFF : ~((1 << (32 - prefix)) - 1)
            self.init(interface: "extra", address: address & mask, mask: mask)
        }

        // MARK: Internal

        let interface: String
        let address: UInt32
        let mask: UInt32

        var cidr: String {
            "\(Self.dotted(address & mask))/\(mask.nonzeroBitCount)"
        }

        var broadcastAddress: String {
            Self.dotted((address & mask) | ~mask)
        }

        /// Every host address except ourselves, network and broadcast.
        var hosts: [String] {
            let base = address & mask
            let count = Int(~mask)
            guard count >= 2 else {
                return []
            }
            return (1 ..< count).map { base + UInt32($0) }
                .filter { $0 != address }
                .map(Self.dotted)
        }

        static func dotted(_ value: UInt32) -> String {
            "\((value >> 24) & 0xFF).\((value >> 16) & 0xFF).\((value >> 8) & 0xFF).\(value & 0xFF)"
        }

        static func parseAddress(_ text: String) -> UInt32? {
            let octets = text.split(separator: ".", omittingEmptySubsequences: false)
            guard octets.count == 4 else {
                return nil
            }
            var value: UInt32 = 0
            for octet in octets {
                guard let number = UInt32(octet), number <= 255 else {
                    return nil
                }
                value = (value << 8) | number
            }
            return value
        }
    }

    static let maxConcurrentProbes = 48

    /// True when the device itself sits on this network (no need to remember it).
    nonisolated static func isLocal(_ network: LocalNetwork) -> Bool {
        localNetworks().contains { $0.address & $0.mask == network.address & network.mask }
    }

    /// Enumerate IPv4 interfaces (skipping loopback, link-local, and
    /// point-to-point tunnels) and clamp each to at most a /24.
    nonisolated static func localNetworks() -> [LocalNetwork] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else {
            return []
        }
        defer { freeifaddrs(head) }
        var result: [LocalNetwork] = []
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = cursor {
            defer { cursor = entry.pointee.ifa_next }
            guard let addr = entry.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET),
                  let maskPtr = entry.pointee.ifa_netmask
            else {
                continue
            }
            let flags = Int32(entry.pointee.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0, flags & IFF_POINTOPOINT == 0 else {
                continue
            }
            let name = String(cString: entry.pointee.ifa_name)
            // utun*/ipsec* are VPN tunnels; bridge*/awdl* aren't LANs we sweep.
            if name.hasPrefix("utun") || name.hasPrefix("ipsec") || name.hasPrefix("awdl")
                || name.hasPrefix("llw") || name.hasPrefix("bridge")
            {
                continue
            }
            let address = addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                UInt32(bigEndian: $0.pointee.sin_addr.s_addr)
            }
            var mask = maskPtr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                UInt32(bigEndian: $0.pointee.sin_addr.s_addr)
            }
            // 169.254/16 link-local: skip.
            if (address >> 16) == 0xA9FE {
                continue
            }
            if mask.nonzeroBitCount < 24 {
                mask = 0xFFFF_FF00
            }
            let network = LocalNetwork(interface: name, address: address, mask: mask)
            if !result.contains(where: { $0.address & $0.mask == network.address & network.mask }) {
                result.append(network)
            }
        }
        // en0 first so the primary LAN is swept before secondary adapters.
        return result.sorted { lhs, rhs in
            if lhs.interface == "en0" {
                return true
            }
            if rhs.interface == "en0" {
                return false
            }
            return lhs.interface < rhs.interface
        }
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

    // MARK: Private

    private enum Keys {
        static let extraNetworks = "tracker.extraNetworks"
        static let knownHosts = "tracker.knownHosts"
    }

    private let defaults: UserDefaults

    nonisolated private static func probeHamlibRotator(_ host: String) async -> DiscoveredTracker? {
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

    nonisolated private static func probePSR100Web(_ host: String) async -> DiscoveredTracker? {
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
    nonisolated private static func probeUDPRotator(_ host: String) async -> DiscoveredTracker? {
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
    nonisolated private static func fetchText(host: String, port: UInt16, timeout: Duration) async -> String? {
        var request = URLRequest(url: URL(string: "http://\(host):\(port)/")!)
        request.timeoutInterval = Double(timeout.components.seconds)
            + Double(timeout.components.attoseconds) / 1e18
        request.httpMethod = "GET"
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        do {
            let (data, _) = try await session.data(for: request)
            return String(bytes: data.prefix(64 * 1_024), encoding: .utf8) ?? String(
                decoding: data.prefix(64 * 1_024),
                as: UTF8.self
            )
        } catch {
            return nil
        }
    }

    /// Broadcast an EasyComm `AZ EL` query to 2390 and a S.A.T. XML `AZ?` to
    /// 12000 on every network, then read replies on 2391 / 12001 for ~1.5 s.
    nonisolated private static func broadcastProbe(networks: [LocalNetwork]) async -> [DiscoveredTracker] {
        let probes: [(RotatorProtocolKind, UInt16, UInt16)] = [
            (.easycommII, 2_390, 2_391),
            (.csnSATxml, 12_000, 12_001),
        ]
        var found: [DiscoveredTracker] = []
        for (protocolKind, port, replyPort) in probes {
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
    nonisolated private static func broadcast(
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
}
