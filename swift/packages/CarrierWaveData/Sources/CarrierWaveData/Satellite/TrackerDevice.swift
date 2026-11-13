import Foundation

// MARK: - TrackerKind

/// Satellite tracker / rotator controllers Carrier Wave can find on the LAN.
public enum TrackerKind: String, Codable, Sendable, CaseIterable, Identifiable {
    /// CSN Technologies S.A.T. (and the newer SAT Controller): a Hamlib
    /// compatible rotator server on TCP 4533 plus a web UI on port 80.
    case csnSAT
    /// WA4MCM PSR-100 Mk2 portable rotor: UDP commands (GS-232B / EasyComm II
    /// on 2390, CSN S.A.T. XML on 12000) plus a web UI on port 8080.
    case psr100
    /// Anything else answering Hamlib `rotctld` on 4533 (a PC running
    /// rotctld, Gpredict's rotator bridge, …).
    case hamlibRotctld

    // MARK: Public

    public var id: String {
        rawValue
    }

    public var displayName: String {
        switch self {
        case .csnSAT: "CSN S.A.T."
        case .psr100: "WA4MCM PSR-100"
        case .hamlibRotctld: "Hamlib rotctld"
        }
    }

    public var vendor: String {
        switch self {
        case .csnSAT: "CSN Technologies"
        case .psr100: "WA4MCM Kits"
        case .hamlibRotctld: "Hamlib"
        }
    }

    /// Default rotator command protocol for a freshly discovered unit.
    public var defaultProtocol: RotatorProtocolKind {
        switch self {
        case .csnSAT,
             .hamlibRotctld: .hamlibRotctl
        // The Mk2's web server takes the same commands over HTTP and, unlike
        // UDP replies, HTTP crosses VLANs and needs no port setup.
        case .psr100: .psr100HTTP
        }
    }

    /// Web UI port, when the unit has one.
    public var webPort: UInt16? {
        switch self {
        case .csnSAT: 80
        case .psr100: 8_080
        case .hamlibRotctld: nil
        }
    }
}

// MARK: - RotatorProtocolKind

/// Wire protocols the rotator client speaks. The PSR-100 picks one at a time
/// on its Comm Link page; the S.A.T. always speaks Hamlib on TCP.
public enum RotatorProtocolKind: String, Codable, Sendable, CaseIterable, Identifiable {
    /// Hamlib `rotctld` text protocol over TCP (`P az el`, `p`, `S`).
    case hamlibRotctl
    /// EasyComm II / SAEBRTrackBox over UDP (`AZxxx.x ELyy.y`).
    case easycommII
    /// Yaesu GS-232B over UDP (`Wxxx yyy`, `C2`).
    case gs232B
    /// CSN S.A.T. → PstRotator XML over UDP (`<PST><AZIMUTH>…`).
    case csnSATxml
    /// PSR-100 Mk2 web server: `GET /command?cmd=AZ180EL45`, `AZ EL`, `STOP`
    /// on port 8080. Works whatever the rotor's Comm Link mode is set to.
    case psr100HTTP

    // MARK: Public

    public var id: String {
        rawValue
    }

    public var displayName: String {
        switch self {
        case .hamlibRotctl: "Hamlib rotctld (TCP)"
        case .easycommII: "EasyComm II (UDP)"
        case .gs232B: "GS-232B (UDP)"
        case .csnSATxml: "CSN S.A.T. XML (UDP)"
        case .psr100HTTP: "PSR-100 web (HTTP)"
        }
    }

    /// Connection-oriented link (TCP / HTTP) rather than UDP datagrams.
    public var isTCP: Bool {
        self == .hamlibRotctl || self == .psr100HTTP
    }

    /// Whether every command yields a reply worth waiting for.
    public var expectsReply: Bool {
        isTCP
    }

    /// Port the rotator listens on.
    public var defaultPort: UInt16 {
        switch self {
        case .hamlibRotctl: 4_533
        case .easycommII,
             .gs232B: 2_390
        case .csnSATxml: 12_000
        case .psr100HTTP: 8_080
        }
    }

