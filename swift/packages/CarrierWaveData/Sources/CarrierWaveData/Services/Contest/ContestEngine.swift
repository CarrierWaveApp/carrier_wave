import CarrierWaveCore
import Foundation

// MARK: - ContestEngine

/// Scoring, dupe, and multiplier engine for server-defined contest
/// definitions (format v0.3). Facade over the Rust `ContestEngineApi`
/// (`cw_domain::contest::engine`) — all scoring behavior lives in the core;
/// this actor owns the instance and converts value types at the boundary.
public actor ContestEngine {
    // MARK: Lifecycle

    public init(
        definition: ContestDefinition,
        myStation: MyStationContext? = nil,
        startingSerial: Int = 0
    ) {
        self.definition = definition
        self.myStation = myStation
        guard let api = try? ContestEngineApi.fromJson(
            definitionJson: definition.rawJson,
            myStation: myStation?.ffi,
            startingSerial: Int64(startingSerial)
        ) else {
            // `rawJson` is produced by the Rust parser itself, so a re-parse
            // failure means the binary and the cache disagree — unrecoverable.
            preconditionFailure("Contest definition failed to parse: \(definition.id)")
        }
        self.api = api
    }

    // MARK: Public

    public let definition: ContestDefinition

    /// The operator's own station context, used to evaluate `my_*` fields.
    public private(set) var myStation: MyStationContext?

    public func setMyStation(_ context: MyStationContext?) {
        myStation = context
        api.setMyStation(station: context?.ffi)
    }

    /// Check whether a prospective QSO would be a dupe. O(1).
    public func dupeStatus(
        callsign: String,
        band: String,
        mode: String = "CW"
    ) -> ContestDupeStatus {
        ContestDupeStatus(ffi: api.dupeStatus(callsign: callsign, band: band, mode: mode))
    }

    /// Peek at next-sent serial without incrementing.
    public func currentSerial() -> Int {
        Int(api.currentSerial())
    }

    /// Increment and return the next serial to send.
    public func nextSerial() -> Int {
        Int(api.nextSerial())
    }

    /// Suggest received-exchange values based on a prior QSO with the same
    /// callsign on another band (useful in multi-band contests).
    public func suggestedExchange(for callsign: String) -> [String: String]? {
        api.suggestedExchange(callsign: callsign)
    }

    /// Register a completed QSO — updates dupe table, multipliers, phase
    /// totals, and returns the resulting status for UI feedback.
    @discardableResult
    public func registerQSO(_ record: ContestQSORecord) -> ContestDupeStatus {
        ContestDupeStatus(ffi: api.registerQso(input: record.ffiInput))
    }

    /// Current score snapshot (recomputes aggregate phases from running totals).
    public func scoreSnapshot() -> ContestScoreSnapshot {
        ContestScoreSnapshot(ffi: api.scoreSnapshot())
    }

    /// QSO rate over the last N minutes.
    public func rate(overMinutes minutes: Int = 60) -> Double {
        api.rate(overMinutes: Int64(minutes), now: Int64(Date().timeIntervalSince1970))
    }

    /// Bucketed time series for the rate graph.
    public func rateTimeSeries(bucketMinutes: Int = 60) -> [RateBucket] {
        api.rateTimeSeries(
            bucketMinutes: Int64(bucketMinutes),
            now: Int64(Date().timeIntervalSince1970)
        )
        .map { bucket in
            RateBucket(
                date: Date(timeIntervalSince1970: TimeInterval(bucket.date)),
                count: Int(bucket.count)
            )
        }
    }

    /// Full rescore from a chronologically-sorted QSO list. Used after edits.
    public func rescore(_ records: [ContestQSORecord]) {
        api.rescore(records: records.map(\.ffiInput))
    }

    /// Load already-logged QSOs at session start (same semantics as rescore).
    public func loadExistingQSOs(_ records: [ContestQSORecord]) {
        rescore(records)
    }

    // MARK: Private

    private let api: ContestEngineApi
}

// MARK: - RateBucket

public struct RateBucket: Sendable {
    public var date: Date
    public var count: Int
}
