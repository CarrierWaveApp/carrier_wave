import Testing
@testable import CarrierWaveCore

@Suite("AntennaDescriptionParser")
struct AntennaDescriptionParserTests {
    @Test("Known model: TCI 530")
    func tci530() {
        let result = AntennaDescriptionParser.parse("TCI 530 Omni Log Periodic")
        #expect(result.type == .logPeriodic)
        #expect(result.modelName == "TCI 530")
        #expect(result.directionality == "omni")
    }

    @Test("Known model: ALA1530 active loop")
    func ala1530() {
        let result = AntennaDescriptionParser.parse("ALA1530 active loop")
        #expect(result.type == .loop)
        #expect(result.modelName == "ALA1530")
        #expect(result.directionality == "omni")
    }

    @Test("Known model: Mini-Whip")
    func miniWhip() {
        let result = AntennaDescriptionParser.parse("Mini-Whip on 10m mast")
        #expect(result.type == .whip)
        #expect(result.modelName == "Mini-Whip")
        #expect(result.directionality == "omni")
    }

    @Test("Known model: W6LVP loop")
    func w6lvp() {
        let result = AntennaDescriptionParser.parse("W6LVP Magnetic Loop")
        #expect(result.type == .loop)
        #expect(result.modelName == "W6LVP")
    }

    @Test("Type keyword: dipole with band")
    func dipoleWithBand() {
        let result = AntennaDescriptionParser.parse("80m dipole")
        #expect(result.type == .dipole)
        #expect(result.bands == ["80m"])
    }

    @Test("Type keyword: vertical with frequency")
    func verticalWithFrequency() {
        let result = AntennaDescriptionParser.parse(
            "5/8th Vertical with masthead preamp for 28MHz"
        )
        #expect(result.type == .vertical)
        // "28MHz" alone doesn't match the MHz range pattern (needs X-Y MHz)
        // but "28" doesn't match band pattern either since it's followed by "MHz" not "m"
    }

    @Test("Band extraction: multiple explicit bands")
    func multipleBands() {
        let result = AntennaDescriptionParser.parse(
            "Parallel dipoles for 160m, 80m, 60m & 40m"
        )
        #expect(result.type == .dipole)
        #expect(result.bands == ["160m", "80m", "60m", "40m"])
    }

    @Test("Band extraction: MHz range covering all HF")
    func mhzRangeAllHF() {
        let result = AntennaDescriptionParser.parse("Active E-field antenna 0.01-30MHz")
        #expect(result.bands.contains("160m"))
        #expect(result.bands.contains("80m"))
        #expect(result.bands.contains("40m"))
        #expect(result.bands.contains("20m"))
        #expect(result.bands.contains("10m"))
    }

    @Test("Band extraction: partial MHz range")
    func mhzRangePartial() {
        let result = AntennaDescriptionParser.parse("Loop 3-15MHz")
        #expect(result.bands.contains("80m"))
        #expect(result.bands.contains("40m"))
        #expect(result.bands.contains("30m"))
        #expect(!result.bands.contains("160m"))
        // 14.0 MHz (20m) overlaps with 3-15 MHz range
        #expect(result.bands.contains("20m"))
    }

    @Test("Directionality: broadside N/S")
    func broadsideNS() {
        let result = AntennaDescriptionParser.parse("Inverted-V, broadside N/S")
        #expect(result.type == .dipole)
        #expect(result.directionality == "N/S")
    }

    @Test("Directionality: omni")
    func omni() {
        let result = AntennaDescriptionParser.parse("Vertical, omnidirectional")
        #expect(result.type == .vertical)
        #expect(result.directionality == "omni")
    }

    @Test("Directionality: directional")
    func directional() {
        let result = AntennaDescriptionParser.parse("3-element yagi, directional")
        #expect(result.type == .yagi)
        #expect(result.directionality == "directional")
    }

    @Test("Empty description")
    func emptyDescription() {
        let result = AntennaDescriptionParser.parse("")
        #expect(result.type == nil)
        #expect(result.bands.isEmpty)
        #expect(result.directionality == nil)
        #expect(result.modelName == nil)
    }

    @Test("Unknown description")
    func unknownDescription() {
        let result = AntennaDescriptionParser.parse("Something unusual")
        #expect(result.type == nil)
        #expect(result.bands.isEmpty)
    }

    @Test("Log periodic keyword")
    func logPeriodic() {
        let result = AntennaDescriptionParser.parse("LPDA 2-30MHz")
        #expect(result.type == .logPeriodic)
        #expect(!result.bands.isEmpty)
    }

    @Test("End-fed antenna")
    func endFed() {
        let result = AntennaDescriptionParser.parse("EFHW 40m end-fed half-wave")
        #expect(result.type == .endFed)
        #expect(result.bands == ["40m"])
    }

    @Test("Bands sorted by frequency order")
    func bandsSorted() {
        let result = AntennaDescriptionParser.parse("Dipole for 20m, 40m, 80m")
        #expect(result.bands == ["80m", "40m", "20m"])
    }

    @Test("T2FD known model")
    func t2fd() {
        let result = AntennaDescriptionParser.parse("T2FD 2-30MHz")
        #expect(result.type == .dipole)
        #expect(result.modelName == "T2FD")
    }

    @Test("Raw description preserved")
    func rawDescriptionPreserved() {
        let input = "  TCI 530 Omni Log Periodic  "
        let result = AntennaDescriptionParser.parse(input)
        #expect(result.rawDescription == input)
    }
}