    /// Port the rotator sends UDP replies to (the PSR-100 "TX Port"); the
    /// client binds its socket here so replies land whether the rotor
    /// answers the source port or this fixed one.
    public var defaultReplyPort: UInt16? {
        switch self {
        case .hamlibRotctl,
             .psr100HTTP: nil
        case .easycommII,
             .gs232B: 2_391
        case .csnSATxml: 12_001
        }
    }
}

// MARK: - RotatorPosition

/// A rotator or target pointing, degrees. Azimuth 0 ..< 360, elevation −90 … 90.
public struct RotatorPosition: Equatable, Hashable, Sendable, Codable {
    // MARK: Lifecycle

    public init(azimuthDeg: Double, elevationDeg: Double) {
        self.azimuthDeg = azimuthDeg
        self.elevationDeg = elevationDeg
    }

    // MARK: Public

    public var azimuthDeg: Double
    public var elevationDeg: Double

    /// Azimuth folded into 0 ..< 360 and elevation clamped to the mast's
    /// mechanical range.
    public func normalized(minElevation: Double = 0, maxElevation: Double = 90) -> RotatorPosition {
        var az = azimuthDeg.truncatingRemainder(dividingBy: 360)
        if az < 0 {
            az += 360
        }
        if az >= 360 {
            az -= 360
        }
        return RotatorPosition(
            azimuthDeg: az,
            elevationDeg: min(max(elevationDeg, minElevation), maxElevation)
        )
    }

    /// Largest axis error between two pointings, taking the azimuth
    /// wrap-around into account.
    public func maxAxisError(to other: RotatorPosition) -> Double {
        var dAz = abs(azimuthDeg - other.azimuthDeg).truncatingRemainder(dividingBy: 360)
        if dAz > 180 {
            dAz = 360 - dAz
        }
        return max(dAz, abs(elevationDeg - other.elevationDeg))
    }
}

// MARK: - TrackerEndpoint

/// Where a rotator lives and how to talk to it. Persisted as the station's
/// chosen tracker.
public struct TrackerEndpoint: Codable, Equatable, Hashable, Sendable, Identifiable {
    // MARK: Lifecycle

    public init(
        kind: TrackerKind,
        host: String,
        protocolKind: RotatorProtocolKind? = nil,
        port: UInt16? = nil,
        replyPort: UInt16? = nil
    ) {
        self.kind = kind
        self.host = host
        let proto = protocolKind ?? kind.defaultProtocol
        self.protocolKind = proto
        self.port = port ?? proto.defaultPort
        self.replyPort = replyPort ?? proto.defaultReplyPort
    }

    // MARK: Public

    public var kind: TrackerKind
    public var host: String
    public var protocolKind: RotatorProtocolKind
    public var port: UInt16
    public var replyPort: UInt16?

    public var id: String {
        "\(host):\(port)/\(protocolKind.rawValue)"
    }

    /// `http://host[:port]/` for the unit's web UI, when it has one.
    public var webURL: URL? {
        guard let webPort = kind.webPort else {
            return nil
        }
        let suffix = webPort == 80 ? "" : ":\(webPort)"
        return URL(string: "http://\(host)\(suffix)/")
    }
}

// MARK: - DiscoveredTracker

/// One unit found by `TrackerDiscoveryService`.
public struct DiscoveredTracker: Identifiable, Hashable, Sendable {
    // MARK: Lifecycle

    public init(endpoint: TrackerEndpoint, name: String, detail: String, lastSeen: Date = Date()) {
        self.endpoint = endpoint
        self.name = name
        self.detail = detail
        self.lastSeen = lastSeen
    }

    // MARK: Public

    public var endpoint: TrackerEndpoint
    /// e.g. "CSN S.A.T." or "PSR-100 Mk2"
    public var name: String
    /// e.g. "192.168.1.42 · rotctld 4533 · web UI"
    public var detail: String
    public var lastSeen: Date

    public var id: String {
        endpoint.id
    }

    public var kind: TrackerKind {
        endpoint.kind
    }

    public var host: String {
        endpoint.host
    }
}
