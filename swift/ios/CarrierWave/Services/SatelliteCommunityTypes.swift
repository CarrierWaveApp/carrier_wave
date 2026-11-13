import CarrierWaveCore
import UIKit

// MARK: - CommunityActivityStatus

/// How one grid cell is coloured — amsat.org's status legend plus `quiet`
/// for a cell with no reports. Bridged from the engine's classification.
nonisolated enum CommunityActivityStatus: Sendable, Equatable {
    case quiet
    case heard
    case telemetryOnly
    case notHeard
    case conflicting

    // MARK: Lifecycle

    init(ffi: FfiActivityStatus) {
        switch ffi {
        case .quiet:
            self = .quiet
        case .heard:
            self = .heard
        case .telemetryOnly:
            self = .telemetryOnly
        case .notHeard:
            self = .notHeard
        case .conflicting:
            self = .conflicting
        }
    }

    // MARK: Internal

    /// Legend wording (matches the AMSAT status page).
    var label: String {
        switch self {
        case .quiet: "No reports"
        case .heard: "Sat/Mode active"
        case .telemetryOnly: "TLM/Beacon only"
        case .notHeard: "Not heard"
        case .conflicting: "Conflicting reports"
        }
    }

    /// True when at least one report said the bird was transmitting.
    var isPositive: Bool {
        self == .heard || self == .conflicting || self == .telemetryOnly
    }
}

// MARK: - CommunityActivityBucket

/// One occupied cell of a satellite's activity row.
nonisolated struct CommunityActivityBucket: Identifiable, Sendable, Equatable {
    // MARK: Lifecycle

    private init(start: Date) {
        self.start = start
        heard = 0
        notHeard = 0
        telemetry = 0
        crew = 0
        other = 0
        total = 0
        status = .quiet
    }

    init(ffi: FfiActivityBucket) {
        start = Date(timeIntervalSince1970: TimeInterval(ffi.startEpoch))
        heard = Int(ffi.heard)
        notHeard = Int(ffi.notHeard)
        telemetry = Int(ffi.telemetry)
        crew = Int(ffi.crew)
        other = Int(ffi.other)
        total = Int(ffi.total)
        status = CommunityActivityStatus(ffi: ffi.status)
    }

    // MARK: Internal

    let start: Date
    let heard: Int
    let notHeard: Int
    let telemetry: Int
    let crew: Int
    let other: Int
    let total: Int
    let status: CommunityActivityStatus

    var id: Date {
        start
    }

    /// An empty cell at `start` (for scrub readouts over quiet hours).
    static func quiet(at start: Date) -> CommunityActivityBucket {
        CommunityActivityBucket(start: start)
    }
}

// MARK: - CommunityActivityRow

