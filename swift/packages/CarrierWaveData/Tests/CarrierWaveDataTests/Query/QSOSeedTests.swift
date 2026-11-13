import CarrierWaveData
import Foundation
import Testing

@Suite("QSO mapping")
struct QSOSeedTests {
    @Test("metadata-mode QSOs are skipped")
    func metadataModesSkipped() {
        let weather = QSO(
            callsign: "TEST",
            band: "20m",
            mode: "WEATHER",
            timestamp: Date(),
            myCallsign: "TEST",
            importSource: .logger
        )
        let solar = QSO(
            callsign: "TEST",
            band: "20m",
            mode: "SOLAR",
            timestamp: Date(),
            myCallsign: "TEST",
            importSource: .logger
        )
        let real = QSO(
            callsign: "K1ABC",
            band: "20m",
            mode: "CW",
            timestamp: Date(),
            myCallsign: "TEST",
            importSource: .logger
        )

        #expect(QSOMapper.slimRow(from: weather) == nil)
        #expect(QSOMapper.slimRow(from: solar) == nil)
        #expect(QSOMapper.slimRow(from: real) != nil)
    }

    @Test("preserves slim columns")
    func preservesSlimColumns() {
        let qso = QSO(
            callsign: "K1ABC",
            band: "20m",
            mode: "CW",
            frequency: 14_025.0,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            myCallsign: "TEST",
            myGrid: "FN42",
            theirGrid: "FN31",
            parkReference: "K-1234",
            importSource: .logger,
            dxcc: 291
        )
        guard let row = QSOMapper.slimRow(from: qso) else {
            Issue.record("expected non-nil row")
            return
        }
        #expect(row.callsign == "K1ABC")
        #expect(row.band == "20m")
        #expect(row.mode == "CW")
        #expect(row.frequency == 14_025.0)
        #expect(row.myCallsign == "TEST")
        #expect(row.myGrid == "FN42")
        #expect(row.theirGrid == "FN31")
        #expect(row.parkRef == "K-1234")
        #expect(row.dxcc == 291)
    }
}
