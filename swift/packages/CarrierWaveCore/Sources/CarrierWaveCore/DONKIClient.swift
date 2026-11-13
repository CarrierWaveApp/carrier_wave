// DONKI Client
//
// NASA Space Weather Database (DONKI) API client.
// Fetches geomagnetic storms, solar flares, and CMEs.

import Foundation

// MARK: - RadioImpactLevel

/// Severity of radio propagation impact from a space weather event.
public enum RadioImpactLevel: Int, Sendable, Comparable, CaseIterable {
    case none = 0
    case minor = 1
    case moderate = 2
    case severe = 3
    case extreme = 4

    // MARK: Public

    public var label: String {
        switch self {
        case .none: "None"
        case .minor: "Minor"
        case .moderate: "Moderate"
        case .severe: "Severe"
        case .extreme: "Extreme"
        }
    }

    public static func < (lhs: RadioImpactLevel, rhs: RadioImpactLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - DONKIGeostorm

public struct DONKIGeostorm: Sendable, Codable {
    public let gstID: String
    public let startTime: String
    public let allKpIndex: [KpObservation]?
    public let link: String

    /// Peak Kp value across all observations
    public var peakKp: Double {
        allKpIndex?.compactMap(\.kpIndex).max() ?? 0
    }
}

// MARK: - KpObservation

public struct KpObservation: Sendable, Codable {
    // MARK: Lifecycle

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        observedTime = try container.decode(String.self, forKey: .observedTime)
        source = try container.decode(String.self, forKey: .source)

        // kpIndex can be a Double or a String in the API
        if let doubleVal = try? container.decode(Double.self, forKey: .kpIndex) {
            kpIndex = doubleVal
        } else if let stringVal = try? container.decode(String.self, forKey: .kpIndex) {
            kpIndex = Double(stringVal)
        } else {
            kpIndex = nil
        }
    }

    // MARK: Public

    public let observedTime: String
    public let kpIndex: Double?
    public let source: String

    // MARK: Internal

    enum CodingKeys: String, CodingKey {
        case observedTime
        case kpIndex
        case source
    }
}

// MARK: - DONKIFlare

public struct DONKIFlare: Sendable, Codable {
    public let flrID: String
    public let beginTime: String
    public let peakTime: String?
    public let endTime: String?
    public let classType: String
    public let sourceLocation: String?
    public let link: String
    public let note: String?
}

// MARK: - DONKICME

public struct DONKICME: Sendable, Codable {
    public let activityID: String
    public let startTime: String
    public let sourceLocation: String?
    public let link: String
    public let note: String?
    public let cmeAnalyses: [CMEAnalysis]?
}

// MARK: - CMEAnalysis

public struct CMEAnalysis: Sendable, Codable {
    public let speed: Double?
    public let halfAngle: Double?
    public let type: String?
}

// MARK: - DONKIEvent

/// Unified space weather event.
public enum DONKIEvent: Sendable {
    case geostorm(DONKIGeostorm)
    case flare(DONKIFlare)
    case cme(DONKICME)

    // MARK: Public

    public var eventID: String {
        switch self {
        case let .geostorm(gst): gst.gstID
        case let .flare(flr): flr.flrID
        case let .cme(cme): cme.activityID
        }
    }

    public var startTimeString: String {
        switch self {
        case let .geostorm(gst): gst.startTime
        case let .flare(flr): flr.beginTime
        case let .cme(cme): cme.startTime
        }
    }

    public var startDate: Date? {
        DONKIDateParser.parse(startTimeString)
    }

    public var link: String {
        switch self {
        case let .geostorm(gst): gst.link
        case let .flare(flr): flr.link
        case let .cme(cme): cme.link
        }
    }

    public var note: String? {
        switch self {
        case .geostorm: nil
        case let .flare(flr): flr.note
        case let .cme(cme): cme.note
        }
    }

    public var typeName: String {
        switch self {
        case .geostorm: "Geomagnetic Storm"
        case .flare: "Solar Flare"
        case .cme: "CME"
        }
    }

