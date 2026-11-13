import CarrierWaveCore
import CarrierWaveData
import Foundation
import SwiftData
import Testing
@testable import CWSweep

// MARK: - Fixtures

private let satRecord = "<CALL:5>W1ABC<QSO_DATE:8>20260926<TIME_ON:6>142233<BAND:2>2m<BAND_RX:4>70cm"
    + "<FREQ:9>145.99000<FREQ_RX:9>435.30000<MODE:2>FM<SAT_NAME:5>AO-91<PROP_MODE:3>SAT"
    + "<STATION_CALLSIGN:5>W6JSV<MY_GRIDSQUARE:6>CM87xx<eor>"

private let secondRecord = "<CALL:4>K1JT<QSO_DATE:8>20260926<TIME_ON:6>142401<BAND:4>70cm<MODE:2>CW"
    + "<SAT_NAME:5>RS-44<PROP_MODE:3>SAT<eor>"

private let header = "ADIF export from S.A.T.\n<ADIF_VER:5>3.1.4<PROGRAMID:3>SAT<eoh>\n"

private func data(_ text: String) -> Data {
    Data(text.utf8)
}

// MARK: - SatLogRecordBuffer

@Test func bufferAcceptsBareRecord() {
    let records = SatLogRecordBuffer.records(inDatagram: data(satRecord))
    #expect(records == [satRecord])
}

@Test func bufferStripsAdifHeader() {
    let records = SatLogRecordBuffer.records(inDatagram: data(header + satRecord))
    #expect(records == [satRecord])
}

@Test func bufferSplitsTwoRecordsInOnePayload() {
    let records = SatLogRecordBuffer.records(inDatagram: data(satRecord + "\r\n" + secondRecord + "\n"))
    #expect(records == [satRecord, secondRecord])
}

@Test func bufferMatchesEorCaseInsensitively() {
    let upper = satRecord.replacingOccurrences(of: "<eor>", with: "<EOR>")
    let mixed = secondRecord.replacingOccurrences(of: "<eor>", with: "<Eor>")
    let records = SatLogRecordBuffer.records(inDatagram: data(upper + mixed))
    // Output is normalised to a lowercase terminator.
    #expect(records == [satRecord, secondRecord])
}

@Test func bufferHoldsPartialTcpRecordUntilEor() {
    var buffer = SatLogRecordBuffer()
    let splitAt = satRecord.index(satRecord.startIndex, offsetBy: 40)
    let first = String(satRecord[..<splitAt])
    let second = String(satRecord[splitAt...])

    #expect(buffer.append(data(first)).isEmpty)
    #expect(!buffer.isEmpty)
    #expect(buffer.append(data(second)) == [satRecord])
    #expect(buffer.isEmpty)
}

@Test func bufferHandlesEorSplitAcrossChunks() {
    var buffer = SatLogRecordBuffer()
    let body = String(satRecord.dropLast(5))
    #expect(buffer.append(data(body + "<eo")).isEmpty)
    #expect(buffer.append(data("r>" + secondRecord)) == [satRecord, secondRecord])
}

@Test func flushTreatsUnterminatedDatagramAsRecord() {
    let bare = String(satRecord.dropLast(5))
    let records = SatLogRecordBuffer.records(inDatagram: data(bare))
    #expect(records == [satRecord])
}

@Test func flushIgnoresWrapperGarbage() {
    // e.g. the tail of an ACLog-style XML wrapper after the ADIF payload.
    var buffer = SatLogRecordBuffer()
    #expect(buffer.append(data("</VALUE></CMD>\r\n")).isEmpty)
    #expect(buffer.flush().isEmpty)
    #expect(SatLogRecordBuffer.records(inDatagram: data("   \n")).isEmpty)
}

// MARK: - Parsing + satellite fields

