import CarrierWaveData
import Foundation

// MARK: - Contest

/// A contest from the WA7BNM Contest Calendar RSS feed, enriched with
/// mode/band/template metadata at parse time.
///
/// In-memory only — not persisted to SwiftData.
nonisolated struct Contest: Identifiable, Hashable {
    // MARK: Internal

    let id: String // GUID from RSS
    let title: String
    let link: URL?
    let startDate: Date
    let endDate: Date
    let enrichment: ContestEnrichment

    /// Whether the contest is currently running.
    var isActive: Bool {
        let now = Date()
        return now >= startDate && now <= endDate
    }

    /// Whether the contest hasn't started yet.
    var isUpcoming: Bool {
        Date() < startDate
    }

    /// Human-readable status.
    var statusLabel: String {
        if isActive {
            "Active"
        } else if isUpcoming {
            "Upcoming"
        } else {
            "Ended"
        }
    }

    /// Compact start date string (e.g. "Feb 27, 22:00Z").
    var formattedStart: String {
        Self.formatter.string(from: startDate)
    }

    /// Compact end date string.
    var formattedEnd: String {
        Self.formatter.string(from: endDate)
    }

    /// Wall-clock duration.
    var duration: TimeInterval {
        endDate.timeIntervalSince(startDate)
    }

    /// Short form of the total duration ("24h", "6h sprint", "48h").
    var durationLabel: String {
        let hours = Int(duration.rounded() / 3_600)
        if hours >= 24, hours.isMultiple(of: 24) {
            let days = hours / 24
            return days == 1 ? "24h" : "\(days)d"
        }
        if hours <= 6 {
            return "\(hours)h sprint"
        }
        return "\(hours)h"
    }

    /// Time remaining in an active contest, or nil when not active.
    var timeRemaining: TimeInterval? {
        guard isActive else {
            return nil
        }
        return endDate.timeIntervalSinceNow
    }

    /// Time until an upcoming contest starts, or nil when not upcoming.
    var timeUntilStart: TimeInterval? {
        guard isUpcoming else {
            return nil
        }
        return startDate.timeIntervalSinceNow
    }

    /// Progress (0.0–1.0) through an active contest, or nil.
    var progress: Double? {
        guard isActive else {
            return nil
        }
        let total = duration
        guard total > 0 else {
            return nil
        }
        let elapsed = Date().timeIntervalSince(startDate)
        return min(1.0, max(0.0, elapsed / total))
    }

    // MARK: Private

    private static let formatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d, HH:mm'Z'"
        fmt.timeZone = TimeZone(identifier: "UTC")
        return fmt
    }()
}

// MARK: - ContestEnrichment

/// Structured metadata extracted from the WA7BNM description and matched
/// against the app's bundled contest templates.
///
/// Everything here is best-effort — if a field is missing we degrade to
/// the unenriched UI rather than guessing.
nonisolated struct ContestEnrichment: Hashable {
    /// Modes (CW, SSB, Digital, Mixed, FT8, RTTY...)
    var modes: [String] = []

    /// Bands ("160m", "80m", ...). Empty if unparseable or "All HF".
    var bands: [String] = []

    /// "All HF", "VHF+", "6m" etc. when bands couldn't be parsed individually.
    var bandSummary: String?

    /// Short exchange preview ("RST + State").
    var exchangePreview: String?

    /// Matching template from `CarrierWaveData/ContestTemplates` — when
    /// non-nil we can start a fully-scored logging session directly.
    var matchedTemplateId: String?

    /// 1–5 "popularity" tier. 5 = CQ WW scale, 1 = niche sprint.
    /// Hard-coded for known majors; nil means "unknown, don't show".
    var popularity: Int?

    /// Loose "category" tag ("DX", "Sprint", "QSO Party", "VHF", etc.)
    var category: ContestCategory = .unknown
}

// MARK: - ContestCategory

nonisolated enum ContestCategory: String, CaseIterable {
    case dx
    case qsoParty = "qso_party"
    case sprint
    case fieldDay = "field_day"
    case vhf
    case digital
    case cw
    case ssb
    case stateQSOParty = "state_qso_party"
    case specialEvent = "special_event"
    case unknown

    // MARK: Internal

    var displayLabel: String {
        switch self {
        case .dx: "DX"
        case .qsoParty: "QSO Party"
        case .sprint: "Sprint"
        case .fieldDay: "Field Day"
        case .vhf: "VHF"
        case .digital: "Digital"
        case .cw: "CW"
        case .ssb: "SSB"
        case .stateQSOParty: "State QSO Party"
        case .specialEvent: "Special Event"
        case .unknown: "Contest"
        }
    }
}