/// One AMSAT-tracked transmitter (e.g. `AO-7_[U/v]`) with its cells and
/// the engine's enrichment: catalog identity, the matching SatNOGS
/// transmitter, the observer's next pass, and the operator's own QSOs.
nonisolated struct CommunityActivityRow: Identifiable, Sendable {
    // MARK: Lifecycle

    init(ffi: FfiCommunityActivityRow) {
        amsatName = ffi.amsatName
        baseName = ffi.baseName
        capability = ffi.capability
        noradID = ffi.noradId.map { Int($0) }
        inCatalog = ffi.inCatalog
        displayName = ffi.displayName
        detailName = ffi.detailName
        modeCategory = ffi.modeCategory.map(SatelliteModeCategory.init(ffi:))
        transmitterMode = ffi.transmitterMode
        downlinkLow = ffi.downlinkLowHz
        uplinkLow = ffi.uplinkLowHz
        transmitterActive = ffi.transmitterActive
        lastHeardAt = ffi.lastHeardEpoch.map { Date(timeIntervalSince1970: TimeInterval($0)) }
        heardReports24h = Int(ffi.heardReports24h)
        totalReports24h = Int(ffi.totalReports24h)
        nextPass = ffi.nextPass.map(SatellitePass.init(ffi:))
        myQSOCount = Int(ffi.myQsoCount)
        buckets = ffi.buckets.map(CommunityActivityBucket.init(ffi:))
    }

    // MARK: Internal

    /// AMSAT's internal name, e.g. `AO-7_[U/v]`.
    let amsatName: String
    /// The satellite part: `AO-7`.
    let baseName: String
    /// The bracket tag: `U/v`, `FM`, `SSDV`, …
    let capability: String?
    let noradID: Int?
    /// In the engine's workable catalog (selectable on the map, has passes).
    let inCatalog: Bool
    let displayName: String
    let detailName: String?
    let modeCategory: SatelliteModeCategory?
    let transmitterMode: String?
    let downlinkLow: Int64?
    let uplinkLow: Int64?
    /// SatNOGS still lists the matching transmitter as active (nil = no match).
    let transmitterActive: Bool?
    let lastHeardAt: Date?
    let heardReports24h: Int
    let totalReports24h: Int
    let nextPass: SatellitePass?
    /// QSOs in the operator's log through this bird inside the window.
    let myQSOCount: Int
    /// Occupied cells, ascending by start.
    let buckets: [CommunityActivityBucket]

    var id: String {
        amsatName
    }

    /// Any positive community report in the window.
    var heardInWindow: Bool {
        buckets.contains { $0.status.isPositive }
    }

    /// The mode string to badge the row with: the SatNOGS mode when a
    /// transmitter matched, else the AMSAT tag.
    var badgeMode: String? {
        transmitterMode ?? capability
    }
}

// MARK: - CommunityActivity

/// The whole community-activity grid for one window.
nonisolated struct CommunityActivity: Sendable {
    // MARK: Lifecycle

    init(ffi: FfiCommunityActivity) {
        windowStart = Date(timeIntervalSince1970: TimeInterval(ffi.windowStartEpoch))
        windowEnd = Date(timeIntervalSince1970: TimeInterval(ffi.windowEndEpoch))
        bucketSeconds = TimeInterval(ffi.bucketSecs)
        updatedAt = ffi.updatedAtEpoch.map { Date(timeIntervalSince1970: TimeInterval($0)) }
        fetchedAt = Date(timeIntervalSince1970: TimeInterval(ffi.fetchedAtEpoch))
        isStale = ffi.isStale
        rows = ffi.rows.map(CommunityActivityRow.init(ffi:))
    }

    // MARK: Internal

    let windowStart: Date
    let windowEnd: Date
    /// Width of every cell.
    let bucketSeconds: TimeInterval
    /// When the server last refreshed from AMSAT.
    let updatedAt: Date?
    /// When the engine fetched (or, when stale, last fetched) the payload.
    let fetchedAt: Date
    let isStale: Bool
    /// Rows in AMSAT's order.
    let rows: [CommunityActivityRow]

    /// Number of cells spanning the window (partial trailing cell included).
    var cellCount: Int {
        max(1, Int((windowEnd.timeIntervalSince(windowStart) / bucketSeconds).rounded(.up)))
    }

    /// Start of cell `index` counted newest-first (0 = the cell containing
    /// `windowEnd`), aligned to `windowStart` like the engine's cells.
    func cellStart(newestFirst index: Int) -> Date {
        windowStart.addingTimeInterval(TimeInterval(cellCount - 1 - index) * bucketSeconds)
    }
}

// MARK: - CommunityViewport

