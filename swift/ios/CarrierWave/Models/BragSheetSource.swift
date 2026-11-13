// BragSheetSource — neutral input for the activation/session share card.
//
// `ActivationShareCardView` originally took a `POTAActivation` directly, which
// pinned every field name to "park". SOTA sessions need the same card shape —
// callsign, QSOs, map, stats — but with a summit reference instead of a park.
//
// This struct wraps just the fields the share card actually needs and exposes
// converters from POTAActivation (existing path) and LoggingSession + qsos
// (new SOTA path). The renderer and views read from this instead of poking
// program-specific models.

import CarrierWaveData
import Foundation

// MARK: - BragSheetSource

struct BragSheetSource {
    enum Program {
        case pota
        case sota
        case dual // POTA + SOTA on the same session
        case casual // no program — generic share

        // MARK: Internal

        var icon: String {
            switch self {
            case .pota: "tree.fill"
            case .sota: "mountain.2.fill"
            case .dual: "tree.fill"
            case .casual: "antenna.radiowaves.left.and.right"
            }
        }
    }

    /// Display label for the activation reference (e.g. "US-1234" or "W6/CT-021").
    /// `nil` for casual sessions.
    let referenceCode: String?
    /// Friendly name for the reference (park or summit) when known.
    let referenceName: String?
    /// SF Symbol shown next to the reference label.
    let referenceIcon: String
    /// Operator callsign as logged.
    let callsign: String
    /// QSOs included in the share. The card reads bands/modes/duration/grids
    /// from this directly so the source doesn't need to precompute them.
    let qsos: [QSO]
    /// Pre-formatted UTC date (e.g. "April 24, 2026") to keep formatting
    /// consistent with the existing POTA path.
    let displayDate: String
    /// Optional metadata title set by the user.
    let title: String?
    /// Which program the share is being generated for — drives the icon
    /// fallback when the caller doesn't override it.
    let program: Program

    var qsoCount: Int {
        qsos.count
    }

    /// Unique bands worked, e.g. {"20m", "40m"}.
    var uniqueBands: Set<String> {
        Set(qsos.map(\.band))
    }

    /// Modes deduplicated through `ModeEquivalence` so the card doesn't list
    /// `CW` and `CW`-mapped variants separately.
    var uniqueModes: [String] {
        ModeEquivalence.deduplicatedModes(qsos.map(\.mode))
    }

    /// QSOs with a usable `theirGrid`, used to drive the share-card map.
    var mappableQSOs: [QSO] {
        qsos.filter { qso in
            guard let grid = qso.theirGrid, grid.count >= 4 else {
                return false
            }
            return true
        }
    }

    /// Activation duration as the sum of per-session spans (matches POTA path —
    /// gaps between sessions don't inflate the total).
    var duration: TimeInterval {
        guard !qsos.isEmpty else {
            return 0
        }
        var groups: [UUID?: [QSO]] = [:]
        for qso in qsos {
            groups[qso.loggingSessionId, default: []].append(qso)
        }
        var total: TimeInterval = 0
        for (_, group) in groups {
            guard let first = group.min(by: { $0.timestamp < $1.timestamp }),
                  let last = group.max(by: { $0.timestamp < $1.timestamp })
            else {
                continue
            }
            total += last.timestamp.timeIntervalSince(first.timestamp)
        }
        return total
    }

    /// Formatted duration string (e.g. "2h 15m" or "45m").
    var formattedDuration: String {
        let totalMinutes = Int(duration) / 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
}

// MARK: - POTAActivation Converter

extension BragSheetSource {
    /// Build a share-card source from the existing POTA path. Preserves the
    /// previous behaviour — same display date, same icon, same field shape.
    static func pota(
        activation: POTAActivation,
        parkName: String?,
        title: String? = nil
    ) -> BragSheetSource {
        BragSheetSource(
            referenceCode: activation.parkReference,
            referenceName: parkName,
            referenceIcon: Program.pota.icon,
            callsign: activation.callsign,
            qsos: activation.qsos,
            displayDate: activation.displayDate,
            title: title,
            program: .pota
        )
    }
}

// MARK: - LoggingSession Converter

extension BragSheetSource {
    /// Build a share-card source from a logging session — used for SOTA-only
    /// sessions and any future non-POTA share path. The caller passes the
    /// session's QSOs explicitly so we don't need a ModelContext here.
    /// Returns `nil` when the session has no callsign to label the card with.
    static func session(
        _ session: LoggingSession,
        qsos: [QSO],
        summitName: String? = nil
    ) -> BragSheetSource? {
        guard !session.myCallsign.isEmpty else {
            return nil
        }

        let program: Program
        let referenceCode: String?
        let referenceName: String?
        let icon: String
        if session.isPOTA, session.isSOTA {
            program = .dual
            // Prefer SOTA reference for the headline since POTA already has its own
            // share path; this mirrors how the menu treats dual sessions.
            referenceCode = session.sotaReference ?? session.parkReference
            referenceName = summitName
            icon = Program.sota.icon
        } else if session.isSOTA {
            program = .sota
            referenceCode = session.sotaReference
            referenceName = summitName
            icon = Program.sota.icon
        } else if session.isPOTA {
            program = .pota
            referenceCode = session.parkReference
            referenceName = nil
            icon = Program.pota.icon
        } else {
            program = .casual
            referenceCode = nil
            referenceName = nil
            icon = Program.casual.icon
        }

        return BragSheetSource(
            referenceCode: referenceCode,
            referenceName: referenceName,
            referenceIcon: icon,
            callsign: session.myCallsign,
            qsos: qsos,
            displayDate: Self.displayDate(for: session, qsos: qsos),
            title: session.customTitle,
            program: program
        )
    }

    /// Match POTAActivation's "April 24, 2026" UTC date format. Falls back to
    /// the session's start date when the QSO list is empty.
    private static func displayDate(for session: LoggingSession, qsos: [QSO]) -> String {
        let date = qsos.min(by: { $0.timestamp < $1.timestamp })?.timestamp ?? session.startedAt
        return Self.displayDateFormatter.string(from: date)
    }

    private static let displayDateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "MMMM d, yyyy"
        df.timeZone = TimeZone(identifier: "UTC")
        return df
    }()
}
