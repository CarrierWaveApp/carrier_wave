// LAN address enumeration
//
// Lists this Mac's IPv4 addresses via getifaddrs so the Settings UI can show
// the user what to type into the S.A.T.'s "QSO LOG IP" field.

import Foundation

enum LANAddress {
    // MARK: Internal

    struct Entry: Identifiable, Hashable, Sendable {
        let interface: String
        let address: String

        var id: String {
            "\(interface)/\(address)"
        }
    }

    /// Up, non-loopback IPv4 addresses, most useful first: `en0` (built-in
    /// Wi-Fi / Ethernet), then other `en*` interfaces, then the rest. Tunnels
    /// (`utun*`), AWDL and similar virtual interfaces are excluded.
    static func ipv4Entries() -> [Entry] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else {
            return []
        }
        defer { freeifaddrs(head) }

        var entries: [Entry] = []
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let current = cursor {
            cursor = current.pointee.ifa_next
            if let entry = entry(from: current.pointee) {
                entries.append(entry)
            }
        }
        return entries.sorted { rank($0.interface) < rank($1.interface) }
    }

    /// Best guess at the address a device on the same LAN should use.
    static func preferred() -> Entry? {
        ipv4Entries().first
    }

    // MARK: Private

    private static let excludedPrefixes = ["lo", "utun", "awdl", "llw", "bridge", "gif", "stf", "ap"]

    private static func entry(from interface: ifaddrs) -> Entry? {
        guard let address = interface.ifa_addr,
              address.pointee.sa_family == sa_family_t(AF_INET)
        else {
            return nil
        }
        let flags = Int32(bitPattern: interface.ifa_flags)
        guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0 else {
            return nil
        }
        let name = String(cString: interface.ifa_name)
        guard !excludedPrefixes.contains(where: { name.hasPrefix($0) }) else {
            return nil
        }
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let status = getnameinfo(
            address, socklen_t(address.pointee.sa_len),
            &host, socklen_t(host.count),
            nil, 0, NI_NUMERICHOST
        )
        guard status == 0 else {
            return nil
        }
        return Entry(interface: name, address: String(cString: host))
    }

    private static func rank(_ interface: String) -> (Int, String) {
        if interface == "en0" {
            return (0, interface)
        }
        if interface.hasPrefix("en") {
            return (1, interface)
        }
        return (2, interface)
    }
}
