import Foundation
import SwiftData

// MARK: - WorkedBeforeResult

/// Result of a worked-before check for a single callsign
struct WorkedBeforeResult: Sendable {
    static let notWorked = WorkedBeforeResult(
        todayBands: [],
        previousBands: [],
        isNewDXCC: false
    )

    /// Bands worked today
    let todayBands: Set<String>

    /// Bands worked on the previous UTC day
    let previousBands: Set<String>

    /// Whether this is a new DXCC entity
    let isNewDXCC: Bool

    /// Whether this callsign has been worked at all
    var hasBeenWorked: Bool {
        !todayBands.isEmpty || !previousBands.isEmpty
    }

    /// Whether this would be a dupe on the given band
    func isDupe(on band: String) -> Bool {
        todayBands.contains(band)
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
            !qso.isHidden && qso.timestamp >= startOfDay
        }
        var descriptor = FetchDescriptor<QSO>(predicate: predicate)
        descriptor.fetchLimit = 500

        do {
            let qsos = try context.fetch(descriptor)
            todayWorked.removeAll()
            for qso in qsos {
                let key = qso.callsign.uppercased()
                todayWorked[key, default: []].insert(qso.band)
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
                    && qso.timestamp >= startOfYesterday
                    && qso.timestamp < startOfToday
            }
            var descriptor = FetchDescriptor<QSO>(predicate: predicate)
            descriptor.fetchLimit = 50

            let bands: Set<String> = if let qsos = try? context.fetch(descriptor) {
                Set(qsos.map(\.band))
            } else {
                []
            }
            previousDayWorked[upper] = bands
        }
    }

    /// Get the worked-before result for a callsign on a given band
    func result(for callsign: String, band: String) -> WorkedBeforeResult {
        let upper = callsign.uppercased()
        let today = todayWorked[upper] ?? []
        let previousDay = previousDayWorked[upper] ?? []

        // DXCC checking is deferred to Phase 3
        return WorkedBeforeResult(
            todayBands: today,
            previousBands: previousDay,
            isNewDXCC: false
        )
    }

    /// Record a newly logged QSO in the cache (avoids re-query)
    func recordQSO(callsign: String, band: String) {
        let upper = callsign.uppercased()
        todayWorked[upper, default: []].insert(band)
    }

    /// Clear previous-day cache so next checkCallsigns re-queries from DB
    func invalidateHistory() {
        previousDayWorked.removeAll()
    }

    // MARK: Private

    /// callsign -> bands worked today
    private var todayWorked: [String: Set<String>] = [:]

    /// callsign -> bands worked on the previous UTC day (lazy-loaded per callsign)
    private var previousDayWorked: [String: Set<String>] = [:]
}
