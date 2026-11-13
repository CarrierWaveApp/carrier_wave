import Foundation

// MARK: - BandPlan

/// Region-aware TX-permitted segments consumed by the macro safety gate.
///
/// Loaded from `Resources/band-plans/<region>.json`. The plans are the
/// baseline union of amateur TX allocations for that region — they may be
/// more permissive than any single country's license. The safety gate uses
/// them as a coarse refusal floor; tighter per-country/per-license-class
/// checks are deferred to a future iteration.
public struct BandPlan: Sendable {
    // MARK: Lifecycle

    public init(region: String, txSegments: [Segment]) {
        self.region = region
        self.txSegments = txSegments
    }

    // MARK: Public

    /// A contiguous TX-permitted frequency range, inclusive on both ends.
    public struct Segment: Sendable {
        // MARK: Lifecycle

        public init(minHz: UInt64, maxHz: UInt64, name: String) {
            self.minHz = minHz
            self.maxHz = maxHz
            self.name = name
        }

        // MARK: Public

        public let minHz: UInt64
        public let maxHz: UInt64
        public let name: String
    }

    public let region: String
    public let txSegments: [Segment]

    /// Synchronous lookup against the bundled tables. Falls back to `R2`
    /// (the broadest reasonable default) on miss; if that also fails,
    /// returns an empty `"unknown"` plan so callers degrade safely rather
    /// than crash.
    public static func load(region: String) -> BandPlan {
        if let plan = loadRaw(region: region) {
            return plan
        }
        if region != "R2", let fallback = loadRaw(region: "R2") {
            return fallback
        }
        return BandPlan(region: "unknown", txSegments: [])
    }

    /// Returns `true` iff `hz` falls inside any TX-permitted segment.
    public func allowsTx(at hertz: UInt64) -> Bool {
        txSegments.contains { segment in
            hertz >= segment.minHz && hertz <= segment.maxHz
        }
    }

    // MARK: Internal

    /// Decode helper that ignores unknown JSON fields (e.g. `"channels": true`
    /// on the US 60m entry). Synthesized `Codable` already drops unknown keys
    /// by default — `BandPlanTests.decodesUnknownFieldsTolerantly` locks that
    /// behavior in.
    struct RawSegment: Decodable {
        let name: String
        let minHz: UInt64
        let maxHz: UInt64
    }

    struct RawPlan: Decodable {
        let region: String
        let txSegments: [RawSegment]
    }

    // MARK: Private

    private static func loadRaw(region: String) -> BandPlan? {
        guard
            let url = Bundle.module.url(
                forResource: "band-plans/\(region)",
                withExtension: "json"
            ),
            let data = try? Data(contentsOf: url),
            let raw = try? JSONDecoder().decode(RawPlan.self, from: data)
        else {
            return nil
        }
        let segments = raw.txSegments.map { seg in
            Segment(minHz: seg.minHz, maxHz: seg.maxHz, name: seg.name)
        }
        return BandPlan(region: raw.region, txSegments: segments)
    }
}
