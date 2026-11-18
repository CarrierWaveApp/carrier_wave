import CarrierWaveData
import Foundation
import OSLog

private let logger = Logger(subsystem: "com.jsvana.CWSweep", category: "IcomDiscovery")

// MARK: - DiscoveredIcomRadio

/// An Icom radio that answered an RS-BA1 "are you there" on the LAN.
struct DiscoveredIcomRadio: Identifiable, Hashable {
    let host: String
    var lastSeen: Date

    var id: String {
        host
    }
}

// MARK: - IcomDiscoveryService

/// Finds Icom LAN/WiFi radios (IC-9700, IC-705, IC-7610, …) with Network
/// Control on. Icom radios don't broadcast, so this sends the unauthenticated
/// RS-BA1 probe to each host on the Mac's local subnets (capped at a /24 per
/// interface) and keeps whoever answers. The probe can't name the model —
/// that only arrives after login (`IcomRadioInfo`).
///
/// Kept gentle on the radio: one socket + sender ID for the app's lifetime,
/// one probe per host, a full sweep at start / Scan Now / every 5 min, a
/// recheck of already-found radios every 60 s, and never a probe to a radio
/// we're connected to.
@MainActor
@Observable
final class IcomDiscoveryService {
    // MARK: Internal

    private(set) var radios: [DiscoveredIcomRadio] = []
    private(set) var isScanning = false

    /// Called with each host the first time it appears.
    @ObservationIgnored var onRadioFound: ((String) -> Void)?
    /// Hosts with a live session; these are never probed.
    @ObservationIgnored var connectedHosts: () -> Set<String> = { [] }

    func start() {
        guard scanLoop == nil else {
            return
        }
        scanLoop = Task { [weak self] in
            // macOS can drop a fresh process's first LAN packets while it
            // evaluates local-network access, so the launch sweep often
            // misses: recheck remembered radios soon after.
            await self?.check(fullSweep: true)
            for delay in [5, 10] {
                try? await Task.sleep(for: .seconds(delay))
                await self?.check(fullSweep: false)
            }
            var tick = 1
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                await self?.check(fullSweep: tick.isMultiple(of: 5))
                tick += 1
            }
        }
    }

    func stop() {
        scanLoop?.cancel()
        scanLoop = nil
    }

    /// Full subnet sweep ("Scan Now").
    func scanOnce() async {
        await check(fullSweep: true)
    }

    // MARK: Private

    @ObservationIgnored private var scanLoop: Task<Void, Never>?
    @ObservationIgnored private let prober = IcomLANProber()

    private func check(fullSweep: Bool) async {
        guard !isScanning, let prober else {
            return
        }
        isScanning = true
        defer { isScanning = false }

        let connected = connectedHosts()
        let known = radios.map(\.host)
        // Radios found this session or logged into before get several tries:
        // the 9700 sometimes ignores a single probe.
        let priorityHosts = Set(known + IcomKnownRadios.knownHosts()).subtracting(connected)
        let found = await Task.detached(priority: .utility) {
            let priority = priorityHosts.compactMap(IcomLANProber.address)
            let sweep = fullSweep
                ? IcomLANProber.localTargets().filter {
                    !priority.contains($0) && !connected.contains(IcomLANProber.string($0))
                }
                : []
            let found = prober.probe(sweep, priority: priority)
            let kind = fullSweep ? "sweep" : "recheck"
            logger.debug(
                "Icom \(kind, privacy: .public): \(priority.count)+\(sweep.count) probed, \(found.count) answered"
            )
            return found
        }.value

        let now = Date()
        var byHost = Dictionary(uniqueKeysWithValues: radios.map { ($0.host, $0) })
        for host in found.union(connected.intersection(known)) {
            if byHost[host] == nil {
                logger.info("Found Icom radio at \(host, privacy: .public)")
                onRadioFound?(host)
            }
            byHost[host] = DiscoveredIcomRadio(host: host, lastSeen: now)
        }
        // UDP is lossy and the 9700 sometimes ignores a probe: only drop a
        // radio after it misses three rechecks.
        radios = byHost.values
            .filter { now.timeIntervalSince($0.lastSeen) < 200 }
            .sorted { $0.host < $1.host }
    }
}

// MARK: - IcomLANProber

/// Blocking POSIX UDP prober owning one socket and sender ID for its whole
/// lifetime; call from one background task at a time.
final class IcomLANProber: Sendable {
    // MARK: Lifecycle

    init?() {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else {
            return nil
        }
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        sock = fd
        probePacket = IcomLANProbe.areYouThere(senderID: UInt32.random(in: 1 ... UInt32.max))
    }

    deinit {
        close(sock)
    }

    // MARK: Internal

