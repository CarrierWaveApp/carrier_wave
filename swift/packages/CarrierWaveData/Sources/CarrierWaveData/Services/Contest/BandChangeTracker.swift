import CarrierWaveCore
import Foundation

// MARK: - BandChangeSummary

public struct BandChangeSummary: Sendable, Equatable {
    // MARK: Lifecycle

    public init(
        totalChanges: Int = 0,
        changesPerHour: [Date: Int] = [:],
        violations: [BandChangeViolation] = []
    ) {
        self.totalChanges = totalChanges
        self.changesPerHour = changesPerHour
        self.violations = violations
    }

    // MARK: Public

    public var totalChanges: Int
    /// Count of band changes bucketed by clock-hour (start-of-hour in UTC).
    public var changesPerHour: [Date: Int]
    public var violations: [BandChangeViolation]
}

// MARK: - BandChangeViolation

public enum BandChangeViolation: Sendable, Equatable {
    case tooManyChangesInClockHour(hourStart: Date, count: Int, limit: Int)
    case leftBandTooEarly(band: String, start: Date, duration: TimeInterval, minimum: TimeInterval)
}

// MARK: - BandChangeTracker

/// Evaluates `operating_constraints.band_changes` against a chronological
/// list of QSOs. Facade over `cw_domain::contest::band_change`.
public enum BandChangeTracker {
    public static func summarize(
        qsos: [(band: String, timestamp: Date)],
        categoryID: String?,
        rules: ContestBandChangeRules?
    ) -> BandChangeSummary {
        let ffiRules = rules.map { input in
            FfiBandChangeRulesInput(
                appliesTo: input.appliesTo,
                minMinutesOnBand: input.minMinutesOnBand.map(Int64.init),
                maxChangesPerClockHour: input.maxChangesPerClockHour.map(Int64.init)
            )
        }
        let summary = contestBandChangeSummary(
            qsos: qsos.map { entry in
                FfiContestBandStamp(
                    band: entry.band,
                    timestamp: Int64(entry.timestamp.timeIntervalSince1970)
                )
            },
            categoryId: categoryID,
            rules: ffiRules
        )
        var changesPerHour: [Date: Int] = [:]
        for bucket in summary.changesPerHour {
            changesPerHour[Date(timeIntervalSince1970: TimeInterval(bucket.hourStart))] =
                Int(bucket.count)
        }
        return BandChangeSummary(
            totalChanges: Int(summary.totalChanges),
            changesPerHour: changesPerHour,
            violations: summary.violations.map(BandChangeViolation.init(ffi:))
        )
    }
}

extension BandChangeViolation {
    init(ffi: FfiBandChangeViolation) {
        switch ffi {
        case let .tooManyChangesInClockHour(hourStart, count, limit):
            self = .tooManyChangesInClockHour(
                hourStart: Date(timeIntervalSince1970: TimeInterval(hourStart)),
                count: Int(count),
                limit: Int(limit)
            )
        case let .leftBandTooEarly(band, start, durationSeconds, minimumSeconds):
            self = .leftBandTooEarly(
                band: band,
                start: Date(timeIntervalSince1970: TimeInterval(start)),
                duration: durationSeconds,
                minimum: minimumSeconds
            )
        }
    }
}
