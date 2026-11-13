import Testing
@testable import CWSweep

struct VimFilterParserTests {
    @Test func parseModeFilter() {
        let result = VimFilterParser.parse("cw")
        #expect(result.modeFilter == "CW")
    }

    @Test func parseBandFilter() {
        let result = VimFilterParser.parse("20m")
        #expect(result.bandFilter == "20M")
    }

    @Test func parseSourceFilter() {
        let result = VimFilterParser.parse("pota")
        #expect(result.sourceFilter == "POTA")
    }

    @Test func parseNeededFilter() {
        let result = VimFilterParser.parse("new")
        #expect(result.neededOnly == true)
    }

    @Test func parseDupeFilter() {
        let result = VimFilterParser.parse("dupe")
        #expect(result.dupeOnly == true)
    }

    @Test func parseCombined() {
        let result = VimFilterParser.parse("cw 20m new")
        #expect(result.modeFilter == "CW")
        #expect(result.bandFilter == "20M")
        #expect(result.neededOnly == true)
    }

    @Test func parseCallsignPrefix() {
        let result = VimFilterParser.parse("ja")
        #expect(result.callsignPrefix == "JA")
    }

    @Test func disambiguateWithCallPrefix() {
        let result = VimFilterParser.parse("call:cw")
        #expect(result.callsignPrefix == "CW")
        #expect(result.modeFilter == nil)
    }

    @Test func disambiguateWithModePrefix() {
        let result = VimFilterParser.parse("mode:ssb")
        #expect(result.modeFilter == "SSB")
    }

    @Test func parseBandNeedFilter() {
        let result = VimFilterParser.parse("need:40m")
        #expect(result.neededOnBand == "40M")
    }

    @Test func parseModeNeedFilter() {
        let result = VimFilterParser.parse("need:cw")
        #expect(result.neededOnMode == "CW")
    }

    @Test func emptyInput() {
        let result = VimFilterParser.parse("")
        #expect(result.isEmpty)
    }

    @Test func multipleCallsignTokensUsesLast() {
        let result = VimFilterParser.parse("cw w4")
        #expect(result.modeFilter == "CW")
        #expect(result.callsignPrefix == "W4")
    }
}
