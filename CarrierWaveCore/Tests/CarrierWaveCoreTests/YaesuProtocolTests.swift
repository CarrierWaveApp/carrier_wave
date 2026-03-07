import Testing
@testable import CarrierWaveCore

@Suite("Yaesu Protocol Tests")
struct YaesuProtocolTests {
    // MARK: - Set Frequency

    @Test("Set frequency - 14.250 MHz")
    func setFreq14250() {
        let cmd = YaesuProtocol.setFrequency(hz: 14_250_000)
        #expect(cmd == "FA014250000;")
    }

    @Test("Set frequency - 7.074 MHz")
    func setFreq7074() {
        let cmd = YaesuProtocol.setFrequency(hz: 7_074_000)
        #expect(cmd == "FA007074000;")
    }

    @Test("Set frequency - 28.074 MHz")
    func setFreq28074() {
        let cmd = YaesuProtocol.setFrequency(hz: 28_074_000)
        #expect(cmd == "FA028074000;")
    }

    @Test("Read frequency command")
    func readFreq() {
        #expect(YaesuProtocol.readFrequency() == "FA;")
    }

    // MARK: - Set Mode

    @Test("Set mode - CW-U on main band")
    func setModeCW() {
        #expect(YaesuProtocol.setMode(.cwU) == "MD03;")
    }

    @Test("Set mode - USB on main band")
    func setModeUSB() {
        #expect(YaesuProtocol.setMode(.usb) == "MD02;")
    }

    @Test("Set mode - LSB on main band")
    func setModeLSB() {
        #expect(YaesuProtocol.setMode(.lsb) == "MD01;")
    }

    @Test("Set mode - DATA-U on main band")
    func setModeDataU() {
        #expect(YaesuProtocol.setMode(.dataU) == "MD0C;")
    }

    @Test("Set mode - FM on sub band")
    func setModeFMSub() {
        #expect(YaesuProtocol.setMode(.fm, band: 1) == "MD14;")
    }

    @Test("Read mode command")
    func readMode() {
        #expect(YaesuProtocol.readMode() == "MD0;")
    }

    // MARK: - PTT

    @Test("PTT on")
    func pttOn() {
        #expect(YaesuProtocol.setPTT(on: true) == "TX1;")
    }

    @Test("PTT off")
    func pttOff() {
        #expect(YaesuProtocol.setPTT(on: false) == "TX0;")
    }

    @Test("Read PTT")
    func readPTT() {
        #expect(YaesuProtocol.readPTT() == "TX;")
    }

    // MARK: - Clarifier (RIT/XIT)

    @Test("RIT on/off")
    func ritOnOff() {
        #expect(YaesuProtocol.setRIT(on: true) == "RT1;")
        #expect(YaesuProtocol.setRIT(on: false) == "RT0;")
    }

    @Test("XIT on/off")
    func xitOnOff() {
        #expect(YaesuProtocol.setXIT(on: true) == "XT1;")
        #expect(YaesuProtocol.setXIT(on: false) == "XT0;")
    }

    @Test("Clear clarifier")
    func clearClarifier() {
        #expect(YaesuProtocol.clearClarifier() == "RC;")
    }

    @Test("Clarifier up")
    func clarifierUp() {
        #expect(YaesuProtocol.clarifierUp(hz: 100) == "RU0100;")
        #expect(YaesuProtocol.clarifierUp(hz: 9_990) == "RU9990;")
    }

    @Test("Clarifier down")
    func clarifierDown() {
        #expect(YaesuProtocol.clarifierDown(hz: 50) == "RD0050;")
    }

    @Test("Clarifier clamping")
    func clarifierClamping() {
        #expect(YaesuProtocol.clarifierUp(hz: 99_999) == "RU9990;")
        #expect(YaesuProtocol.clarifierDown(hz: -5) == "RD0000;")
    }

    // MARK: - CW Commands

    @Test("Send CW text")
    func sendCW() {
        let cmd = YaesuProtocol.sendCW("CQ CQ DE W1AW")
        #expect(cmd == "KM5CQ CQ DE W1AW;KY5;")
    }

    @Test("CW text truncated to 50 chars")
    func sendCWTruncated() {
        let longText = String(repeating: "A", count: 60)
        let cmd = YaesuProtocol.sendCW(longText)
        let expected50 = String(repeating: "A", count: 50)
        #expect(cmd == "KM5\(expected50);KY5;")
    }

