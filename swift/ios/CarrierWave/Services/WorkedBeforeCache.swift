import CarrierWaveData
import Foundation
import SwiftData

// MARK: - WorkedBeforeResult

/// Result of a worked-before check for a single callsign
struct WorkedBeforeResult {
    static let notWorked = WorkedBeforeResult(
        todayBandModes: [],
        previousBandModes: [],
        isNewDXCC: false
    )

    /// Band+mode+park keys worked today (e.g. "20m|CW|", "40m|PHONE|US-1234")
    let todayBandModes: Set<String>

    /// Band+mode-family keys worked on the previous UTC day
    let previousBandModes: Set<String>

    /// Whether this is a new DXCC entity
    let isNewDXCC: Bool

    /// Bands worked today (extracted from bandMode keys, for display)
    var todayBands: Set<String> {
        Set(todayBandModes.compactMap { $0.components(separatedBy: "|").first })
    }

    /// Bands worked on the previous UTC day (extracted from bandMode keys, for display)
    var previousBands: Set<String> {
        Set(previousBandModes.compactMap { $0.components(separatedBy: "|").first })
    }

    /// Whether this callsign has been worked at all
    var hasBeenWorked: Bool {
        !todayBandModes.isEmpty || !previousBandModes.isEmpty
    }

    /// Whether this would be a dupe on the given band, mode family, and park.
    /// Different parks are separate POTA contacts and never dupes of each other.
    func isDupe(on band: String, mode: String, park: String? = nil) -> Bool {
        let key = bandModeParkKey(band: band, mode: mode, park: park)
        return todayBandModes.contains(key)
    }
}

// MARK: - WorkedBeforeCache

/// Caches worked-before data for hunter spot checking.
/// Loads today's QSOs on open, batch-checks visible spots, updates on QSO logged.
actor WorkedBeforeCache {
    // MARK: Internal

    /// Load today's QSOs into the cache
    func loadToday(container: ModelContainer) async {
        let context = ModelContext(container)
        context.autosaveEnabled = false

        var calendar = Calendar.current
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let startOfDay = calendar.startOfDay(for: Date())

        let predicate = #Predicate<QSO> { qso in
            !qso.isHidden && qso.timestamp >= startOfDay && qso.isActivityLogQSO
        }
        let descriptor = BoundedDescriptor<QSO>(predicate: predicate, limit: 500)

        do {
            let qsos = try context.boundedFetch(descriptor)
            todayWorked.removeAll()
            for qso in qsos {
                let key = qso.callsign.uppercased()
                // A multi-park n-fer contributes one key per credited park so
                // each park's spot row crosses out independently.
                for bmKey in bandModeParkKeys(band: qso.band, mode: qso.mode, park: qso.theirParkReference) {
                    todayWorked[key, default: []].insert(bmKey)
                }
            }
        } catch {
            // Silently fail — cache will be empty
        }
    }

    /// Check a batch of callsigns against previous UTC day data
    func checkCallsigns(
        _ callsigns: [String],
        container: ModelContainer
    ) async {
        // Only look up callsigns we haven't checked yet
        let unchecked = callsigns.filter { previousDayWorked[$0.uppercased()] == nil }
        guard !unchecked.isEmpty else {
            return
        }

        let context = ModelContext(container)
        context.autosaveEnabled = false

        // Previous UTC day range (yesterday 00:00Z to today 00:00Z)
        var calendar = Calendar.current
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let startOfToday = calendar.startOfDay(for: Date())
        let startOfYesterday = calendar.date(byAdding: .day, value: -1, to: startOfToday)!

        for callsign in unchecked {
            let upper = callsign.uppercased()
            let predicate = #Predicate<QSO> { qso in
                qso.callsign == upper && !qso.isHidden
                    && qso.isActivityLogQSO
                    && qso.timestamp >= startOfYesterday
                    && qso.timestamp < startOfToday
            }
            let descriptor = BoundedDescriptor<QSO>(predicate: predicate, limit: 50)

            let bandModes: Set<String> = if let qsos = try? context.boundedFetch(descriptor) {
                Set(qsos.flatMap {
                    bandModeParkKeys(band: $0.band, mode: $0.mode, park: $0.theirParkReference)
                })
            } else {
                []
            }
            previousDayWorked[upper] = bandModes
        }
    }

    /// Get the worked-before result for a callsign on a given band
    func result(for callsign: String, band: String) -> WorkedBeforeResult {
        let upper = callsign.uppercased()
        let today = todayWorked[upper] ?? []
        let previousDay = previousDayWorked[upper] ?? []

        // DXCC checking is deferred to Phase 3
        return WorkedBeforeResult(
            todayBandModes: today,
            previousBandModes: previousDay,
            isNewDXCC: false
        )
    }

    /// Record a newly logged QSO in the cache (avoids re-query)
    func recordQSO(callsign: String, band: String, mode: String, park: String? = nil) {
        let upper = callsign.uppercased()
        // Explode an n-fer so every credited park's spot row crosses out.
        for bmKey in bandModeParkKeys(band: band, mode: mode, park: park) {
            todayWorked[upper, default: []].insert(bmKey)
        }
    }

    /// Clear previous-day cache so next checkCallsigns re-queries from DB
    func invalidateHistory() {
        previousDayWorked.removeAll()
    }

    // MARK: Private

    /// callsign -> band+mode keys worked today
    private var todayWorked: [String: Set<String>] = [:]

    /// callsign -> band+mode keys worked on the previous UTC day (lazy-loaded per callsign)
    private var previousDayWorked: [String: Set<String>] = [:]

    /// Build a composite key from band, mode family, and park reference.
    /// Different parks produce different keys so they're never treated as dupes.
    private func bandModeParkKey(band: String, mode: String, park: String?) -> String {
        let familyKey = switch ModeEquivalence.family(for: mode) {
        case .phone: "PHONE"
        case .cw: "CW"
        case .digital: "DIGITAL"
        case .other: "OTHER"
        }
        let parkKey = park?.uppercased().trimmingCharacters(in: .whitespaces) ?? ""
        return "\(band)|\(familyKey)|\(parkKey)"
    }

    /// Worked keys for a QSO, one per credited park. A comma-separated multi-park
    /// reference (a POTA n-fer, e.g. "US-1044, US-3791") explodes into one
    /// `bandModeParkKey` per park so each park deduplicates independently;
    /// single-park and no-park QSOs return exactly one key, unchanged. Mirrors
    /// Rust `hunter_log::band_mode_park_keys`.
    private func bandModeParkKeys(band: String, mode: String, park: String?) -> [String] {
        guard let park, park.contains(",") else {
            return [bandModeParkKey(band: band, mode: mode, park: park)]
        }
        let parks = park.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).uppercased() }
            .filter { !$0.isEmpty }
        guard !parks.isEmpty else {
            return [bandModeParkKey(band: band, mode: mode, park: park)]
        }
        return parks.map { bandModeParkKey(band: band, mode: mode, park: $0) }
    }
}

/// Build a composite key from band, mode family, and park reference (free function for use outside actor)
func bandModeParkKey(band: String, mode: String, park: String? = nil) -> String {
    let familyKey = switch ModeEquivalence.family(for: mode) {
    case .phone: "PHONE"
    case .cw: "CW"
    case .digital: "DIGITAL"
    case .other: "OTHER"
    }
    let parkKey = park?.uppercased().trimmingCharacters(in: .whitespaces) ?? ""
    return "\(band)|\(familyKey)|\(parkKey)"
}
