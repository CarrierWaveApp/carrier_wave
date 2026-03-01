import Foundation
import SwiftData

// MARK: - CallsignSuggestionProvider

/// Merges SCP database results with active spot callsigns for unified suggestions.
/// Used by both the Logger and Hunter Log quick-log views.
/// Suggestions are weighted by previous contact count — frequently worked stations appear first.
enum CallsignSuggestionProvider {
    // MARK: Internal

    /// Returns merged suggestions from SCP database and spot callsigns,
    /// weighted by previous contact count (most-contacted first).
    /// Spot matches get a boost over SCP-only matches at equal contact counts.
    static func suggestions(
        for fragment: String,
        spotCallsigns: [String],
        contactCounts: [String: Int] = [:],
        limit: Int = 20
    ) -> [String] {
        let scpDisabled = UserDefaults.standard.object(forKey: "scpEnabled") as? Bool == false
        guard !scpDisabled else {
            return []
        }

        let upper = fragment.trimmingCharacters(in: .whitespaces).uppercased()
        guard upper.count >= 3,
              LoggerCommand.parse(fragment) == nil
        else {
            return []
        }

        let spotSet = Set(spotCallsigns.map { $0.uppercased() })
        var candidates = collectCandidates(
            upper: upper, spotCallsigns: spotCallsigns, contactCounts: contactCounts, limit: limit
        )

        // Sort: highest contact count first, then spot matches before SCP-only
        candidates.sort { lhs, rhs in
            if lhs.score != rhs.score {
                return lhs.score > rhs.score
            }
            let lhsIsSpot = spotSet.contains(lhs.callsign)
            let rhsIsSpot = spotSet.contains(rhs.callsign)
            if lhsIsSpot != rhsIsSpot {
                return lhsIsSpot
            }
            return lhs.callsign < rhs.callsign
        }

        return Array(candidates.prefix(limit).map(\.callsign))
    }

    /// Whether the callsign exists in the SCP database or active spots.
    static func contains(_ callsign: String, spotCallsigns: [String]) -> Bool {
        let upper = callsign.uppercased()
        if spotCallsigns.contains(where: { $0.uppercased() == upper }) {
            return true
        }
        return SCPService.shared.database.contains(upper)
    }

    /// Load contact counts per callsign from QSO history.
    /// Runs on a background context to avoid blocking the main thread.
    nonisolated static func loadContactCounts(
        container: ModelContainer
    ) -> [String: Int] {
        let context = ModelContext(container)
        context.autosaveEnabled = false

        let predicate = #Predicate<QSO> { qso in
            !qso.isHidden
                && qso.mode != "WEATHER"
                && qso.mode != "SOLAR"
                && qso.mode != "NOTE"
        }
        var descriptor = FetchDescriptor<QSO>(predicate: predicate)
        descriptor.propertiesToFetch = [\.callsign]

        guard let qsos = try? context.fetch(descriptor) else {
            return [:]
        }

        var counts: [String: Int] = [:]
        counts.reserveCapacity(qsos.count / 2)
        for qso in qsos {
            counts[qso.callsign, default: 0] += 1
        }
        return counts
    }

    // MARK: Private

    private static func collectCandidates(
        upper: String,
        spotCallsigns: [String],
        contactCounts: [String: Int],
        limit: Int
    ) -> [(callsign: String, score: Int)] {
        var seen = Set<String>()
        var candidates: [(callsign: String, score: Int)] = []

        // Spot matches: prefix first, then substring
        for call in spotCallsigns {
            let callUpper = call.uppercased()
            guard callUpper.hasPrefix(upper), seen.insert(callUpper).inserted else {
                continue
            }
            candidates.append((callUpper, contactCounts[callUpper, default: 0]))
        }
        for call in spotCallsigns {
            let callUpper = call.uppercased()
            guard !callUpper.hasPrefix(upper), callUpper.contains(upper),
                  seen.insert(callUpper).inserted
            else {
                continue
            }
            candidates.append((callUpper, contactCounts[callUpper, default: 0]))
        }

        // SCP matches
        let db = SCPService.shared.database
        if !db.isEmpty {
            for call in db.partialMatch(upper, limit: limit * 2) {
                guard seen.insert(call).inserted else {
                    continue
                }
                candidates.append((call, contactCounts[call, default: 0]))
            }
        }

        return candidates
    }
}