    public var typeIcon: String {
        switch self {
        case .geostorm: "bolt.fill"
        case .flare: "sun.max.trianglebadge.exclamationmark"
        case .cme: "wind"
        }
    }

    public var summary: String {
        switch self {
        case let .geostorm(gst):
            let kp = gst.peakKp
            return "Kp \(String(format: "%.0f", kp)) — HF blackouts, auroral absorption"
        case let .flare(flr):
            return "\(flr.classType) — Sudden ionospheric disturbance"
        case let .cme(cme):
            let speed = cme.cmeAnalyses?.compactMap(\.speed).max()
            if let speed {
                return "\(Int(speed)) km/s — GST possible in 1-3 days"
            }
            return "Coronal mass ejection detected"
        }
    }

    public var radioImpact: RadioImpactLevel {
        switch self {
        case let .geostorm(gst):
            geostormImpact(kp: gst.peakKp)
        case let .flare(flr):
            flareImpact(classType: flr.classType)
        case let .cme(cme):
            cmeImpact(cme: cme)
        }
    }

    /// Computed expiry date for this event.
    /// Flares: endTime + 1h grace, or 3h after start if no endTime.
    /// Geostorms: 24h after last Kp observation, or 24h after start.
    /// CMEs: 48h after start (transit forecasts).
    public var expiryDate: Date? {
        switch self {
        case let .flare(flr):
            if let endStr = flr.endTime,
               let endDate = DONKIDateParser.parse(endStr)
            {
                return endDate.addingTimeInterval(3_600) // 1h grace
            }
            return startDate?.addingTimeInterval(10_800) // 3h
        case let .geostorm(gst):
            let lastObs = gst.allKpIndex?
                .compactMap { DONKIDateParser.parse($0.observedTime) }
                .max()
            let anchor = lastObs ?? startDate
            return anchor?.addingTimeInterval(86_400) // 24h
        case .cme:
            return startDate?.addingTimeInterval(172_800) // 48h
        }
    }

    /// Whether this event is still relevant for display.
    public func isActive(at now: Date = Date()) -> Bool {
        guard let expiry = expiryDate else {
            return true
        }
        return now < expiry
    }

    // MARK: Private

    private func geostormImpact(kp: Double) -> RadioImpactLevel {
        switch kp {
        case ..<5: .minor
        case ..<7: .moderate
        case ..<8: .severe
        default: .extreme
        }
    }

    private func flareImpact(classType: String) -> RadioImpactLevel {
        let upper = classType.uppercased()
        if upper.hasPrefix("X") {
            return .severe
        }
        if upper.hasPrefix("M") {
            return .moderate
        }
        if upper.hasPrefix("C") {
            return .minor
        }
        return .none
    }

    private func cmeImpact(cme: DONKICME) -> RadioImpactLevel {
        let maxSpeed = cme.cmeAnalyses?.compactMap(\.speed).max() ?? 0
        if maxSpeed < 1_000 {
            return .minor
        } else if maxSpeed < 1_500 {
            return .moderate
        }
        return .severe
    }
}

// MARK: - DONKIDateParser

enum DONKIDateParser {
    // MARK: Internal

    static func parse(_ string: String) -> Date? {
        // DONKI uses mixed formats: with/without seconds, with/without Z
        let cleaned = string.hasSuffix("Z") ? string : string + "Z"
        return formatter.date(from: cleaned)
            ?? formatterNoSeconds.date(from: cleaned)
            ?? formatterNoZ.date(from: string)
            ?? formatterNoZNoSeconds.date(from: string)
    }

    static func formatQueryDate(_ date: Date) -> String {
        queryFormatter.string(from: date)
    }

    // MARK: Private

    nonisolated(unsafe) private static let formatter: ISO8601DateFormatter = {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime]
        return fmt
    }()