    // MARK: - Information command

    @Test("Read information command")
    func readInformation() {
        #expect(YaesuProtocol.readInformation() == "IF;")
    }

    // MARK: - Parse Frequency Response

    @Test("Parse frequency response - 14.250 MHz")
    func parseFreqResponse14250() {
        let hz = YaesuProtocol.parseFrequencyResponse("FA014250000")
        #expect(hz == 14_250_000)
    }

    @Test("Parse frequency response - 7.074 MHz")
    func parseFreqResponse7074() {
        let hz = YaesuProtocol.parseFrequencyResponse("FA007074000")
        #expect(hz == 7_074_000)
    }

    @Test("Parse frequency response - too short returns nil")
    func parseFreqResponseShort() {
        #expect(YaesuProtocol.parseFrequencyResponse("FA123") == nil)
    }

    @Test("Parse frequency response - wrong prefix returns nil")
    func parseFreqResponseWrongPrefix() {
        #expect(YaesuProtocol.parseFrequencyResponse("MD014250000") == nil)
    }

    // MARK: - Parse Mode Response

    @Test("Parse mode response - CW-U")
    func parseModeResponseCW() {
        let mode = YaesuProtocol.parseModeResponse("MD03")
        #expect(mode == .cwU)
    }

    @Test("Parse mode response - USB")
    func parseModeResponseUSB() {
        let mode = YaesuProtocol.parseModeResponse("MD02")
        #expect(mode == .usb)
    }

    @Test("Parse mode response - DATA-U")
    func parseModeResponseDataU() {
        let mode = YaesuProtocol.parseModeResponse("MD0C")
        #expect(mode == .dataU)
    }

    @Test("Parse mode response - too short returns nil")
    func parseModeResponseShort() {
        #expect(YaesuProtocol.parseModeResponse("MD") == nil)
    }

    // MARK: - Parse TX Response

    @Test("Parse TX response - receiving")
    func parseTXResponseRX() {
        #expect(YaesuProtocol.parseTXResponse("TX0") == false)
    }

    @Test("Parse TX response - CAT TX on")
    func parseTXResponseCATTX() {
        #expect(YaesuProtocol.parseTXResponse("TX1") == true)
    }

    @Test("Parse TX response - radio TX on")
    func parseTXResponseRadioTX() {
        #expect(YaesuProtocol.parseTXResponse("TX2") == true)
    }

    // MARK: - Parse RIT/XIT Response

    @Test("Parse RIT response")
    func parseRITResponse() {
        #expect(YaesuProtocol.parseRITResponse("RT1") == true)
        #expect(YaesuProtocol.parseRITResponse("RT0") == false)
    }

    @Test("Parse XIT response")
    func parseXITResponse() {
        #expect(YaesuProtocol.parseXITResponse("XT1") == true)
        #expect(YaesuProtocol.parseXITResponse("XT0") == false)
    }

    // MARK: - Parse IF (Information) Response

    @Test("Parse IF response - full status")
    func parseIFResponse() {
        // IF + P1(001) + P2(014250000) + P3(+0100) + P4(1) + P5(0) + P6(3) + P7(0) + P8(0) + P9(00) + P10(0)
        let response = "IF001014250000+010010300000"
        let info = YaesuProtocol.parseInformationResponse(response)
        #expect(info != nil)
        #expect(info?.frequencyHz == 14_250_000)
        #expect(info?.clarifierOffset == 100)
        #expect(info?.rxClarifier == true)
        #expect(info?.txClarifier == false)
        #expect(info?.mode == .cwU)
    }

    @Test("Parse IF response - negative offset")
    func parseIFResponseNegativeOffset() {
        let response = "IF001007074000-005010200000"
        let info = YaesuProtocol.parseInformationResponse(response)
        #expect(info != nil)
        #expect(info?.frequencyHz == 7_074_000)
        #expect(info?.clarifierOffset == -50)
        #expect(info?.rxClarifier == true)
        #expect(info?.txClarifier == false)
        #expect(info?.mode == .usb)
    }

