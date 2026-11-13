import Testing
@testable import CarrierWaveCore

struct CIVScopeTests {
    // MARK: Internal

    // MARK: - Parsing

    @Test("LAN single-frame sweep parses band, geometry, and 475 samples")
    func lanSingleFrame() {
        let samples = ramp(475)
        let data = header(band: 0x00, division: 0x01, max: 0x01, mode: 0x00,
                          first: bcd145900, second: bcd25k) + samples
        let parsed = CIVScopeFrame(frame: frame(data: data))
        #expect(parsed?.band == .main)
        #expect(parsed?.division == 1)
        #expect(parsed?.divisionMax == 1)
        #expect(parsed?.mode == .center)
        #expect(parsed?.firstFrequencyHz == 145_900_000)
        #expect(parsed?.secondFrequencyHz == 25_000)
        #expect(parsed?.isOutOfRange == false)
        #expect(parsed?.samples == samples)
    }

    @Test("Non-scope frames and non-waveform sub-commands are rejected")
    func rejectsOtherFrames() {
        let freq = CIVFrame(to: controller, from: radio, command: 0x03, data: bcd145900)
        #expect(CIVScopeFrame(frame: freq) == nil)
        let scopeOn = frame(data: [0x11, 0x01])
        #expect(CIVScopeFrame(frame: scopeOn) == nil)
    }

    @Test("Division index is BCD (0x11 → 11)")
    func divisionIsBCD() {
        let data: [UInt8] = [0x00, 0x00, 0x11, 0x11] + ramp(25)
        let parsed = CIVScopeFrame(frame: frame(data: data))
        #expect(parsed?.division == 11)
        #expect(parsed?.divisionMax == 11)
        #expect(parsed?.samples.count == 25)
        #expect(parsed?.mode == nil)
    }

    @Test("Sub band frame carries band = .sub")
    func subBandFrame() {
        let data = header(band: 0x01, division: 0x01, max: 0x01, mode: 0x00,
                          first: bcd145900, second: bcd25k) + ramp(475)
        #expect(CIVScopeFrame(frame: frame(data: data))?.band == .sub)
    }

    @Test("Frames survive the CI-V byte-level extractor")
    func roundTripThroughExtractor() {
        let data = header(band: 0x00, division: 0x01, max: 0x01, mode: 0x00,
                          first: bcd145900, second: bcd25k) + ramp(475)
        let bytes = CIVProtocol.buildFrame(to: controller, from: radio, command: 0x27, data: data)
        #expect(bytes.count == 490 + 2 + 4 + 1)
        let extracted = CIVProtocol.extractFrames(from: bytes)
        #expect(extracted.frames.count == 1)
        #expect(extracted.consumed == bytes.count)
        let parsed = extracted.frames.first.flatMap { CIVScopeFrame(frame: $0) }
        #expect(parsed?.samples.count == 475)
    }

    // MARK: - Accumulator

