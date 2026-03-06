import CarrierWaveData
import Foundation
import Testing

@Test func importSourceRoundTrip() {
    let source = ImportSource.logger
    #expect(source.rawValue == "logger")
    #expect(ImportSource(rawValue: "logger") == .logger)
}

@Test func activationTypeFromPrograms() {
    #expect(ActivationType.from(programs: ["pota"]) == .pota)
    #expect(ActivationType.from(programs: ["sota"]) == .sota)
    #expect(ActivationType.from(programs: []) == .casual)
    #expect(ActivationType.from(programs: ["pota", "wwff"]) == .pota)
}

@Test func roveStopDuration() {
    let start = Date()
    let end = start.addingTimeInterval(3_600) // 1 hour
    let stop = RoveStop(
        parkReference: "K-1234",
        startedAt: start,
        endedAt: end,
        qsoCount: 10
    )
    #expect(stop.duration == 3_600)
    #expect(stop.formattedDuration == "1h 0m")
    #expect(!stop.isActive)
}