    @Test("Parse IF response - zero offset, XIT on")
    func parseIFResponseZeroOffset() {
        let response = "IF001014060000+000001300000"
        let info = YaesuProtocol.parseInformationResponse(response)
        #expect(info != nil)
        #expect(info?.clarifierOffset == 0)
        #expect(info?.rxClarifier == false)
        #expect(info?.txClarifier == true)
        #expect(info?.mode == .cwU)
    }

    @Test("Parse IF response - too short returns nil")
    func parseIFResponseShort() {
        #expect(YaesuProtocol.parseInformationResponse("IF001") == nil)
    }

    // MARK: - Extract Responses

    @Test("Extract single response")
    func extractSingle() {
        let (responses, consumed) = YaesuProtocol.extractResponses(
            from: "FA014250000;"
        )
        #expect(responses == ["FA014250000"])
        #expect(consumed == 12)
    }

    @Test("Extract multiple responses")
    func extractMultiple() {
        let (responses, consumed) = YaesuProtocol.extractResponses(
            from: "FA014250000;MD03;"
        )
        #expect(responses == ["FA014250000", "MD03"])
        #expect(consumed == 17)
    }

    @Test("Extract with incomplete trailing data")
    func extractIncomplete() {
        let (responses, consumed) = YaesuProtocol.extractResponses(
            from: "FA014250000;MD"
        )
        #expect(responses == ["FA014250000"])
        #expect(consumed == 12)
    }

    // MARK: - Mode Mapping

    @Test("YaesuMode to Carrier Wave mode")
    func modeToCarrierWave() {
        #expect(YaesuMode.lsb.carrierWaveMode == "LSB")
        #expect(YaesuMode.usb.carrierWaveMode == "USB")
        #expect(YaesuMode.cwU.carrierWaveMode == "CW")
        #expect(YaesuMode.cwL.carrierWaveMode == "CW")
        #expect(YaesuMode.fm.carrierWaveMode == "FM")
        #expect(YaesuMode.fmN.carrierWaveMode == "FM")
        #expect(YaesuMode.am.carrierWaveMode == "AM")
        #expect(YaesuMode.amN.carrierWaveMode == "AM")
        #expect(YaesuMode.rttyL.carrierWaveMode == "RTTY")
        #expect(YaesuMode.rttyU.carrierWaveMode == "RTTY")
        #expect(YaesuMode.dataU.carrierWaveMode == "DATA")
        #expect(YaesuMode.dataL.carrierWaveMode == "DATA")
        #expect(YaesuMode.dataFM.carrierWaveMode == "DATA")
        #expect(YaesuMode.psk.carrierWaveMode == "DATA")
    }

    @Test("Carrier Wave mode to YaesuMode")
    func carrierWaveToMode() {
        #expect(YaesuMode.from(carrierWaveMode: "CW") == .cwU)
        #expect(YaesuMode.from(carrierWaveMode: "USB") == .usb)
        #expect(YaesuMode.from(carrierWaveMode: "SSB") == .usb)
        #expect(YaesuMode.from(carrierWaveMode: "LSB") == .lsb)
        #expect(YaesuMode.from(carrierWaveMode: "FT8") == .dataU)
        #expect(YaesuMode.from(carrierWaveMode: "FT4") == .dataU)
        #expect(YaesuMode.from(carrierWaveMode: "RTTY") == .rttyL)
        #expect(YaesuMode.from(carrierWaveMode: "MFSK") == nil)
    }

    @Test("YaesuMode protocol char round-trip")
    func modeProtocolCharRoundTrip() {
        for mode in YaesuMode.allCases {
            let restored = YaesuMode(protocolChar: mode.protocolChar)
            #expect(restored == mode, "Round-trip failed for \(mode)")
        }
    }

    // MARK: - Frequency Round-Trip

    @Test("Frequency set/parse round-trip")
    func frequencyRoundTrip() {
        let frequencies: [UInt64] = [
            14_250_000,
            7_074_000,
            3_573_000,
            28_074_000,
            1_840_000,
            50_313_000,
        ]
        for freq in frequencies {
            let cmd = YaesuProtocol.setFrequency(hz: freq)
            let response = String(cmd.dropLast()) // Strip ";"
            let parsed = YaesuProtocol.parseFrequencyResponse(response)
            #expect(parsed == freq, "Round-trip failed for \(freq) Hz")
        }
    }
}