    @Test("Center mode line has doubled span and MHz/kHz conveniences")
    func centerModeLine() throws {
        var acc = CIVScopeAccumulator()
        let data = header(band: 0x00, division: 0x01, max: 0x01, mode: 0x00,
                          first: bcd145900, second: bcd25k) + ramp(475)
        let line = try acc.ingest(#require(CIVScopeFrame(frame: frame(data: data))))
        #expect(line?.centerHz == 145_900_000)
        #expect(line?.spanHz == 50_000)
        #expect(line?.centerMHz == 145.9)
        #expect(line?.spanKHz == 50)
        #expect(line?.samples.count == 475)
    }

    @Test("Fixed mode line derives center and span from the edges")
    func fixedModeLine() throws {
        var acc = CIVScopeAccumulator()
        let data = header(band: 0x00, division: 0x01, max: 0x01, mode: 0x01,
                          first: bcd144000, second: bcd148000) + ramp(475)
        let line = try acc.ingest(#require(CIVScopeFrame(frame: frame(data: data))))
        #expect(line?.mode == .fixed)
        #expect(line?.centerHz == 146_000_000)
        #expect(line?.spanHz == 4_000_000)
    }

    @Test("USB 11-division sweep reassembles into one 475-bin line")
    func usbMultiDivision() throws {
        var acc = CIVScopeAccumulator()
        let all = ramp(475)
        let head = header(band: 0x00, division: 0x01, max: 0x11, mode: 0x00,
                          first: bcd145900, second: bcd25k)
        #expect(try acc.ingest(#require(CIVScopeFrame(frame: frame(data: head)))) == nil)

        var offset = 0
        var emitted: CIVScopeLine?
        for div in 2 ... 11 {
            let count = div == 11 ? 25 : 50
            let chunk = Array(all[offset ..< offset + count])
            offset += count
            let bcdDiv = UInt8((div / 10) << 4 | (div % 10))
            let data: [UInt8] = [0x00, 0x00, bcdDiv, 0x11] + chunk
            let result = try acc.ingest(#require(CIVScopeFrame(frame: frame(data: data))))
            if div < 11 {
                #expect(result == nil)
            } else {
                emitted = result
            }
        }
        #expect(emitted?.samples == all)
        #expect(emitted?.centerHz == 145_900_000)
    }

    @Test("Interleaved Main and Sub sweeps do not mix samples")
    func interleavedBands() throws {
        var acc = CIVScopeAccumulator()
        let mainHead = header(band: 0x00, division: 0x01, max: 0x02, mode: 0x00,
                              first: bcd145900, second: bcd25k)
        let subHead = header(band: 0x01, division: 0x01, max: 0x02, mode: 0x00,
                             first: bcd144000, second: bcd25k)
        #expect(try acc.ingest(#require(CIVScopeFrame(frame: frame(data: mainHead)))) == nil)
        #expect(try acc.ingest(#require(CIVScopeFrame(frame: frame(data: subHead)))) == nil)
        let subTail: [UInt8] = [0x00, 0x01, 0x02, 0x02] + [7, 7, 7]
        let mainTail: [UInt8] = [0x00, 0x00, 0x02, 0x02] + [9, 9]
        let sub = try acc.ingest(#require(CIVScopeFrame(frame: frame(data: subTail))))
        let main = try acc.ingest(#require(CIVScopeFrame(frame: frame(data: mainTail))))
        #expect(sub?.band == .sub)
        #expect(sub?.samples == [7, 7, 7])
        #expect(main?.band == .main)
        #expect(main?.samples == [9, 9])
    }

    @Test("Out-of-range header drops the sweep and clears any pending line")
    func outOfRange() throws {
        var acc = CIVScopeAccumulator()
        let head = header(band: 0x00, division: 0x01, max: 0x11, mode: 0x00,
                          first: bcd145900, second: bcd25k)
        #expect(try acc.ingest(#require(CIVScopeFrame(frame: frame(data: head)))) == nil)
        let oor = header(band: 0x00, division: 0x01, max: 0x11, mode: 0x00,
                         first: bcd145900, second: bcd25k, outOfRange: 0x01)
        #expect(try acc.ingest(#require(CIVScopeFrame(frame: frame(data: oor)))) == nil)
        // A stray continuation without a header is ignored.
        let tail: [UInt8] = [0x00, 0x00, 0x11, 0x11] + ramp(25)
        #expect(try acc.ingest(#require(CIVScopeFrame(frame: frame(data: tail)))) == nil)
    }

    @Test("Normalized magnitudes scale 0…160 to 0…1 and clamp")
    func normalizedMagnitudes() {
        let line = CIVScopeLine(band: .main, mode: .center, centerHz: 1, spanHz: 1,
                                samples: [0, 80, 160, 200])
        let mags = line.normalizedMagnitudes
        #expect(mags[0] == 0)
        #expect(mags[1] == 0.5)
        #expect(mags[2] == 1)
        #expect(mags[3] == 1)
    }

    // MARK: - Encoders

    @Test("Scope command encoders produce documented byte sequences")
    func encoders() {
        #expect(CIVScope.waveformOutput(on: true) == [0x11, 0x01])
        #expect(CIVScope.waveformOutput(on: false) == [0x11, 0x00])
        #expect(CIVScope.scopeDisplay(on: true) == [0x10, 0x01])
        #expect(CIVScope.selectBand(.sub) == [0x12, 0x01])
        #expect(CIVScope.setMode(.fixed, band: .sub) == [0x14, 0x01, 0x01])
        #expect(CIVScope.setSpan(.k25) == [0x15, 0x00, 0x00, 0x50, 0x02, 0x00, 0x00])
        #expect(CIVScope.setSpan(.k2p5) == [0x15, 0x00, 0x00, 0x25, 0x00, 0x00, 0x00])
        let full = CIVProtocol.buildFrame(to: 0xA2, command: CIVScope.command,
                                          data: CIVScope.waveformOutput(on: true))
        #expect(full == [0xFE, 0xFE, 0xA2, 0xE0, 0x27, 0x11, 0x01, 0xFD])
    }

    // MARK: - State read + restore

    @Test("On/off replies parse only from the radio to the controller")
    func parsesOnOffReplies() {
        let on = CIVFrame(to: controller, from: radio, command: 0x27, data: [0x10, 0x01])
        let off = CIVFrame(to: controller, from: radio, command: 0x27, data: [0x11, 0x00])
        #expect(CIVScope.parseOnOffReply(on, subcommand: 0x10, radio: radio) == true)
        #expect(CIVScope.parseOnOffReply(off, subcommand: 0x11, radio: radio) == false)
        // Wrong sub-command, transceive broadcast, other radio, NG.
        #expect(CIVScope.parseOnOffReply(on, subcommand: 0x11, radio: radio) == nil)
        let broadcast = CIVFrame(to: 0x00, from: radio, command: 0x27, data: [0x10, 0x01])
        #expect(CIVScope.parseOnOffReply(broadcast, subcommand: 0x10, radio: radio) == nil)
        #expect(CIVScope.parseOnOffReply(on, subcommand: 0x10, radio: 0x94) == nil)
        let nak = CIVFrame(to: controller, from: radio, command: 0xFA, data: [])
        #expect(CIVScope.parseOnOffReply(nak, subcommand: 0x10, radio: radio) == nil)
    }

    @Test("Scope off, output off: both turned on, both restored off")
    func restoreFromAllOff() {
        let plan = CIVScopeRestorePlan(scopeDisplayOn: false, waveformOutputOn: false)
        #expect(plan.connectCommands == [[0x10, 0x01], [0x11, 0x01]])
        #expect(plan.disconnectCommands == [[0x11, 0x00], [0x10, 0x00]])
    }

    @Test("Scope already on: display is left alone both ways")
    func restoreLeavesDisplayOn() {
        let plan = CIVScopeRestorePlan(scopeDisplayOn: true, waveformOutputOn: false)
        #expect(plan.connectCommands == [[0x11, 0x01]])
        #expect(plan.disconnectCommands == [[0x11, 0x00]])
    }

    @Test("Output read on (a previous client's leftover): still turned off on disconnect")
    func restoreClearsStaleOutput() {
        let plan = CIVScopeRestorePlan(scopeDisplayOn: true, waveformOutputOn: true)
        #expect(plan.connectCommands == [[0x11, 0x01]])
        #expect(plan.disconnectCommands == [[0x11, 0x00]])
    }

    @Test("Unknown state: never writes the display, output off on disconnect")
    func restoreFromUnknown() {
        let plan = CIVScopeRestorePlan(scopeDisplayOn: nil, waveformOutputOn: nil)
        #expect(plan.connectCommands == [[0x11, 0x01]])
        #expect(plan.disconnectCommands == [[0x11, 0x00]])
    }

    // MARK: Private

    // MARK: - Fixtures

    private let radio: UInt8 = 0xA2
    private let controller: UInt8 = 0xE0

    /// 145.900000 MHz, 5-byte BCD LSB-first.
    private let bcd145900: [UInt8] = [0x00, 0x00, 0x90, 0x45, 0x01]
    /// 25 kHz half-width.
    private let bcd25k: [UInt8] = [0x00, 0x50, 0x02, 0x00, 0x00]
    /// 144.000000 MHz / 148.000000 MHz fixed edges.
    private let bcd144000: [UInt8] = [0x00, 0x00, 0x00, 0x44, 0x01]
    private let bcd148000: [UInt8] = [0x00, 0x00, 0x00, 0x48, 0x01]

    private func header(
        band: UInt8, division: UInt8, max: UInt8, mode: UInt8,
        first: [UInt8], second: [UInt8], outOfRange: UInt8 = 0x00
    ) -> [UInt8] {
        [0x00, band, division, max, mode] + first + second + [outOfRange]
    }

    private func frame(data: [UInt8]) -> CIVFrame {
        CIVFrame(to: controller, from: radio, command: 0x27, data: data)
    }

    private func ramp(_ count: Int) -> [UInt8] {
        (0 ..< count).map { UInt8($0 % 161) }
    }
}
