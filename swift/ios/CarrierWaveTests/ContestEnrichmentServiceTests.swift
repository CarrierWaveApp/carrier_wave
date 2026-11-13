import Foundation
import Testing
@testable import CarrierWave

struct ContestEnrichmentServiceTests {
    // MARK: - Mode parsing

    @Test func parsesSingleCWMode() {
        let result = ContestEnrichmentService.enrich(
            title: "CQ WW DX CW",
            description: "Mode: CW<br>Bands: 160, 80, 40, 20, 15, 10m"
        )
        #expect(result.modes == ["CW"])
    }

    @Test func parsesSSBMode() {
        let result = ContestEnrichmentService.enrich(
            title: "CQ WW DX SSB",
            description: "Mode: SSB<br>Bands: All HF"
        )
        #expect(result.modes == ["SSB"])
    }

    @Test func parsesMixedModes() {
        let result = ContestEnrichmentService.enrich(
            title: "ARRL Field Day",
            description: "Modes: CW, SSB, Digital"
        )
        #expect(result.modes.contains("CW"))
        #expect(result.modes.contains("SSB"))
        #expect(result.modes.contains("Digital"))
    }

    // MARK: - Band parsing

    @Test func parsesExplicitBands() {
        let result = ContestEnrichmentService.enrich(
            title: "CQ WW DX CW",
            description: "Bands: 160, 80, 40, 20, 15, 10m"
        )
        #expect(result.bands == ["160m", "80m", "40m", "20m", "15m", "10m"])
    }

    @Test func parsesAllHFSummary() {
        let result = ContestEnrichmentService.enrich(
            title: "CQ WPX",
            description: "Bands: All HF"
        )
        #expect(result.bandSummary == "All HF")
        #expect(result.bands.isEmpty)
    }

    @Test func detectsVHFSummary() {
        let result = ContestEnrichmentService.enrich(
            title: "ARRL VHF Contest",
            description: "Mode: Mixed<br>Bands: 6m and up"
        )
        #expect(result.bandSummary == "VHF+" || result.bands.contains("6m"))
    }

    // MARK: - Exchange parsing

    @Test func parsesExchange() {
        let result = ContestEnrichmentService.enrich(
            title: "CQ WW DX CW",
            description: "Exchange: RST + CQ Zone"
        )
        #expect(result.exchangePreview == "RST + CQ Zone")
    }

    // MARK: - Category inference

    @Test func inferFieldDayCategory() {
        let result = ContestEnrichmentService.enrich(
            title: "ARRL Field Day",
            description: "Mode: Mixed"
        )
        #expect(result.category == .fieldDay)
    }

    @Test func inferSprintCategory() {
        let result = ContestEnrichmentService.enrich(
            title: "NCCC Sprint Ladder",
            description: "Mode: CW"
        )
        #expect(result.category == .sprint)
    }

    @Test func inferQSOPartyCategory() {
        let result = ContestEnrichmentService.enrich(
            title: "Texas State Parks on the Air",
            description: "Exchange: Name + Park"
        )
        // State parks programs surface as QSO-party-like
        #expect(result.category == .qsoParty || result.category == .unknown)
    }

    @Test func inferDXCategory() {
        let result = ContestEnrichmentService.enrich(
            title: "Worked All Provinces of China DX Contest",
            description: "Mode: Mixed"
        )
        #expect(result.category == .dx)
    }

    // MARK: - Popularity

    @Test func cqwwHasTopTier() {
        let result = ContestEnrichmentService.enrich(
            title: "CQ WW DX Contest, CW",
            description: ""
        )
        #expect(result.popularity == 5)
    }

    @Test func arrlDXHasTopTier() {
        let result = ContestEnrichmentService.enrich(
            title: "ARRL DX Contest, CW",
            description: ""
        )
        #expect(result.popularity == 5)
    }

    @Test func nicheContestNoPopularity() {
        let result = ContestEnrichmentService.enrich(
            title: "Some Obscure Club Test",
            description: ""
        )
        #expect(result.popularity == nil)
    }

    // MARK: - Template matching

    @Test func matchesCQWWCWTemplate() {
        let result = ContestEnrichmentService.enrich(
            title: "CQ WW DX Contest, CW",
            description: "Mode: CW",
            templateIds: ["cq-ww-cw", "cq-ww-ssb", "naqp-cw"]
        )
        #expect(result.matchedTemplateId == "cq-ww-cw")
    }

    @Test func matchesFieldDayTemplate() {
        let result = ContestEnrichmentService.enrich(
            title: "ARRL Field Day",
            description: "Modes: CW, SSB, Digital",
            templateIds: ["arrl-field-day", "cq-ww-cw"]
        )
        #expect(result.matchedTemplateId == "arrl-field-day")
    }

    @Test func unmatchedContestHasNoTemplate() {
        let result = ContestEnrichmentService.enrich(
            title: "Holyland Contest",
            description: "Mode: Mixed",
            templateIds: ["cq-ww-cw", "arrl-field-day", "naqp-cw"]
        )
        #expect(result.matchedTemplateId == nil)
    }

    // MARK: - HTML stripping

    @Test func stripsHTMLTags() {
        let result = ContestEnrichmentService.enrich(
            title: "Test",
            description: "<p>Mode: CW</p><br/><b>Bands</b>: 40m"
        )
        #expect(result.modes == ["CW"])
        #expect(result.bands == ["40m"])
    }
}
