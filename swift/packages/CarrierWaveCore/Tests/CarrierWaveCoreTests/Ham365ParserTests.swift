import Testing
@testable import CarrierWaveCore

struct Ham365ParserTests {
    /// Minimal but representative HTML from Ham365.net DXpedition calendar.
    /// Matches real structure: rowspan header cell + class="rotate" on data cells.
    static let sampleHTML = """
    <table>
    <tr>
    <td rowspan="2" class="align-middle text-center">Dx-peditions</td>
    <td class="rotate"><div>Bouvet Is.</div></td>
    <td class="rotate"><div>Crozet Is.</div></td>
    <td class="rotate"><div><img src="onair.gif"/>Heard Is.</div></td>
    </tr>
    <tr>
    <td class="rotate">3Y0K</td>
    <td class="rotate">FT5WQ</td>
    <td class="rotate">VK0HI</td>
    </tr>
    <tr>
    <td class="text-center">color</td>
    <td></td>
    <td></td>
    <td></td>
    </tr>
    <tr>
    <td>DAY</td>
    <td></td>
    <td></td>
    <td></td>
    </tr>
    <tr>
    <td>1</td>
    <td bgcolor="#FF0000"></td>
    <td></td>
    <td bgcolor="#00FF00"></td>
    </tr>
    <tr>
    <td>2</td>
    <td bgcolor="#FF0000"></td>
    <td></td>
    <td></td>
    </tr>
    <tr>
    <td>3</td>
    <td></td>
    <td bgcolor="#0000FF"></td>
    <td></td>
    </tr>
    <tr>
    <td>15</td>
    <td></td>
    <td></td>
    <td bgcolor="#00FF00"></td>
    </tr>
    </table>
    """

    @Test("Parses expedition count")
    func parsesExpeditionCount() {
        let results = Ham365Parser.parse(html: Self.sampleHTML, month: 3, year: 2_026)
        #expect(results.count == 3)
    }

    @Test("Parses callsigns")
    func parsesCallsigns() {
        let results = Ham365Parser.parse(html: Self.sampleHTML, month: 3, year: 2_026)
        let callsigns = results.map(\.callsign)
        #expect(callsigns.contains("3Y0K"))
        #expect(callsigns.contains("FT5WQ"))
        #expect(callsigns.contains("VK0HI"))
    }

    @Test("Parses entity names")
    func parsesEntityNames() {
        let results = Ham365Parser.parse(html: Self.sampleHTML, month: 3, year: 2_026)
        let entities = results.map(\.entity)
        #expect(entities.contains("Bouvet Is."))
        #expect(entities.contains("Crozet Is."))
        #expect(entities.contains("Heard Is."))
    }

    @Test("Parses active days for first expedition")
    func parsesActiveDays() {
        let results = Ham365Parser.parse(html: Self.sampleHTML, month: 3, year: 2_026)
        guard let bouvet = results.first(where: { $0.callsign == "3Y0K" }) else {
            Issue.record("3Y0K not found")
            return
        }
        #expect(bouvet.activeDays == [1, 2])
    }

    @Test("Parses on-air status")
    func parsesOnAirStatus() {
        let results = Ham365Parser.parse(html: Self.sampleHTML, month: 3, year: 2_026)
        let bouvet = results.first { $0.callsign == "3Y0K" }
        let crozet = results.first { $0.callsign == "FT5WQ" }
        let heard = results.first { $0.callsign == "VK0HI" }
        #expect(bouvet?.isOnAir == false)
        #expect(crozet?.isOnAir == false)
        #expect(heard?.isOnAir == true)
    }

    @Test("Sets month and year")
    func setsMonthAndYear() {
        let results = Ham365Parser.parse(html: Self.sampleHTML, month: 3, year: 2_026)
        for expedition in results {
            #expect(expedition.month == 3)
            #expect(expedition.year == 2_026)
        }
    }

