import Testing
@testable import CWSweep

struct JttyMacroExpanderTests {
    // MARK: Internal

    @Test("Shipped defaults expand exactly as the WSJT-X user guide shows")
    func defaultsMatchUserGuide() {
        let expected = [
            "CQ K1ABC CQ",
            "W9XYZ 599 107",
            "W9XYZ TU CQ K1ABC CQ",
            "K1ABC",
            "W9XYZ",
            "TU NOW W7UVW 599 108",
            "W9XYZ AGN?",
            "599 107",
        ]
        for (slot, template) in JttyMacroExpander.defaultTemplates.enumerated() {
            #expect(JttyMacroExpander.expand(template, context: context) == expected[slot], "F\(slot + 1)")
        }
    }

    @Test("Serials render with at least three digits")
    func serialPadding() {
        var small = context
        small.serial = 5
        #expect(JttyMacroExpander.expand("%E", context: small) == "599 005")
        #expect(JttyMacroExpander.expand("%N", context: small) == "005")
        small.serial = 12_345
        #expect(JttyMacroExpander.expand("%N", context: small) == "12345")
    }

    @Test("Field Day and RTTY Roundup profiles use the exchange field")
    func profileExchanges() {
        var fieldDay = context
        fieldDay.profile = .fieldDay
        fieldDay.exchange = "1d ema"
        #expect(JttyMacroExpander.expand("%H %E", context: fieldDay) == "W9XYZ 1D EMA")

        var roundup = context
        roundup.profile = .rttyRoundup
        roundup.exchange = "ma"
        #expect(JttyMacroExpander.expand("%E", context: roundup) == "599 MA")
        roundup.exchange = ""
        #expect(JttyMacroExpander.expand("%E", context: roundup) == "599 107")
    }

    @Test("Expansion upper-cases and collapses whitespace")
    func normalisation() {
        var lower = context
        lower.hisCall = "w9xyz"
        #expect(JttyMacroExpander.expand("  %H   agn?  ", context: lower) == "W9XYZ AGN?")
        #expect(JttyMacroExpander.normalize("cq\tcq  de\nk1abc") == "CQ CQ DE K1ABC")
    }

    @Test("Missing operator fields are reported per template")
    func missingFields() {
        let empty = JttyMacroContext()
        #expect(JttyMacroExpander.missingFields("CQ %M CQ", context: empty) == ["my callsign"])
        #expect(JttyMacroExpander.missingFields("%H %E", context: empty) == ["his callsign"])
        #expect(JttyMacroExpander.missingFields("TU NOW %Q %E", context: empty) == ["queued callsign"])
        var fieldDay = empty
        fieldDay.profile = .fieldDay
        #expect(JttyMacroExpander.missingFields("%E", context: fieldDay) == ["exchange"])
        #expect(JttyMacroExpander.missingFields("%E", context: empty).isEmpty)
        #expect(JttyMacroExpander.missingFields("CQ %M CQ", context: context).isEmpty)
    }

    @Test("Callsign tokens are picked out of received text")
    func callsignTokens() {
        #expect(JttyService.callsigns(in: "CQ K1ABC CQ") == ["K1ABC"])
        #expect(JttyService.callsigns(in: "W9XYZ 599 107") == ["W9XYZ"])
        #expect(JttyService.callsigns(in: "TU NOW W7UVW 599 108") == ["W7UVW"])
        #expect(JttyService.callsigns(in: "ONLY DECODED YOUR FIRST CQ").isEmpty)
        #expect(JttyService.callsigns(in: "VE3ABC/W4 DE K1ABC") == ["VE3ABC/W4", "K1ABC"])
    }

    // MARK: Private

    /// WSJT-X's user-guide table: K1ABC running, W9XYZ worked, W7UVW queued, serial 107.
    private var context: JttyMacroContext {
        JttyMacroContext(myCall: "K1ABC", hisCall: "W9XYZ", queuedCall: "W7UVW", serial: 107)
    }
}
