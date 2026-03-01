import Testing
@testable import CarrierWaveCore

@Suite("CI-V Protocol Tests")
struct CIVProtocolTests {
    // MARK: - BCD Frequency

    @Test("Parse BCD frequency - 14.060 MHz")
    func parseBCDFreq14060() {
        // 14,060,000 Hz — byte[3] = (1<<4)|4 = 0x14
        let data: [UInt8] = [0x00, 0x00, 0x06, 0x14, 0x00]
        let hz = CIVProtocol.parseBCDFrequency(data)
        #expect(hz == 14_060_000)
    }

    @Test("Parse BCD frequency - 7.074 MHz")
    func parseBCDFreq7074() {
        // 7,074,000 Hz — byte[3] = (0<<4)|7 = 0x07
        let data: [UInt8] = [0x00, 0x40, 0x07, 0x07, 0x00]
        let hz = CIVProtocol.parseBCDFrequency(data)
        #expect(hz == 7_074_000)
    }

    @Test("Parse BCD frequency - 145.520 MHz")
    func parseBCDFreq145520() {
        // 145,520,000 Hz
        // LSB-first BCD: 00 00 52 45 01
        let data: [UInt8] = [0x00, 0x00, 0x52, 0x45, 0x01]
        let hz = CIVProtocol.parseBCDFrequency(data)
        #expect(hz == 145_520_000)
    }

    @Test("Encode BCD frequency - 14.060 MHz")
    func encodeBCDFreq14060() {
        let bytes = CIVProtocol.encodeBCDFrequency(14_060_000)
        #expect(bytes == [0x00, 0x00, 0x06, 0x14, 0x00])
    }

    @Test("BCD frequency round-trip")
    func bcdFreqRoundTrip() {
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
            let encoded = CIVProtocol.encodeBCDFrequency(freq)
            let decoded = CIVProtocol.parseBCDFrequency(encoded)
            #expect(decoded == freq, "Round-trip failed for \(freq) Hz")
        }
    }

    @Test("Parse BCD frequency - insufficient data returns nil")
    func parseBCDFreqShortData() {
        let data: [UInt8] = [0x00, 0x00, 0x06]
        #expect(CIVProtocol.parseBCDFrequency(data) == nil)
    }

    @Test("Hz/MHz conversion")
    func hzMhzConversion() {
        let hz: UInt64 = 14_060_000
        let mhz = CIVProtocol.hzToMHz(hz)
        #expect(mhz == 14.06)
        #expect(CIVProtocol.mhzToHz(mhz) == hz)
    }

    // MARK: - Frame Building

    @Test("Build read frequency frame")
    func buildReadFreqFrame() {
        let frame = CIVProtocol.buildFrame(to: 0xA4, command: CIVProtocol.cmdReadFreq)
        #expect(frame == [0xFE, 0xFE, 0xA4, 0xE0, 0x03, 0xFD])
    }

    @Test("Build set frequency frame")
    func buildSetFreqFrame() {
        let bcd = CIVProtocol.encodeBCDFrequency(14_060_000)
        let frame = CIVProtocol.buildFrame(
            to: 0xA4, command: CIVProtocol.cmdSetFreq, data: bcd
        )
        #expect(frame == [0xFE, 0xFE, 0xA4, 0xE0, 0x05, 0x00, 0x00, 0x06, 0x14, 0x00, 0xFD])
    }

    @Test("Build set mode frame")
    func buildSetModeFrame() {
        let frame = CIVProtocol.buildFrame(
            to: 0xA4, command: CIVProtocol.cmdSetMode, data: [CIVMode.cw.rawValue]
        )
        #expect(frame == [0xFE, 0xFE, 0xA4, 0xE0, 0x06, 0x03, 0xFD])
    }

    // MARK: - Frame Parsing

    @Test("Extract single frame")
    func extractSingleFrame() {
        // Freq response for 14.060 MHz
        let buffer: [UInt8] = [0xFE, 0xFE, 0xE0, 0xA4, 0x03, 0x00, 0x00, 0x06, 0x14, 0x00, 0xFD]
        let (frames, consumed) = CIVProtocol.extractFrames(from: buffer)
        #expect(frames.count == 1)
        #expect(consumed == buffer.count)

        let frame = frames[0]
        #expect(frame.to == 0xE0)
        #expect(frame.from == 0xA4)
        #expect(frame.command == 0x03)
        #expect(frame.data == [0x00, 0x00, 0x06, 0x14, 0x00])
    }

    @Test("Extract multiple frames")
    func extractMultipleFrames() {
        // Read freq response + ACK
        var buffer: [UInt8] = [0xFE, 0xFE, 0xE0, 0xA4, 0x03, 0x00, 0x00, 0x06, 0x14, 0x00, 0xFD]
        buffer += [0xFE, 0xFE, 0xE0, 0xA4, 0xFB, 0xFD]

        let (frames, consumed) = CIVProtocol.extractFrames(from: buffer)
        #expect(frames.count == 2)
        #expect(consumed == buffer.count)
        #expect(frames[1].isAck)
    }

    @Test("Extract with incomplete frame leaves unconsumed bytes")
    func extractIncompleteFrame() {
        // Complete frame + start of another without terminator
        var buffer: [UInt8] = [0xFE, 0xFE, 0xE0, 0xA4, 0xFB, 0xFD]
        buffer += [0xFE, 0xFE, 0xE0, 0xA4, 0x03]

        let (frames, consumed) = CIVProtocol.extractFrames(from: buffer)
        #expect(frames.count == 1)
        #expect(consumed == 6)
    }

    @Test("ACK and NAK detection")
    func ackNakDetection() {
        let ack = CIVFrame(to: 0xE0, from: 0xA4, command: 0xFB, data: [])
        #expect(ack.isAck)
        #expect(!ack.isNak)

        let nak = CIVFrame(to: 0xE0, from: 0xA4, command: 0xFA, data: [])
        #expect(!nak.isAck)
        #expect(nak.isNak)
    }

    @Test("Extract ignores garbage before valid frame")
    func extractSkipsGarbage() {
        let buffer: [UInt8] = [0x00, 0xFF, 0x42, 0xFE, 0xFE, 0xE0, 0xA4, 0xFB, 0xFD]
        let (frames, consumed) = CIVProtocol.extractFrames(from: buffer)
        #expect(frames.count == 1)
        #expect(consumed == buffer.count)
        #expect(frames[0].isAck)
    }

    // MARK: - CIVMode

    @Test("Mode byte to Carrier Wave mode")
    func modeMapping() {
        #expect(CIVMode.lsb.carrierWaveMode == "LSB")
        #expect(CIVMode.usb.carrierWaveMode == "USB")
        #expect(CIVMode.am.carrierWaveMode == "AM")
        #expect(CIVMode.cw.carrierWaveMode == "CW")
        #expect(CIVMode.cwR.carrierWaveMode == "CW")
        #expect(CIVMode.rtty.carrierWaveMode == "RTTY")
        #expect(CIVMode.rttyR.carrierWaveMode == "RTTY")
        #expect(CIVMode.fm.carrierWaveMode == "FM")
    }

    @Test("Carrier Wave mode to CI-V mode byte")
    func reverseModeMapping() {
        #expect(CIVMode.from(carrierWaveMode: "CW") == .cw)
        #expect(CIVMode.from(carrierWaveMode: "USB") == .usb)
        #expect(CIVMode.from(carrierWaveMode: "SSB") == .usb)
        #expect(CIVMode.from(carrierWaveMode: "LSB") == .lsb)
        #expect(CIVMode.from(carrierWaveMode: "FT8") == nil)
    }
}
