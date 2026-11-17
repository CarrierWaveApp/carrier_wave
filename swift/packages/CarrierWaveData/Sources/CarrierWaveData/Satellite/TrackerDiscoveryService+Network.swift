import Darwin
import Foundation

extension TrackerDiscoveryService {
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
}
