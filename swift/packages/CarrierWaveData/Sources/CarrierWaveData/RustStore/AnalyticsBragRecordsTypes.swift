import Foundation

// MARK: - BragRecordsResult

/// The SQL-expressible volume / records / "fun" brag-sheet stats (mirrors cw-store
/// `BragRecords` / `BragSheetComputationActor`'s volume + fun + misc-totals set). The
/// `*Day` / `mostQSOsSession` / `activeModes` counts are 0 over no data (→ `.noData` view-side
/// for the records); the "best" fields are `nil` then. `(label, count)` records reuse
/// `ItemTallyRow`; `earliestQSO` / `latestQSO` are unix seconds (UTC).
public struct BragRecordsResult: Equatable, Sendable {
    // MARK: Lifecycle

    public init(
        mostQSOsDay: Int,
        mostQSOsSession: Int,
        mostCountriesDay: Int,
        mostBandsDay: Int,
        mostActiveWeekday: ItemTallyRow?,
        busiestBand: ItemTallyRow?,
        busiestMode: ItemTallyRow?,
        repeatCustomer: ItemTallyRow?,
        earliestQSO: Int?,
        latestQSO: Int?,
        totalDistanceKm: Double?,
        activeModes: Int
    ) {
        self.mostQSOsDay = mostQSOsDay
        self.mostQSOsSession = mostQSOsSession
        self.mostCountriesDay = mostCountriesDay
        self.mostBandsDay = mostBandsDay
        self.mostActiveWeekday = mostActiveWeekday
        self.busiestBand = busiestBand
        self.busiestMode = busiestMode
        self.repeatCustomer = repeatCustomer
        self.earliestQSO = earliestQSO
        self.latestQSO = latestQSO
        self.totalDistanceKm = totalDistanceKm
        self.activeModes = activeModes
    }

    // MARK: Public

    public let mostQSOsDay: Int
    public let mostQSOsSession: Int
    public let mostCountriesDay: Int
    public let mostBandsDay: Int
    public let mostActiveWeekday: ItemTallyRow?
    public let busiestBand: ItemTallyRow?
    public let busiestMode: ItemTallyRow?
    public let repeatCustomer: ItemTallyRow?
    public let earliestQSO: Int?
    public let latestQSO: Int?
    public let totalDistanceKm: Double?
    public let activeModes: Int
}
