import Testing
@testable import CarrierWaveCore

@Suite("Kenwood Protocol Tests")
struct KenwoodProtocolTests {
    // MARK: - Set Frequency

    @Test("Set frequency - 14.060 MHz")
    func setFreq14060() {
        let cmd = KenwoodProtocol.setFrequency(hz: 14_060_000)
        #expect(cmd == "FA00014060000;")
    }

    @Test("Set frequency - 7.074 MHz")
    func setFreq7074() {
        let cmd = KenwoodProtocol.setFrequency(hz: 7_074_000)
        #expect(cmd == "FA00007074000;")
    }

    @Test("Set frequency - 145.520 MHz")
    func setFreq145520() {
        let cmd = KenwoodProtocol.setFrequency(hz: 145_520_000)
        #expect(cmd == "FA00145520000;")
    }

    @Test("Set frequency - 432.100 MHz")
    func setFreq432100() {
        let cmd = KenwoodProtocol.setFrequency(hz: 432_100_000)
        #expect(cmd == "FA00432100000;")
    }

    @Test("Read frequency command")
    func readFreq() {
        #expect(KenwoodProtocol.readFrequency() == "FA;")
    }

    // MARK: - Set Mode

    @Test("Set mode - CW")
    func setModeCW() {
        #expect(KenwoodProtocol.setMode(.cw) == "MD3;")
    }

    @Test("Set mode - USB")
    func setModeUSB() {
        #expect(KenwoodProtocol.setMode(.usb) == "MD2;")
    }

    @Test("Set mode - LSB")
    func setModeLSB() {
        #expect(KenwoodProtocol.setMode(.lsb) == "MD1;")
    }

    @Test("Set mode - DATA")
    func setModeDATA() {
        #expect(KenwoodProtocol.setMode(.data) == "MD6;")
    }

    @Test("Read mode command")
    func readMode() {
        #expect(KenwoodProtocol.readMode() == "MD;")
    }

    // MARK: - Parse Frequency Response

    @Test("Parse frequency response - 14.060 MHz")
    func parseFreqResponse14060() {
        let hz = KenwoodProtocol.parseFrequencyResponse("FA00014060000")
        #expect(hz == 14_060_000)
    }

    @Test("Parse frequency response - 7.074 MHz")
    func parseFreqResponse7074() {
        let hz = KenwoodProtocol.parseFrequencyResponse("FA00007074000")
        #expect(hz == 7_074_000)
    }

    @Test("Parse frequency response - too short returns nil")
    func parseFreqResponseShort() {
        #expect(KenwoodProtocol.parseFrequencyResponse("FA123") == nil)
    }

    @Test("Parse frequency response - wrong prefix returns nil")
    func parseFreqResponseWrongPrefix() {
        #expect(KenwoodProtocol.parseFrequencyResponse("MD00014060000") == nil)
    }

    @Test("Parse frequency response - non-numeric returns nil")
    func parseFreqResponseNonNumeric() {
        #expect(KenwoodProtocol.parseFrequencyResponse("FA0001406ABCD") == nil)
    }

    // MARK: - Parse Mode Response

    @Test("Parse mode response - CW")
    func parseModeResponseCW() {
        let mode = KenwoodProtocol.parseModeResponse("MD3")
        #expect(mode == .cw)
    }

    @Test("Parse mode response - USB")
    func parseModeResponseUSB() {
        let mode = KenwoodProtocol.parseModeResponse("MD2")
        #expect(mode == .usb)
    }

    @Test("Parse mode response - DATA-R")
    func parseModeResponseDataR() {
        let mode = KenwoodProtocol.parseModeResponse("MD9")
        #expect(mode == .dataR)
    }

    @Test("Parse mode response - invalid digit returns nil")
    func parseModeResponseInvalid() {
        #expect(KenwoodProtocol.parseModeResponse("MD8") == nil)
    }

    @Test("Parse mode response - too short returns nil")
    func parseModeResponseShort() {
        #expect(KenwoodProtocol.parseModeResponse("M") == nil)
    }

    // MARK: - Extract Responses

    @Test("Extract single response from buffer")
    func extractSingle() {
        let (responses, consumed) = KenwoodProtocol.extractResponses(
            from: "FA00014060000;"
        )
        #expect(responses == ["FA00014060000"])
        #expect(consumed == 14)
    }

    @Test("Extract multiple responses from buffer")
    func extractMultiple() {
        let (responses, consumed) = KenwoodProtocol.extractResponses(
            from: "FA00014060000;MD3;"
        )
        #expect(responses == ["FA00014060000", "MD3"])
        #expect(consumed == 18)
    }

    @Test("Extract with incomplete trailing data")
    func extractIncomplete() {
        let (responses, consumed) = KenwoodProtocol.extractResponses(
            from: "FA00014060000;MD"
        )
        #expect(responses == ["FA00014060000"])
        #expect(consumed == 14)
    }

    @Test("Extract from empty buffer")
    func extractEmpty() {
        let (responses, consumed) = KenwoodProtocol.extractResponses(from: "")
        #expect(responses.isEmpty)
        #expect(consumed == 0)
    }

    @Test("Extract no terminator in buffer")
    func extractNoTerminator() {
        let (responses, consumed) = KenwoodProtocol.extractResponses(
            from: "FA00014060000"
        )
        #expect(responses.isEmpty)
        #expect(consumed == 0)
    }

    // MARK: - Mode Mapping

    @Test("KenwoodMode to Carrier Wave mode")
    func modeToCarrierWave() {
        #expect(KenwoodMode.lsb.carrierWaveMode == "LSB")
        #expect(KenwoodMode.usb.carrierWaveMode == "USB")
        #expect(KenwoodMode.cw.carrierWaveMode == "CW")
        #expect(KenwoodMode.cwR.carrierWaveMode == "CW")
        #expect(KenwoodMode.fm.carrierWaveMode == "FM")
        #expect(KenwoodMode.am.carrierWaveMode == "AM")
        #expect(KenwoodMode.data.carrierWaveMode == "DATA")
        #expect(KenwoodMode.dataR.carrierWaveMode == "DATA")
    }

    @Test("Carrier Wave mode to KenwoodMode")
    func carrierWaveToMode() {
        #expect(KenwoodMode.from(carrierWaveMode: "CW") == .cw)
        #expect(KenwoodMode.from(carrierWaveMode: "USB") == .usb)
        #expect(KenwoodMode.from(carrierWaveMode: "SSB") == .usb)
        #expect(KenwoodMode.from(carrierWaveMode: "LSB") == .lsb)
        #expect(KenwoodMode.from(carrierWaveMode: "FT8") == .data)
        #expect(KenwoodMode.from(carrierWaveMode: "FT4") == .data)
        #expect(KenwoodMode.from(carrierWaveMode: "RTTY") == .data)
        #expect(KenwoodMode.from(carrierWaveMode: "MFSK") == nil)
    }

    // MARK: - Frequency Round-Trip

    @Test("Frequency set/parse round-trip")
    func frequencyRoundTrip() {
        let frequencies: [UInt64] = [
            14_060_000,
            7_074_000,
            3_573_000,
            28_074_000,
            145_520_000,
            432_100_000,
            1_840_000,
        ]
        for freq in frequencies {
            let cmd = KenwoodProtocol.setFrequency(hz: freq)
            // Strip the trailing ";"
            let response = String(cmd.dropLast())
            let parsed = KenwoodProtocol.parseFrequencyResponse(response)
            #expect(parsed == freq, "Round-trip failed for \(freq) Hz")
        }
    }
}