/// The slice of the activity window currently on screen — shared by every
/// strip in the list so pinch/pan move all rows together. Continuous (no
/// snapping to buckets) so gestures track the finger; the strips draw
/// bars at fractional positions.
nonisolated struct CommunityViewport: Sendable, Equatable {
    // MARK: Lifecycle

    init(activity: CommunityActivity, range: ClosedRange<Date>? = nil) {
        windowStart = activity.windowStart
        windowEnd = activity.windowEnd
        bucketSeconds = activity.bucketSeconds
        let full = windowStart ... windowEnd
        let requested = range ?? full
        let fullSpan = windowEnd.timeIntervalSince(windowStart)
        let span = min(fullSpan, max(Self.minimumSpan, requested.upperBound.timeIntervalSince(requested.lowerBound)))
        var start = max(requested.lowerBound, full.lowerBound)
        if start.addingTimeInterval(span) > windowEnd {
            start = windowEnd.addingTimeInterval(-span)
        }
        self.start = start
        end = start.addingTimeInterval(span)
    }

    // MARK: Internal

    /// Narrowest zoom, in seconds.
    static let minimumSpan: TimeInterval = 6 * 3_600

    let windowStart: Date
    let windowEnd: Date
    let bucketSeconds: TimeInterval
    let start: Date
    let end: Date

    var span: TimeInterval {
        end.timeIntervalSince(start)
    }

    var isZoomed: Bool {
        span < windowEnd.timeIntervalSince(windowStart) - 1
    }

    var showsNow: Bool {
        end >= windowEnd.addingTimeInterval(-1)
    }

    /// Horizontal position of a date as a fraction of the viewport (may
    /// fall outside 0…1 for off-screen dates).
    func fraction(of date: Date) -> Double {
        date.timeIntervalSince(start) / span
    }

    /// Zoom by `scale` (>1 zooms in) keeping the date under `anchor`
    /// (0 = left edge, 1 = right edge) fixed on screen, span clamped to
    /// [minimumSpan, whole window].
    func zoomed(by scale: Double, anchor: Double, activity: CommunityActivity) -> CommunityViewport {
        let fullSpan = windowEnd.timeIntervalSince(windowStart)
        let newSpan = min(fullSpan, max(Self.minimumSpan, span / max(scale, 0.01)))
        let pivot = start.addingTimeInterval(anchor * span)
        let newStart = pivot.addingTimeInterval(-anchor * newSpan)
        return CommunityViewport(activity: activity, range: newStart ... newStart.addingTimeInterval(newSpan))
    }

    /// Pan by a fraction of the visible span (positive = later), stopping
    /// at the window edges.
    func panned(byFraction fraction: Double, activity: CommunityActivity) -> CommunityViewport {
        var delta = fraction * span
        if start.addingTimeInterval(delta) < windowStart {
            delta = windowStart.timeIntervalSince(start)
        }
        if end.addingTimeInterval(delta) > windowEnd {
            delta = windowEnd.timeIntervalSince(end)
        }
        return CommunityViewport(
            activity: activity,
            range: start.addingTimeInterval(delta) ... end.addingTimeInterval(delta)
        )
    }
}

// MARK: - SatelliteModeCategory + FFI

nonisolated extension SatelliteModeCategory {
    init(ffi: FfiSatModeCategory) {
        switch ffi {
        case .voiceFm:
            self = .voiceFM
        case .linear:
            self = .linear
        case .morse:
            self = .morse
        case .digital:
            self = .digital
        }
    }
}

// MARK: - CommunityReport

/// One community report for the selected bird, placed at the reporter's
/// grid square when they gave one.
nonisolated struct CommunityReport: Identifiable, Sendable {
    // MARK: Lifecycle

    init(ffi: FfiCommunityReport) {
        amsatName = ffi.amsatName
        time = Date(timeIntervalSince1970: TimeInterval(ffi.epoch))
        callsign = ffi.callsign
        grid = ffi.grid
        latitude = ffi.latitude
        longitude = ffi.longitude
        report = ffi.report
        status = CommunityActivityStatus(ffi: ffi.status)
    }

    // MARK: Internal

    let amsatName: String
    let time: Date
    let callsign: String
    let grid: String?
    let latitude: Double?
    let longitude: Double?
    let report: String
    let status: CommunityActivityStatus

    var id: String {
        "\(amsatName)|\(time.timeIntervalSince1970)|\(callsign)|\(report)"
    }
}

// MARK: - ReporterMark

/// A map mark for one placed report.
nonisolated struct ReporterMark: Identifiable, Sendable, Equatable {
    let id: String
    let latitude: Double
    let longitude: Double
    let status: CommunityActivityStatus
}

// MARK: - PreviousOrbitSummary

