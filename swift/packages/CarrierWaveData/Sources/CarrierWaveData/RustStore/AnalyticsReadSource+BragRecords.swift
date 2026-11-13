import CarrierWaveCore
import Foundation

// MARK: - RustAnalyticsReadSource + brag records

/// The SQL-expressible volume / records / "fun" brag-sheet stats, served from cw-store's
/// `brag_records`. `query` is the optional `.cwquery` DSL filter (the brag period).
public extension RustAnalyticsReadSource {
    func bragRecords(query: String, start: Int? = nil, end: Int? = nil) async throws -> BragRecordsResult {
        let rec = try store.bragRecords(query: query, start: start.map(Int64.init), end: end.map(Int64.init))
        return BragRecordsResult(
            mostQSOsDay: Int(rec.mostQsosDay),
            mostQSOsSession: Int(rec.mostQsosSession),
            mostCountriesDay: Int(rec.mostCountriesDay),
            mostBandsDay: Int(rec.mostBandsDay),
            mostActiveWeekday: rec.mostActiveWeekday.map(Self.tally),
            busiestBand: rec.busiestBand.map(Self.tally),
            busiestMode: rec.busiestMode.map(Self.tally),
            repeatCustomer: rec.repeatCustomer.map(Self.tally),
            earliestQSO: rec.earliestQso.map(Int.init),
            latestQSO: rec.latestQso.map(Int.init),
            totalDistanceKm: rec.totalDistanceKm,
            activeModes: Int(rec.activeModes)
        )
    }

    private static func tally(_ ffi: FfiItemTally) -> ItemTallyRow {
        ItemTallyRow(name: ffi.name, count: Int(ffi.count))
    }
}
