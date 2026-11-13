import CarrierWaveCore
import Foundation

// Oracle for the brag-sheet signal-quality average and club-membership worked set, re-derived
// independently of the SQL for cross-impl parity. `bragAverageRST` mirrors
// `BragSheetComputationActor.computeAverageRST`; `workedMemberCallsigns` supplies the worked-member
// callsign set that the actor's `computeClubMembersWorked` / `computeClubsRepresented` consume.

public extension AnalyticsAggregator {
    /// Average RST strength (S) digit over visible QSOs, or `nil` when none qualify. For each QSO
    /// whose `rstReceived` has at least two characters, the S digit is the second collected digit
    /// (`compactMap(\.wholeNumberValue).dropFirst().first`).
    static func bragAverageRST(over qsos: [QSO]) -> Double? {
        let signals = visibleOnly(qsos).compactMap { qso -> Int? in
            guard let rst = qso.rstReceived, rst.count >= 2 else {
                return nil
            }
            return rst.compactMap(\.wholeNumberValue).dropFirst().first
        }
        guard !signals.isEmpty else {
            return nil
        }
        return Double(signals.reduce(0, +)) / Double(signals.count)
    }

    /// The DISTINCT uppercased visible-QSO callsigns that are in the (uppercased) `members` set,
    /// sorted ascending.
    static func workedMemberCallsigns(over qsos: [QSO], members: Set<String>) -> [String] {
        let upperMembers = Set(members.map { $0.uppercased() })
        var worked = Set<String>()
        for qso in visibleOnly(qsos) {
            let key = qso.callsign.uppercased()
            if upperMembers.contains(key) {
                worked.insert(key)
            }
        }
        return worked.sorted()
    }
}
