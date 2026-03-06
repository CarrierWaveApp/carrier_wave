import Foundation

/// A DX cluster telnet node
struct ClusterNode: Identifiable, Hashable, Sendable {
    /// Well-known cluster nodes
    static let presets: [ClusterNode] = [
        ClusterNode(
            id: "w3lpl",
            name: "W3LPL",
            host: "w3lpl.net",
            port: 7_373,
            description: "East Coast US — High traffic, excellent US/EU coverage"
        ),
        ClusterNode(
            id: "ve7cc",
            name: "VE7CC",
            host: "dxc.ve7cc.net",
            port: 23,
            description: "West Coast Canada — Good Pacific/Asia coverage"
        ),
        ClusterNode(
            id: "n1mm",
            name: "N1MM",
            host: "n1mm.net",
            port: 7_300,
            description: "Contest-oriented cluster"
        ),
        ClusterNode(
            id: "ab5k",
            name: "AB5K",
            host: "dxc.ab5k.net",
            port: 7_300,
            description: "Central US cluster"
        ),
        ClusterNode(
            id: "k1ttt",
            name: "K1TTT",
            host: "k1ttt.net",
            port: 7_373,
            description: "New England cluster"
        ),
    ]

    let id: String
    let name: String
    let host: String
    let port: UInt16
    let description: String

    /// Create a custom node
    static func custom(name: String, host: String, port: UInt16) -> ClusterNode {
        ClusterNode(
            id: "custom-\(host):\(port)",
            name: name,
            host: host,
            port: port,
            description: "Custom node"
        )
    }
}