    @Test("Date range formatting")
    func dateRange() {
        let expedition = Ham365DXpedition(
            callsign: "3Y0K",
            entity: "Bouvet Is.",
            activeDays: [1, 2, 3, 10, 15],
            isOnAir: false,
            month: 3,
            year: 2_026
        )
        #expect(expedition.dateRange == "Mar 1–15")
    }

    @Test("Date range single day")
    func dateRangeSingleDay() {
        let expedition = Ham365DXpedition(
            callsign: "3Y0K",
            entity: "Bouvet Is.",
            activeDays: [5],
            isOnAir: false,
            month: 7,
            year: 2_026
        )
        #expect(expedition.dateRange == "Jul 5")
    }

    @Test("Empty HTML returns empty array")
    func emptyHTML() {
        let results = Ham365Parser.parse(html: "", month: 1, year: 2_026)
        #expect(results.isEmpty)
    }

    // MARK: - Search Callsigns

    @Test("Simple callsign returns only itself")
    func searchCallsignsSimple() {
        let expedition = Ham365DXpedition(
            callsign: "3Y0K", entity: "Bouvet Is.",
            activeDays: [1], isOnAir: true, month: 3, year: 2_026
        )
        #expect(expedition.searchCallsigns == ["3Y0K"])
    }

    @Test("Slash callsign returns primary plus both parts")
    func searchCallsignsSlash() {
        let expedition = Ham365DXpedition(
            callsign: "PJ7/K1XX", entity: "St. Maarten",
            activeDays: [1], isOnAir: true, month: 1, year: 2_026
        )
        let variants = expedition.searchCallsigns
        #expect(variants.contains("PJ7/K1XX"))
        #expect(variants.contains("K1XX"))
        #expect(variants.contains("PJ7"))
        #expect(variants.count == 3)
    }

    @Test("Portable suffix callsign returns primary plus base")
    func searchCallsignsPortable() {
        let expedition = Ham365DXpedition(
            callsign: "VK0HI/P", entity: "Heard Is.",
            activeDays: [1], isOnAir: true, month: 3, year: 2_026
        )
        let variants = expedition.searchCallsigns
        #expect(variants.contains("VK0HI/P"))
        #expect(variants.contains("VK0HI"))
        #expect(variants.contains("P"))
        #expect(variants.count == 3)
    }

    @Test("Strips HTML entities from entity names")
    func stripsHTMLEntities() {
        let html = """
        <table>
        <tr><td class="rotate"><div>St. Martin &amp; Reef</div></td></tr>
        <tr><td class="rotate">PJ7/K1XX</td></tr>
        <tr><td></td></tr>
        <tr><td>DAY</td></tr>
        <tr><td>1</td><td bgcolor="#FF0000"></td></tr>
        </table>
        """
        let results = Ham365Parser.parse(html: html, month: 1, year: 2_026)
        #expect(results.first?.entity == "St. Martin & Reef")
    }

    @Test("Header cell does not shift entity alignment")
    func headerCellAlignment() {
        let html = """
        <table>
        <tr>
        <td rowspan="2" class="align-middle text-center">Dx-peditions</td>
        <td class="rotate"><div>Macao</div></td>
        <td class="rotate"><div>Bangladesh</div></td>
        </tr>
        <tr>
        <td class="rotate">XX9W</td>
        <td class="rotate">S21WD</td>
        </tr>
        <tr><td></td><td></td><td></td></tr>
        <tr><td>DAY</td><td></td><td></td></tr>
        <tr><td>1</td><td bgcolor="#FF0000"></td><td></td></tr>
        </table>
        """
        let results = Ham365Parser.parse(html: html, month: 3, year: 2_026)
        #expect(results.count == 2)
        let xx9w = results.first { $0.callsign == "XX9W" }
        let s21wd = results.first { $0.callsign == "S21WD" }
        #expect(xx9w?.entity == "Macao")
        #expect(s21wd?.entity == "Bangladesh")
    }
}