    private static let formatterNoSeconds: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd'T'HH:mm'Z'"
        fmt.timeZone = TimeZone(identifier: "UTC")
        fmt.locale = Locale(identifier: "en_US_POSIX")
        return fmt
    }()

    private static let formatterNoZ: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        fmt.timeZone = TimeZone(identifier: "UTC")
        fmt.locale = Locale(identifier: "en_US_POSIX")
        return fmt
    }()

    private static let formatterNoZNoSeconds: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd'T'HH:mm"
        fmt.timeZone = TimeZone(identifier: "UTC")
        fmt.locale = Locale(identifier: "en_US_POSIX")
        return fmt
    }()

    private static let queryFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.timeZone = TimeZone(identifier: "UTC")
        fmt.locale = Locale(identifier: "en_US_POSIX")
        return fmt
    }()
}

// MARK: - DONKIClient

/// Client for the NASA DONKI Space Weather API.
/// Fetches geomagnetic storms, solar flares, and CMEs.
public actor DONKIClient {
    // MARK: Lifecycle

    public init() {}

    // MARK: Public

    public func fetchGeostorms(
        startDate: Date,
        endDate: Date
    ) async throws -> [DONKIGeostorm] {
        try await fetch(
            endpoint: "GST",
            startDate: startDate,
            endDate: endDate
        )
    }

    public func fetchFlares(
        startDate: Date,
        endDate: Date
    ) async throws -> [DONKIFlare] {
        try await fetch(
            endpoint: "FLR",
            startDate: startDate,
            endDate: endDate
        )
    }

    public func fetchCMEs(
        startDate: Date,
        endDate: Date
    ) async throws -> [DONKICME] {
        try await fetch(
            endpoint: "CME",
            startDate: startDate,
            endDate: endDate
        )
    }

    /// Fetch all active events within the lookback window, sorted by time descending.
    public func fetchActiveEvents(
        lookbackDays: Int = 3
    ) async -> [DONKIEvent] {
        let now = Date()
        let start = Calendar.current.date(
            byAdding: .day,
            value: -lookbackDays,
            to: now
        ) ?? now

        // Check cache
        if let cached = cachedEvents,
           now.timeIntervalSince(cacheTimestamp ?? .distantPast) < cacheInterval
        {
            return cached
        }

        var events: [DONKIEvent] = []

        // Fetch all three types, never crash on individual failures
        if let storms = try? await fetchGeostorms(
            startDate: start, endDate: now
        ) {
            events.append(contentsOf: storms.map { .geostorm($0) })
        }

        if let flares = try? await fetchFlares(
            startDate: start, endDate: now
        ) {
            events.append(contentsOf: flares.map { .flare($0) })
        }

        if let cmes = try? await fetchCMEs(
            startDate: start, endDate: now
        ) {
            events.append(contentsOf: cmes.map { .cme($0) })
        }

        // Filter out expired events
        events = events.filter { $0.isActive(at: now) }

        // Sort by start time descending
        events.sort { eventA, eventB in
            let dateA = eventA.startDate ?? .distantPast
            let dateB = eventB.startDate ?? .distantPast
            return dateA > dateB
        }

        cachedEvents = events
        cacheTimestamp = now
        return events
    }

    // MARK: Private

    private let baseURL = "https://kauai.ccmc.gsfc.nasa.gov/DONKI/WS/get/"
    private let cacheInterval: TimeInterval = 1_800 // 30 minutes

    private var cachedEvents: [DONKIEvent]?
    private var cacheTimestamp: Date?

    private func fetch<T: Decodable & Sendable>(
        endpoint: String,
        startDate: Date,
        endDate: Date
    ) async throws -> [T] {
        let startStr = DONKIDateParser.formatQueryDate(startDate)
        let endStr = DONKIDateParser.formatQueryDate(endDate)

        guard let url = URL(
            string: "\(baseURL)\(endpoint)?startDate=\(startStr)&endDate=\(endStr)"
        ) else {
            return []
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue(
            "CarrierWave/1.0",
            forHTTPHeaderField: "User-Agent"
        )

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse,
              http.statusCode == 200
        else {
            return []
        }

        let decoder = JSONDecoder()
        return (try? decoder.decode([T].self, from: data)) ?? []
    }
}
