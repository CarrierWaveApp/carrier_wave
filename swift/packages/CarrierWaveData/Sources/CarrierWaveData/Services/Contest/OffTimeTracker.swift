import CarrierWaveCore
import Foundation

// MARK: - OffTimeSummary

public struct OffTimeSummary: Sendable, Equatable {
    // MARK: Lifecycle

    public init(
        totalOnAirSeconds: TimeInterval = 0,
        totalOffSeconds: TimeInterval = 0,
        offPeriods: [OffPeriod] = [],
        violations: [OffTimeViolation] = [],
        remainingOnAirSeconds: TimeInterval? = nil
    ) {
        self.totalOnAirSeconds = totalOnAirSeconds
        self.totalOffSeconds = totalOffSeconds
        self.offPeriods = offPeriods
        self.violations = violations
        self.remainingOnAirSeconds = remainingOnAirSeconds
    }

    // MARK: Public

    public var totalOnAirSeconds: TimeInterval
    public var totalOffSeconds: TimeInterval
    public var offPeriods: [OffPeriod]
    public var violations: [OffTimeViolation]
    /// How much on-air time remains under the selected category's cap, if any.
    public var remainingOnAirSeconds: TimeInterval?
}

// MARK: - OffPeriod

public struct OffPeriod: Sendable, Equatable {
    // MARK: Lifecycle

    public init(start: Date, end: Date) {
        self.start = start
        self.end = end
    }

    // MARK: Public

    public var start: Date
    public var end: Date

    public var duration: TimeInterval {
        end.timeIntervalSince(start)
    }
}

// MARK: - OffTimeViolation

public enum OffTimeViolation: Sendable, Equatable {
    case offPeriodTooShort(start: Date, duration: TimeInterval, minimum: TimeInterval)
    case exceededMaxOnAirTime(actual: TimeInterval, allowed: TimeInterval)
}

// MARK: - OffTimeTracker

/// Evaluates session-long off-time compliance against a contest's
/// `operating_constraints.off_time` rules. Facade over
/// `cw_domain::contest::off_time`.
public enum OffTimeTracker {
    public static func summarize(
        qsoTimestamps: [Date],
        sessionStart: Date,
        sessionEnd: Date? = nil,
        categoryID: String? = nil,
        rules: ContestOffTimeRules?
    ) -> OffTimeSummary {
        let ffiRules = rules.map { input in
            FfiOffTimeRulesInput(
                minimumOffMinutes: input.minimumOffMinutes.map(Int64.init),
                maximumOnHoursByCategory: input.maximumOnHoursByCategory
            )
        }
        let summary = contestOffTimeSummary(
            qsoTimestamps: qsoTimestamps.map { Int64($0.timeIntervalSince1970) },
            sessionStart: Int64(sessionStart.timeIntervalSince1970),
            sessionEnd: Int64((sessionEnd ?? Date()).timeIntervalSince1970),
            categoryId: categoryID,
            rules: ffiRules
        )
        return OffTimeSummary(
            totalOnAirSeconds: summary.totalOnAirSeconds,
            totalOffSeconds: summary.totalOffSeconds,
            offPeriods: summary.offPeriods.map { period in
                OffPeriod(
                    start: Date(timeIntervalSince1970: TimeInterval(period.start)),
                    end: Date(timeIntervalSince1970: TimeInterval(period.end))
                )
            },
            violations: summary.violations.map(OffTimeViolation.init(ffi:)),
            remainingOnAirSeconds: summary.remainingOnAirSeconds
        )
    }
}

extension OffTimeViolation {
    init(ffi: FfiOffTimeViolation) {
        switch ffi {
        case let .offPeriodTooShort(start, durationSeconds, minimumSeconds):
            self = .offPeriodTooShort(
                start: Date(timeIntervalSince1970: TimeInterval(start)),
                duration: durationSeconds,
                minimum: minimumSeconds
            )
        case let .exceededMaxOnAirTime(actualSeconds, allowedSeconds):
            self = .exceededMaxOnAirTime(actual: actualSeconds, allowed: allowedSeconds)
        }
    }
}
