import CarrierWaveCore
import Foundation

// MARK: - ContestOccurrence

public struct ContestOccurrence: Sendable, Equatable {
    // MARK: Lifecycle

    public init(start: Date, end: Date) {
        self.start = start
        self.end = end
    }

    init(ffi: FfiContestOccurrence) {
        start = Date(timeIntervalSince1970: TimeInterval(ffi.start))
        end = Date(timeIntervalSince1970: TimeInterval(ffi.end))
    }

    // MARK: Public

    public var start: Date
    public var end: Date

    public var duration: TimeInterval {
        end.timeIntervalSince(start)
    }

    public func contains(_ date: Date) -> Bool {
        date >= start && date < end
    }
}

// MARK: - ContestScheduleEvaluator

/// Computes concrete start/end dates for a `ContestSchedule`, given a
/// reference date. Facade over `cw_domain::contest::schedule`.
public enum ContestScheduleEvaluator {
    /// The currently-active occurrence (if any) at `now`.
    public static func activeOccurrence(
        schedule: ContestSchedule,
        now: Date = Date()
    ) -> ContestOccurrence? {
        guard let occurrence = try? contestActiveOccurrence(
            definitionJson: schedule.rawJson,
            now: Int64(now.timeIntervalSince1970)
        ) else {
            return nil
        }
        return ContestOccurrence(ffi: occurrence)
    }

    /// The next upcoming occurrence after `now`, if any.
    public static func nextOccurrence(
        schedule: ContestSchedule,
        now: Date = Date()
    ) -> ContestOccurrence? {
        guard let occurrence = try? contestNextOccurrence(
            definitionJson: schedule.rawJson,
            now: Int64(now.timeIntervalSince1970)
        ) else {
            return nil
        }
        return ContestOccurrence(ffi: occurrence)
    }

    /// Candidate occurrences around `now` (up to ~1 year before + after).
    public static func occurrences(
        schedule: ContestSchedule,
        around now: Date
    ) -> [ContestOccurrence] {
        let occurrences = (try? contestOccurrences(
            definitionJson: schedule.rawJson,
            now: Int64(now.timeIntervalSince1970)
        )) ?? []
        return occurrences.map(ContestOccurrence.init(ffi:))
    }
}
