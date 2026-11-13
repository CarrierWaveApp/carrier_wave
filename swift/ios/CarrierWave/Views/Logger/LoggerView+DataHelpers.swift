import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - LoggerView SCP, Utility & Helpers

extension LoggerView {
    // MARK: - SCP (Super Check Partial)

    /// Update callsign suggestions and known-callsign status based on current input.
    /// Merges SCP database with active POTA spot callsigns via CallsignSuggestionProvider.
    func updateSCPSuggestions(for callsign: String) {
        let spotCallsigns = cachedPOTASpots.map(\.activator)

        scpSuggestions = CallsignSuggestionProvider.suggestions(
            for: callsign,
            spotCallsigns: spotCallsigns,
            contactCounts: suggestionContactCounts
        )

        // Known-callsign indicator (border tint) — only when SCP warnings are enabled
        let fragment = callsign.trimmingCharacters(in: .whitespaces).uppercased()
        let scpDisabled = UserDefaults.standard.object(forKey: "scpEnabled") as? Bool == false
        let scpWarningDisabled = !(UserDefaults.standard.object(forKey: "scpWarningEnabled") as? Bool ?? false)
        if scpDisabled || scpWarningDisabled {
            scpCallsignKnown = nil
        } else if fragment.count >= 4 {
            scpCallsignKnown = CallsignSuggestionProvider.contains(
                fragment,
                spotCallsigns: spotCallsigns
            )
        } else if fragment.isEmpty {
            scpCallsignKnown = nil
        }
    }

    // MARK: - Utility

    func formatWebSDRDuration(_ duration: TimeInterval) -> String {
        let total = Int(duration)
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    // MARK: - Activity Item Fetch

    /// Fetch the most recent own sessionCompleted ActivityItem
    func fetchLatestOwnActivity() -> ActivityItem? {
        let typeRaw = ActivityType.sessionCompleted.rawValue
        var descriptor = FetchDescriptor<ActivityItem>(
            predicate: #Predicate {
                $0.isOwn && $0.activityTypeRawValue == typeRaw
            },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    // MARK: - Callsign & Park Helpers

    /// Build a callsign change note when QRZ redirected to a different canonical call
    func buildCallsignChangeNote(loggedCallsign: String) -> String? {
        guard let lookup = lookupResult, lookup.callsignChangeNote != nil else {
            return nil
        }
        return "Logged as \(loggedCallsign) but operator changed to \(lookup.callsign)"
    }

    func lookupParkName(_ reference: String?) -> String? {
        guard let ref = reference else {
            return nil
        }
        // For multi-park, look up the first park only
        let firstPark = ParkReference.split(ref).first ?? ref
        return POTAParksCache.shared.nameSync(for: firstPark)
    }
}
