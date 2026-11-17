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
        let networks = sweepNetworks()
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
        await Self.merge(broadcastTask.value, into: &found)
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

    static let maxConcurrentProbes = 48

    // MARK: Private

    private enum Keys {
        static let extraNetworks = "tracker.extraNetworks"
        static let knownHosts = "tracker.knownHosts"
    }

    private let defaults: UserDefaults

    /// Fold broadcast-probe hits into the sweep results.
    private static func merge(_ trackers: [DiscoveredTracker], into found: inout [String: DiscoveredTracker]) {
        for tracker in trackers {
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
    }

    /// This device's networks plus the remembered extras, de-duplicated.
    private func sweepNetworks() -> [LocalNetwork] {
        var networks = Self.localNetworks()
        for cidr in extraNetworks {
            if let extra = LocalNetwork(cidr: cidr),
               !networks.contains(where: { $0.address & $0.mask == extra.address & extra.mask })
            {
                networks.append(extra)
            }
        }
        return networks
    }
}
