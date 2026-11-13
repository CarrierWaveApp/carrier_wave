import CarrierWaveData
import Testing

@Suite("QSOMode metadata classification")
struct QSOModeTests {
    /// CAR-278: every PoLo "Their Call" command that lands in the log as a
    /// QSO-shaped row must be classified as metadata so it never counts as a
    /// pending upload.
    @Test("all PoLo marker modes are metadata", arguments: [
        "WEATHER", "SOLAR", "NOTE", "TODO", "START", "BREAK",
    ])
    func poloMarkersAreMetadata(mode: String) {
        #expect(QSOMode.isMetadata(mode))
        #expect(QSOMode.metadataModes.contains(mode))
    }

    @Test("classification is case-insensitive", arguments: [
        "weather", "Solar", "note", "Break", "start", "todo",
    ])
    func caseInsensitive(mode: String) {
        #expect(QSOMode.isMetadata(mode))
    }

    @Test("real modes are not metadata", arguments: [
        "CW", "SSB", "FT8", "FT4", "RTTY", "FM", "AM", "PHONE", "DATA", "",
    ])
    func realModesAreNotMetadata(mode: String) {
        #expect(!QSOMode.isMetadata(mode))
    }

    @Test("metadataModes are stored uppercase")
    func storedUppercase() {
        for mode in QSOMode.metadataModes {
            #expect(mode == mode.uppercased())
        }
    }
}
