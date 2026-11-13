import CarrierWaveCore
import CarrierWaveData
import Foundation
import SwiftData

/// Checks whether a callsign+band+mode combo has been worked in the current UTC day.
/// Caches today's QSOs for O(1) lookup after initial load.
@MainActor
@Observable
final class ClusterWorkedBeforeChecker {
    // MARK: Internal

    /// Set of worked keys: "CALLSIGN|band|modeFamily"
    private(set) var workedKeys = Set<String>()
    private(set) var isLoaded = false

    /// Load today's QSOs from SwiftData. Call once on appear and periodically.
    func loadToday(container: ModelContainer) async {
        let context = ModelContext(container)
        let startOfDay = utcStartOfDay()

        let predicate = #Predicate<QSO> { qso in
            qso.timestamp >= startOfDay && !qso.isHidden
        }

        var keys = Set<String>()
        var seenUUIDs = Set<UUID>()
        var offset = 0

        do {
            while true {
                let descriptor = BoundedDescriptor<QSO>(
                    predicate: predicate,
                    limit: BoundedDescriptor<QSO>.maxLimit,
                    offset: offset
                )
                let batch = try context.boundedFetch(descriptor)
                if batch.isEmpty {
                    break
                }

                for qso in batch {
                    guard seenUUIDs.insert(qso.id).inserted else {
                        continue
                    }
                    let key = makeKey(
                        callsign: qso.callsign,
                        band: qso.band,
                        mode: qso.mode
                    )
                    keys.insert(key)
                }

                offset += batch.count
            }
        } catch {
            // Silently fail — checker is optional enrichment
        }

        workedKeys = keys
        isLoaded = true
    }

    /// Record a new QSO without re-querying the database
    func recordQSO(callsign: String, band: String, mode: String) {
        let key = makeKey(callsign: callsign, band: band, mode: mode)
        workedKeys.insert(key)
    }

    /// Check if a spot has been worked today on the same band and mode family
    func isWorked(callsign: String, band: String, mode: String) -> Bool {
        let key = makeKey(callsign: callsign, band: band, mode: mode)
        return workedKeys.contains(key)
    }

    // MARK: Private

    private func makeKey(callsign: String, band: String, mode: String) -> String {
        let family = ModeEquivalence.family(for: mode)
        let familyStr = switch family {
        case .cw: "CW"
        case .phone: "PHONE"
        case .digital: "DIGITAL"
        case .other: "OTHER"
        }
        return "\(callsign.uppercased())|\(band)|\(familyStr)"
    }

    private func utcStartOfDay() -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.startOfDay(for: Date())
    }
}
