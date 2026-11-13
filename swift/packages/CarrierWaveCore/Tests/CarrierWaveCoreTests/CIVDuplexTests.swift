import Testing
@testable import CarrierWaveCore

struct CIVDuplexTests {
    // MARK: Internal

    @Test("Band select frames match the IC-9700 reference (07 D0 / 07 D1)")
    func selectBandFrames() {
        #expect(frame(CIVDuplex.selectCommand, CIVDuplex.selectBand(.main)) == [
            0xFE,
            0xFE,
            0xA2,
            0xE0,
            0x07,
            0xD0,
            0xFD,
        ])
        #expect(frame(CIVDuplex.selectCommand, CIVDuplex.selectBand(.sub)) == [
            0xFE,
            0xFE,
            0xA2,
            0xE0,
            0x07,
            0xD1,
            0xFD,
        ])
        #expect(frame(CIVDuplex.selectCommand, CIVDuplex.readSelectedBand) == [
            0xFE,
            0xFE,
            0xA2,
            0xE0,
            0x07,
            0xD2,
            0xFD,
        ])
    }

    @Test("Satellite mode frames (16 5A)")
    func satelliteModeFrames() {
        #expect(frame(CIVDuplex.functionCommand, CIVDuplex.satelliteMode(on: true))
            == [0xFE, 0xFE, 0xA2, 0xE0, 0x16, 0x5A, 0x01, 0xFD])
        #expect(frame(CIVDuplex.functionCommand, CIVDuplex.satelliteMode(on: false))
            == [0xFE, 0xFE, 0xA2, 0xE0, 0x16, 0x5A, 0x00, 0xFD])
        #expect(frame(CIVDuplex.functionCommand, CIVDuplex.readSatelliteMode) == [
            0xFE,
            0xFE,
            0xA2,
            0xE0,
            0x16,
            0x5A,
            0xFD,
        ])
        #expect(frame(CIVDuplex.statusCommand, CIVDuplex.readPTT) == [0xFE, 0xFE, 0xA2, 0xE0, 0x1C, 0x00, 0xFD])
    }

    @Test("Selected-band reply parses Main/Sub and rejects other frames")
    func selectedBandReply() {
        let sub = CIVFrame(to: controller, from: radio, command: 0x07, data: [0xD2, 0x01])
        #expect(CIVDuplex.parseSelectedBandReply(sub, radio: radio) == .sub)
        let main = CIVFrame(to: controller, from: radio, command: 0x07, data: [0xD2, 0x00])
        #expect(CIVDuplex.parseSelectedBandReply(main, radio: radio) == .main)
        // Transceive broadcast of a frequency is not a band reply.
        let broadcast = CIVFrame(to: 0x00, from: radio, command: 0x00, data: [0x00, 0x00, 0x90, 0x45, 0x01])
        #expect(CIVDuplex.parseSelectedBandReply(broadcast, radio: radio) == nil)
        // Wrong radio address.
        let other = CIVFrame(to: controller, from: 0x94, command: 0x07, data: [0xD2, 0x01])
        #expect(CIVDuplex.parseSelectedBandReply(other, radio: radio) == nil)
    }

    @Test("Satellite-mode reply parses on/off, ignores NG and echoes")
    func satelliteModeReply() {
        let on = CIVFrame(to: controller, from: radio, command: 0x16, data: [0x5A, 0x01])
        #expect(CIVDuplex.parseSatelliteModeReply(on, radio: radio) == true)
        let off = CIVFrame(to: controller, from: radio, command: 0x16, data: [0x5A, 0x00])
        #expect(CIVDuplex.parseSatelliteModeReply(off, radio: radio) == false)
        let nak = CIVFrame(to: controller, from: radio, command: 0xFA, data: [])
        #expect(CIVDuplex.parseSatelliteModeReply(nak, radio: radio) == nil)
        #expect(CIVDuplex.isNak(nak, radio: radio))
        // Our own command echoed back on a shared bus (to == radio) must not count.
        let echo = CIVFrame(to: radio, from: controller, command: 0x16, data: [0x5A, 0x01])
        #expect(CIVDuplex.parseSatelliteModeReply(echo, radio: radio) == nil)
        let ack = CIVFrame(to: controller, from: radio, command: 0xFB, data: [])
        #expect(CIVDuplex.isAck(ack, radio: radio))
        #expect(!CIVDuplex.isAck(echo, radio: radio))
    }

    // MARK: Private

    private let radio: UInt8 = 0xA2
    private let controller = CIVProtocol.controllerAddress

    private func frame(_ command: UInt8, _ data: [UInt8]) -> [UInt8] {
        CIVProtocol.buildFrame(to: radio, command: command, data: data)
    }
}
