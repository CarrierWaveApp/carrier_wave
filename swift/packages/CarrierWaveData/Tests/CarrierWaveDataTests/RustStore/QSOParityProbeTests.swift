import Testing
@testable import CarrierWaveData

// MARK: - QSOParityProbeTests

struct QSOParityProbeTests {
    @Test func sweepClassifiesMatchSupersetAndMismatch() {
        let probe = QSOParityProbe()
        // identical
        #expect(probe.compareQuery(query: "band:20m", swiftDataIDs: ["a", "b"], rustIDs: ["a", "b"]).status == .match)
        // Rust superset because Swift's batch window truncated (rust has extra trailing ids)
        #expect(probe.compareQuery(query: "x", swiftDataIDs: ["a"], rustIDs: ["a", "b"])
            .status == .rustSupersetLikelyBatchWindow)
        // genuine mismatch (different ids, not a tail extension)
        #expect(probe.compareQuery(query: "y", swiftDataIDs: ["a", "c"], rustIDs: ["a", "b"]).status == .mismatch)
    }
}
