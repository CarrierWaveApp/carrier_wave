import Foundation
import Testing
@testable import CWSweep

// MARK: - SpotTuneDestination Tests

@Test func connectedRadioWinsOverWaterfall() {
    let destination = SpotTuneDestination.resolve(
        isRadioConnected: true,
        radioName: "Elecraft K3",
        sdrWaterfallEnabled: true
    )
    #expect(destination == .radio(name: "Elecraft K3"))
    #expect(destination.contextMenuFootnote == nil)
    #expect(destination.noRadioStatusLine(frequencyMHz: 14.03, mode: "CW") == nil)
}

@Test func waterfallDestinationWhenNoRadioButSDREnabled() {
    let destination = SpotTuneDestination.resolve(
        isRadioConnected: false,
        radioName: nil,
        sdrWaterfallEnabled: true
    )
    #expect(destination == .sdrWaterfall)
    #expect(destination.contextMenuFootnote?.contains("SDR waterfall") == true)
    #expect(
        destination.noRadioStatusLine(frequencyMHz: 14.03, mode: "CW")
            == "No radio connected — set 14.030 MHz CW for the SDR waterfall and log entry"
    )
}

@Test func logEntryOnlyWhenNothingConnected() {
    let destination = SpotTuneDestination.resolve(
        isRadioConnected: false,
        radioName: nil,
        sdrWaterfallEnabled: false
    )
    #expect(destination == .logEntryOnly)
    #expect(destination.contextMenuFootnote?.contains("only sets the log entry") == true)
    #expect(
        destination.noRadioStatusLine(frequencyMHz: 7.025, mode: "CW")
            == "No radio connected — set 7.025 MHz CW for the log entry"
    )
}

@Test func statusLineOmitsEmptyMode() {
    let line = SpotTuneDestination.logEntryOnly.noRadioStatusLine(frequencyMHz: 14.03, mode: "")
    #expect(line == "No radio connected — set 14.030 MHz for the log entry")
}