/// What the community saw on the bird's previous orbit.
nonisolated struct PreviousOrbitSummary: Sendable, Equatable {
    // MARK: Lifecycle

    init(ffi: FfiPreviousOrbit) {
        periodMinutes = ffi.periodMinutes
        windowStart = Date(timeIntervalSince1970: TimeInterval(ffi.windowStartEpoch))
        heard = Int(ffi.heard)
        telemetry = Int(ffi.telemetry)
        notHeard = Int(ffi.notHeard)
        heardCallsigns = ffi.heardCallsigns
        status = CommunityActivityStatus(ffi: ffi.status)
    }

    // MARK: Internal

    let periodMinutes: Double
    let windowStart: Date
    let heard: Int
    let telemetry: Int
    let notHeard: Int
    let heardCallsigns: [String]
    let status: CommunityActivityStatus

    /// Prefix list like "DL, ON, EI" from the heard callsigns (letters up
    /// to and including the first digit).
    var heardPrefixes: [String] {
        var seen = Set<String>()
        return heardCallsigns.compactMap { call in
            guard let digit = call.firstIndex(where: \.isNumber) else {
                return nil
            }
            let prefix = String(call[...digit])
            return seen.insert(prefix).inserted ? prefix : nil
        }
    }

    /// "Heard by 4 on the previous orbit (DL, ON, EI)" style line.
    var line: String {
        switch status {
        case .quiet:
            return "No reports on the previous orbit"
        case .heard,
             .conflicting:
            var text = "Heard by \(heard) on the previous orbit"
            if notHeard > 0 {
                text += ", \(notHeard) not heard"
            }
            if !heardPrefixes.isEmpty {
                text += " (" + heardPrefixes.prefix(4).joined(separator: ", ") + ")"
            }
            return text
        case .telemetryOnly:
            return "Telemetry only on the previous orbit (\(telemetry))"
        case .notHeard:
            return "Not heard by \(notHeard) on the previous orbit"
        }
    }
}

// MARK: - CommunityReports

/// The selected bird's recent reports plus the previous-orbit summary.
nonisolated struct CommunityReports: Sendable {
    // MARK: Lifecycle

    init(ffi: FfiCommunityReports) {
        noradID = Int(ffi.noradId)
        windowStart = Date(timeIntervalSince1970: TimeInterval(ffi.windowStartEpoch))
        windowEnd = Date(timeIntervalSince1970: TimeInterval(ffi.windowEndEpoch))
        isStale = ffi.isStale
        reports = ffi.reports.map(CommunityReport.init(ffi:))
        previousOrbit = ffi.previousOrbit.map(PreviousOrbitSummary.init(ffi:))
    }

    // MARK: Internal

    let noradID: Int
    let windowStart: Date
    let windowEnd: Date
    let isStale: Bool
    let reports: [CommunityReport]
    let previousOrbit: PreviousOrbitSummary?

    /// Placed reports as map marks, one per reporter grid (newest wins).
    var marks: [ReporterMark] {
        var seen = Set<String>()
        return reports.compactMap { report in
            guard let lat = report.latitude, let lon = report.longitude, let grid = report.grid,
                  seen.insert(grid.uppercased()).inserted
            else {
                return nil
            }
            return ReporterMark(id: report.id, latitude: lat, longitude: lon, status: report.status)
        }
    }
}

// MARK: - CommunityReportReceipt

/// AMSAT's acknowledgement of a report the operator filed.
nonisolated struct CommunityReportReceipt: Sendable, Equatable {
    // MARK: Lifecycle

    init(ffi: FfiCommunityReportReceipt) {
        id = ffi.id
        amsatName = ffi.amsatName
        reportedAt = Date(timeIntervalSince1970: TimeInterval(ffi.reportedAtEpoch))
        report = ffi.report
        callsign = ffi.callsign
        replacedCount = Int(ffi.replacedCount)
    }

    // MARK: Internal

    let id: Int64
    let amsatName: String
    /// AMSAT's hour-quantised stamp for the report.
    let reportedAt: Date
    let report: String
    let callsign: String
    /// Earlier reports of yours for the same satellite, hour and quarter
    /// hour that this one replaced.
    let replacedCount: Int
}
