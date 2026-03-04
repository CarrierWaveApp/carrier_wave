import CarrierWaveData
import Foundation
import SwiftData

// MARK: - WorkedBeforeResult

/// Result of a worked-before check for a single callsign
struct WorkedBeforeResult: Sendable {
    static let notWorked = WorkedBeforeResult(
        todayBandModes: [],
        previousBandModes: [],
        isNewDXCC: false
    )

    /// Band+mode-family keys worked today (e.g. "20m|CW", "40m|PHONE")
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

    /// Whether this would be a dupe on the given band and mode family
    func isDupe(on band: String, mode: String) -> Bool {
        todayBandModes.contains(bandModeKey(band: band, mode: mode))
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
        var descriptor = FetchDescriptor<QSO>(predicate: predicate)
        descriptor.fetchLimit = 500

        do {
            let qsos = try context.fetch(descriptor)
            todayWorked.removeAll()
            for qso in qsos {
                let key = qso.callsign.uppercased()
                let bmKey = bandModeKey(band: qso.band, mode: qso.mode)
                todayWorked[key, default: []].insert(bmKey)
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
            var descriptor = FetchDescriptor<QSO>(predicate: predicate)
            descriptor.fetchLimit = 50

            let bandModes: Set<String> = if let qsos = try? context.fetch(descriptor) {
                Set(qsos.map { bandModeKey(band: $0.band, mode: $0.mode) })
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
    func recordQSO(callsign: String, band: String, mode: String) {
        let upper = callsign.uppercased()
        let bmKey = bandModeKey(band: band, mode: mode)
        todayWorked[upper, default: []].insert(bmKey)
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

    /// Build a composite key from band and mode family
    private func bandModeKey(band: String, mode: String) -> String {
        let familyKey = switch ModeEquivalence.family(for: mode) {
        case .phone: "PHONE"
        case .cw: "CW"
        case .digital: "DIGITAL"
        case .other: "OTHER"
        }
        return "\(band)|\(familyKey)"
    }
}

/// Build a composite key from band and mode family (free function for use outside actor)
func bandModeKey(band: String, mode: String) -> String {
    let familyKey = switch ModeEquivalence.family(for: mode) {
    case .phone: "PHONE"
    case .cw: "CW"
    case .digital: "DIGITAL"
    case .other: "OTHER"
    }
    return "\(band)|\(familyKey)"
}