@Test func parsedRecordPreservesSatelliteFields() throws {
    let records = try ADIFParser().parse(satRecord)
    let record = try #require(records.first)
    #expect(record.callsign == "W1ABC")
    #expect(record.satName == "AO-91")
    #expect(record.propMode == "SAT")
    #expect(record.myCallsign == "W6JSV")
    #expect(ADIFParser.extractField("BAND_RX", from: record.rawADIF) == "70cm")
    #expect(ADIFParser.extractField("FREQ_RX", from: record.rawADIF) == "435.30000")

    let qso = try ADIFRecordQSOFactory.makeQSO(from: record, myCallsign: "N0CALL", importSource: .satTracker)
    #expect(qso.satName == "AO-91")
    #expect(qso.propMode == "SAT")
    #expect(qso.importSource == .satTracker)
    #expect(qso.myCallsign == "W6JSV")
    #expect(qso.rawADIF?.contains("<BAND_RX:4>70cm") == true)
    #expect(qso.rawADIF?.contains("<FREQ_RX:9>435.30000") == true)
}

@Test func satTrackerImportSourceRawValue() {
    #expect(ImportSource.satTracker.rawValue == "sat")
    #expect(ImportSource(rawValue: "sat") == .satTracker)
}

// MARK: - Ingest / dedup

@MainActor
private func makeContainer() throws -> ModelContainer {
    let schema = Schema(CarrierWaveSchema.models)
    // The Sweep test host carries iCloud entitlements, so SwiftData would apply
    // CloudKit schema validation unless CloudKit is explicitly disabled.
    let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
    return try ModelContainer(for: schema, configurations: [config])
}

@MainActor
private func fetchQSOs(_ context: ModelContext) throws -> [QSO] {
    var descriptor = FetchDescriptor<QSO>()
    descriptor.fetchLimit = 50
    return try context.fetch(descriptor)
}

@MainActor
@Test func ingestorDedupsRetransmittedRecord() throws {
    let container = try makeContainer()
    let ingestor = SatLogIngestor(context: container.mainContext)
    let record = try #require(try ADIFParser().parse(satRecord).first)

    let first = try ingestor.ingest(record, myCallsign: "N0CALL", session: nil)
    guard case let .logged(qso) = first else {
        Issue.record("first ingest should log; got \(first)")
        return
    }
    #expect(qso.importSource == .satTracker)
    #expect(qso.satName == "AO-91")
    #expect(qso.loggingSessionId == nil)

    let second = try ingestor.ingest(record, myCallsign: "N0CALL", session: nil)
    guard case .duplicate = second else {
        Issue.record("retransmit should be a duplicate; got \(second)")
        return
    }
    #expect(try fetchQSOs(container.mainContext).count == 1)
}

@MainActor
@Test func ingestorAttachesActiveSession() throws {
    let container = try makeContainer()
    let context = container.mainContext
    let session = LoggingSession(myCallsign: "W6JSV", mode: "FM", myGrid: "CM87")
    context.insert(session)
    try context.save()

    let ingestor = SatLogIngestor(context: context)
    #expect(ingestor.activeSession()?.id == session.id)

    let record = try #require(try ADIFParser().parse(secondRecord).first)
    let outcome = try ingestor.ingest(record, myCallsign: "N0CALL", session: session)
    guard case let .logged(qso) = outcome else {
        Issue.record("expected logged; got \(outcome)")
        return
    }
    #expect(qso.loggingSessionId == session.id)
    #expect(qso.myCallsign == "W6JSV")
    #expect(qso.myGrid == "CM87")
    #expect(qso.satName == "RS-44")
    #expect(session.qsoCount == 1)
}

@MainActor
@Test func ingestorSkipsMetadataPseudoModes() throws {
    let container = try makeContainer()
    let ingestor = SatLogIngestor(context: container.mainContext)
    let note = "<CALL:4>NOTE<QSO_DATE:8>20260926<TIME_ON:4>1200<BAND:2>2m<MODE:4>NOTE<eor>"
    let record = try #require(try ADIFParser().parse(note).first)
    guard case .skippedMetadata = try ingestor.ingest(record, myCallsign: "N0CALL", session: nil) else {
        Issue.record("metadata pseudo-mode should be skipped")
        return
    }
    #expect(try fetchQSOs(container.mainContext).isEmpty)
}
