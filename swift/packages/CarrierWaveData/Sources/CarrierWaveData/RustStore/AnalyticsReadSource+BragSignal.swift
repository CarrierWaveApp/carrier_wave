import CarrierWaveCore
import Foundation

// MARK: - RustAnalyticsReadSource + brag signal/club stats

/// The brag-sheet signal-quality average and club-membership worked set, served from cw-store's
/// `brag_average_rst` and `worked_member_callsigns`. `query` is the optional `.cwquery` DSL filter
/// (the brag period). The club→callsign mapping stays app-side; the store only supplies the
/// worked-member callsign set.
public extension RustAnalyticsReadSource {
    /// Average RST strength (S) digit over visible QSOs matching `query`, or `nil` when no QSO
    /// qualifies. Faithful port of `BragSheetComputationActor.computeAverageRST`.
    func bragAverageRST(query: String, start: Int? = nil, end: Int? = nil) async throws -> Double? {
        try store.bragAverageRst(query: query, start: start.map(Int64.init), end: end.map(Int64.init))
    }

    /// The DISTINCT uppercased QSO callsigns (over visible QSOs matching `query`) that are in the
    /// (uppercased) `members` set, sorted ascending. Empty `members` → empty list.
    func workedMemberCallsigns(
        query: String,
        members: [String],
        start: Int? = nil,
        end: Int? = nil
    ) async throws -> [String] {
        try store.workedMemberCallsigns(
            query: query,
            members: members,
            start: start.map(Int64.init),
            end: end.map(Int64.init)
        )
    }
}
