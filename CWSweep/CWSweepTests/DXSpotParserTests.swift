import Foundation
import Testing
@testable import CWSweep

@Test func parseStandardDXSpot() {
    let line = "DX de W3LPL:      14076.0  JA1ABC     FT8               1423Z"
    let spot = DXSpotParser.parse(line: line)
    #expect(spot != nil)
    #expect(spot?.spotter == "W3LPL")
    #expect(spot?.frequencyKHz == 14_076.0)
    #expect(spot?.callsign == "JA1ABC")
    #expect(spot?.comment == "FT8")
}

@Test func parseSpotWithLongComment() {
    let line = "DX de VE7CC:       7030.0  DL1ABC     CW 599 in Germany  0745Z"
    let spot = DXSpotParser.parse(line: line)
    #expect(spot != nil)
    #expect(spot?.spotter == "VE7CC")
    #expect(spot?.frequencyKHz == 7_030.0)
    #expect(spot?.callsign == "DL1ABC")
    #expect(spot?.comment == "CW 599 in Germany")
}

@Test func parseSpotWithDecimalFrequency() {
    let line = "DX de N1MM:       14074.5  K1ABC      FT8 -15dB          2359Z"
    let spot = DXSpotParser.parse(line: line)
    #expect(spot != nil)
    #expect(spot?.frequencyKHz == 14_074.5)
}

@Test func parseNonSpotLine() {
    let line = "Hello W1AW, welcome to the cluster"
    let spot = DXSpotParser.parse(line: line)
    #expect(spot == nil)
}

@Test func parseEmptyLine() {
    let spot = DXSpotParser.parse(line: "")
    #expect(spot == nil)
}

@Test func parsedSpotToUnifiedSpot() {
    let line = "DX de W3LPL:      14030.0  JH1ABC     CW 25 dB           1200Z"
    let spot = DXSpotParser.parse(line: line)
    #expect(spot != nil)

    let unified = spot?.toUnifiedSpot()
    #expect(unified != nil)
    #expect(unified?.source == .cluster)
    #expect(unified?.callsign == "JH1ABC")
    #expect(unified?.frequencyKHz == 14_030.0)
    #expect(unified?.id.hasPrefix("cluster-") == true)
}

@Test func parsedSpotBand() {
    let line = "DX de W3LPL:       3530.0  DL5ABC     CW 20 dB           1200Z"
    let spot = DXSpotParser.parse(line: line)
    #expect(spot?.band == "80m")
}

@Test func parsedSpotModeGuess() {
    // CW portion of 20m (below digital boundary at 14070)
    let cwLine = "DX de W3LPL:      14030.0  DL5ABC     CW                  1200Z"
    let cwSpot = DXSpotParser.parse(line: cwLine)
    let cwUnified = cwSpot?.toUnifiedSpot()
    #expect(cwUnified?.mode == "CW")

    // SSB portion of 20m (above SSB boundary at 14150)
    let ssbLine = "DX de W3LPL:      14250.0  DL5ABC     SSB                 1200Z"
    let ssbSpot = DXSpotParser.parse(line: ssbLine)
    let ssbUnified = ssbSpot?.toUnifiedSpot()
    #expect(ssbUnified?.mode == "SSB")
}
