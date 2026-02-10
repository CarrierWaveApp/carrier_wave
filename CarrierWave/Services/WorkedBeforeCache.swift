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

    /// Bands worked historically (not today)
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

    /// Check a batch of callsigns against historical data
    func checkCallsigns(
        _ callsigns: [String],
        container: ModelContainer
    ) async {
        // Only look up callsigns we haven't checked yet
        let unchecked = callsigns.filter { allTimeWorked[$0.uppercased()] == nil }
        guard !unchecked.isEmpty else {
            return
        }

        let context = ModelContext(container)
        context.autosaveEnabled = false

        for callsign in unchecked {
            let upper = callsign.uppercased()
            let predicate = #Predicate<QSO> { qso in
                qso.callsign == upper && !qso.isHidden
            }
            var descriptor = FetchDescriptor<QSO>(predicate: predicate)
            descriptor.fetchLimit = 50

            let bands: Set<String> = if let qsos = try? context.fetch(descriptor) {
                Set(qsos.map(\.band))
            } else {
                []
            }
            allTimeWorked[upper] = bands
        }
    }

    /// Get the worked-before result for a callsign on a given band
    func result(for callsign: String, band: String) -> WorkedBeforeResult {
        let upper = callsign.uppercased()
        let today = todayWorked[upper] ?? []
        let allTime = allTimeWorked[upper] ?? []

        // Historical bands = all-time minus today
        let previous = allTime.subtracting(today)

        // DXCC checking is deferred to Phase 3
        return WorkedBeforeResult(
            todayBands: today,
            previousBands: previous,
            isNewDXCC: false
        )
    }

    /// Record a newly logged QSO in the cache (avoids re-query)
    func recordQSO(callsign: String, band: String) {
        let upper = callsign.uppercased()
        todayWorked[upper, default: []].insert(band)
        allTimeWorked[upper, default: []].insert(band)
    }

    // MARK: Private

    /// callsign -> bands worked today
    private var todayWorked: [String: Set<String>] = [:]

    /// callsign -> all bands ever worked (lazy-loaded per callsign)
    private var allTimeWorked: [String: Set<String>] = [:]
}
