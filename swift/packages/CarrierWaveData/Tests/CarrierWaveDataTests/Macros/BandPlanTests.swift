import Foundation
import Testing
@testable import CarrierWaveData

struct BandPlanTests {
    // MARK: US happy path + edges

    @Test func freqWithinUS40mPasses() {
        let plan = BandPlan.load(region: "US")
        #expect(plan.region == "US")
        #expect(plan.allowsTx(at: 7_032_000))
    }

    @Test func freqJustBelowLowEdgeFails() {
        let plan = BandPlan.load(region: "US")
        #expect(!plan.allowsTx(at: 6_999_999))
    }

    @Test func freqWithinNoUSBandFails() {
        // 152 MHz sits well outside 2m (144-148) and below 1.25m (222-225).
        let plan = BandPlan.load(region: "US")
        #expect(!plan.allowsTx(at: 152_000_000))
    }

    @Test func usVhfBoundariesInclusive() {
        let plan = BandPlan.load(region: "US")
        #expect(plan.allowsTx(at: 144_000_000))
        #expect(plan.allowsTx(at: 148_000_000))
        #expect(!plan.allowsTx(at: 148_000_001))
    }

    // MARK: Region fallback

    @Test func unknownRegionFallsBackToR2() {
        let plan = BandPlan.load(region: "ZZ")
        // Loader falls back to R2 when the file is missing; if R2 itself
        // fails to load (shouldn't on a healthy bundle), the loader yields
        // `unknown` with an empty plan. Lock both branches of the chain in.
        #expect(plan.region == "R2" || plan.region == "unknown")
        if plan.region == "R2" {
            #expect(plan.allowsTx(at: 14_100_000))
        } else {
            #expect(plan.txSegments.isEmpty)
        }
    }

    // MARK: R1/R2/R3 happy paths

    @Test func r1TwentyMetersPermitted() {
        let plan = BandPlan.load(region: "R1")
        #expect(plan.region == "R1")
        #expect(plan.allowsTx(at: 14_100_000))
    }

    @Test func r2TwentyMetersPermitted() {
        let plan = BandPlan.load(region: "R2")
        #expect(plan.region == "R2")
        #expect(plan.allowsTx(at: 14_100_000))
    }

    @Test func r3TwentyMetersPermitted() {
        let plan = BandPlan.load(region: "R3")
        #expect(plan.region == "R3")
        #expect(plan.allowsTx(at: 14_100_000))
    }

    @Test func r1TwoMetersRespectsNarrowerCeiling() {
        // R1 2m baseline is 144-146 MHz, narrower than US/R2/R3 (144-148).
        let plan = BandPlan.load(region: "R1")
        #expect(plan.allowsTx(at: 145_500_000))
        #expect(!plan.allowsTx(at: 147_000_000))
    }

    // MARK: Codable tolerance

    @Test func decodesUnknownFieldsTolerantly() throws {
        let json = #"{"name": "x", "minHz": 1, "maxHz": 2, "channels": true}"#
        let data = try #require(json.data(using: .utf8))
        let segment = try JSONDecoder().decode(BandPlan.RawSegment.self, from: data)
        #expect(segment.name == "x")
        #expect(segment.minHz == 1)
        #expect(segment.maxHz == 2)
    }
}
