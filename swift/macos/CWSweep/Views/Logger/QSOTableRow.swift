import CarrierWaveData
import Foundation

// MARK: - QSOLogRowMetrics

/// Fixed vertical metrics shared by every cell in the compact QSO log so all
/// rows render at one height regardless of content (CAR-193). The time column
/// stacks a date caption over the time; every other column is a single
/// truncated line centred in the same `rowHeight`.
enum QSOLogRowMetrics {
    /// Height of every cell (and therefore every row) in the QSO log table.
    static let rowHeight: CGFloat = 28
    /// Height reserved for the date caption line in the time column.
    static let dateLineHeight: CGFloat = 12
    /// Height reserved for the time line in the time column.
    static let timeLineHeight: CGFloat = 14
    /// Square frame for optional inline glyphs (e.g. the park-to-park tree).
    static let inlineIconSize: CGFloat = 12

    /// Total height of the stacked date + time lines. Must fit in `rowHeight`
    /// or the time column would push its row taller than the others.
    static var timeStackHeight: CGFloat {
        dateLineHeight + timeLineHeight
    }
}

// MARK: - QSOTableRow

/// Lightweight display-only snapshot of a QSO for table rendering.
/// All display strings are precomputed at init to avoid per-frame formatter overhead.
struct QSOTableRow: Identifiable {
    // MARK: Lifecycle

    init(from qso: QSO) {
        id = qso.id
        timestamp = qso.timestamp
        callsign = qso.callsign
        band = qso.band
        mode = qso.mode
        name = qso.name?.capitalized
        contestSerialSent = qso.contestSerialSent
        contestSerialReceived = qso.contestSerialReceived
        contestExchangeSent = qso.contestExchangeSent
        contestExchangeReceived = qso.contestExchangeReceived

        // Precompute all display strings once
        dateKey = Self.dateFormatter.string(from: qso.timestamp)
        timeDisplay = Self.timeFormatter.string(from: qso.timestamp)
        freqDisplay = qso.frequency.map { String(format: "%.3f", $0) }
        parkDisplay = qso.theirParkReference ?? qso.parkReference
        parkReference = qso.parkReference
        hasParkReference = qso.theirParkReference != nil && qso.parkReference != nil
        rstCombined = Self.combineRST(sent: qso.rstSent, received: qso.rstReceived)
        // isFirstOfDate is set after sorting in loadQSOs()
        isFirstOfDate = false
    }

    // MARK: Internal

    let id: UUID
    let timestamp: Date
    let callsign: String
    let band: String
    let mode: String
    let name: String?
    let contestSerialSent: Int?
    let contestSerialReceived: Int?
    let contestExchangeSent: String?
    let contestExchangeReceived: String?

    let dateKey: String
    let timeDisplay: String
    let freqDisplay: String?
    let parkDisplay: String?
    /// Own park reference — the park this QSO was logged under (used in rove sessions)
    let parkReference: String?
    let hasParkReference: Bool
    let rstCombined: String?

    /// True for the first QSO of each date — shows date in the time column
    var isFirstOfDate: Bool

    // MARK: Private

    private static let dateFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d, yyyy"
        return fmt
    }()

    private static let timeFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateStyle = .none
        fmt.timeStyle = .short
        return fmt
    }()

    private static func combineRST(sent: String?, received: String?) -> String? {
        switch (sent, received) {
        case let (rstSent?, rstRecv?):
            "\(rstSent)/\(rstRecv)"
        case let (rstSent?, nil):
            "\(rstSent)S"
        case let (nil, rstRecv?):
            "\(rstRecv)R"
        case (nil, nil):
            nil
        }
    }
}