    /// Host addresses (network order) on each up, non-virtual IPv4 interface,
    /// excluding our own. Subnets wider than /24 are narrowed to our /24.
    static func localTargets() -> [in_addr_t] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else {
            return []
        }
        defer { freeifaddrs(head) }

        var targets = Set<in_addr_t>()
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let current = cursor {
            cursor = current.pointee.ifa_next
            guard let (own, mask) = ipv4AndMask(current.pointee) else {
                continue
            }
            let narrowed = max(mask, 0xFFFF_FF00)
            let network = own & narrowed
            let hostCount = ~narrowed
            guard hostCount > 1 else {
                continue
            }
            for offset in 1 ..< hostCount where network | offset != own {
                targets.insert((network | offset).bigEndian)
            }
        }
        return Array(targets)
    }

    static func address(_ host: String) -> in_addr_t? {
        var addr = in_addr()
        return inet_pton(AF_INET, host, &addr) == 1 ? addr.s_addr : nil
    }

    static func string(_ addr: in_addr_t) -> String {
        String(cString: inet_ntoa(in_addr(s_addr: addr)))
    }

    /// Probe `targets` once and `priority` hosts three times (300 ms apart),
    /// collecting "I am here" senders.
    func probe(
        _ targets: [in_addr_t],
        priority: [in_addr_t] = [],
        listenFor seconds: Double = 1.5
    ) -> Set<String> {
        guard !targets.isEmpty || !priority.isEmpty else {
            return []
        }
        var found = collectReplies(seconds: 0) // late replies from the last round still count
        for target in priority {
            send(to: target)
        }
        // Paced: a burst of hundreds of datagrams on Wi-Fi overflows the send
        // buffer (ENOBUFS) and silently drops probes, the radio's included.
        for target in targets {
            send(to: target)
            usleep(1_000)
        }
        for _ in 0 ..< 2 where !priority.isEmpty {
            found.formUnion(collectReplies(seconds: 0.3))
            for target in priority where !found.contains(Self.string(target)) {
                send(to: target)
            }
        }
        return found.union(collectReplies(seconds: seconds))
    }

    // MARK: Private

    private static let excludedPrefixes = ["lo", "utun", "awdl", "llw", "bridge", "gif", "stf", "ap"]

    private let sock: Int32
    private let probePacket: Data

    /// Host-order (address, netmask) for a usable IPv4 interface.
    private static func ipv4AndMask(_ ifa: ifaddrs) -> (UInt32, UInt32)? {
        guard let addr = ifa.ifa_addr, addr.pointee.sa_family == sa_family_t(AF_INET),
              let maskPtr = ifa.ifa_netmask
        else {
            return nil
        }
        let flags = Int32(bitPattern: ifa.ifa_flags)
        let name = String(cString: ifa.ifa_name)
        guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0,
              !excludedPrefixes.contains(where: { name.hasPrefix($0) })
        else {
            return nil
        }
        let own = addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr.s_addr }
        let mask = maskPtr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr.s_addr }
        return (UInt32(bigEndian: own), UInt32(bigEndian: mask))
    }

    private func send(to target: in_addr_t) {
        var dest = sockaddr_in()
        dest.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        dest.sin_family = sa_family_t(AF_INET)
        dest.sin_port = UInt16(50_001).bigEndian
        dest.sin_addr.s_addr = target
        probePacket.withUnsafeBytes { buf in
            withUnsafePointer(to: &dest) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { addr in
                    let len = socklen_t(MemoryLayout<sockaddr_in>.size)
                    for _ in 0 ..< 5 {
                        if sendto(sock, buf.baseAddress, buf.count, 0, addr, len) >= 0 || errno != ENOBUFS {
                            return
                        }
                        usleep(5_000)
                    }
                }
            }
        }
    }

    private func collectReplies(seconds: Double) -> Set<String> {
        var found = Set<String>()
        let deadline = Date().addingTimeInterval(seconds)
        var buffer = [UInt8](repeating: 0, count: 256)
        repeat {
            var pfd = pollfd(fd: sock, events: Int16(POLLIN), revents: 0)
            guard poll(&pfd, 1, seconds > 0 ? 100 : 0) > 0 else {
                if seconds > 0 {
                    continue
                }
                break
            }
            var from = sockaddr_in()
            var fromLen = socklen_t(MemoryLayout<sockaddr_in>.size)
            let count = withUnsafeMutablePointer(to: &from) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    recvfrom(sock, &buffer, buffer.count, 0, $0, &fromLen)
                }
            }
            guard count > 0, IcomLANProbe.isIAmHere(Data(buffer[0 ..< count])) else {
                continue
            }
            found.insert(Self.string(from.sin_addr.s_addr))
        } while Date() < deadline
        return found
    }
}
