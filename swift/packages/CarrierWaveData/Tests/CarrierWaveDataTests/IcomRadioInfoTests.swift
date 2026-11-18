import Foundation
import Testing
@testable import CarrierWaveData

// MARK: - IcomRadioInfoTests

struct IcomRadioInfoTests {
    // MARK: Internal

    @Test func parsesNameCIVAndMAC() throws {
        let pkt = capabilitiesPacket(name: "IC-9700", civ: 0xA2, mac: [0x00, 0x90, 0xC7, 0x16, 0x87, 0x4D])
        let info = try #require(IcomRadioInfo.parse(capabilitiesPacket: pkt))
        #expect(info.name == "IC-9700")
        #expect(info.civAddress == 0xA2)
        #expect(info.macAddress == "00:90:c7:16:87:4d")
    }

    @Test func missingMACIsNil() throws {
        let pkt = capabilitiesPacket(name: "IC-705", civ: 0xA4, mac: [0, 0, 0, 0, 0, 0])
        let info = try #require(IcomRadioInfo.parse(capabilitiesPacket: pkt))
        #expect(info.macAddress == nil)
    }

    @Test func rejectsShortOrWrongPackets() {
        #expect(IcomRadioInfo.parse(capabilitiesPacket: Data(count: 82)) == nil)
        var wrong = [UInt8](repeating: 0, count: 0xA8)
        wrong[0] = 0x90
        #expect(IcomRadioInfo.parse(capabilitiesPacket: Data(wrong)) == nil)
    }

    @Test func probeRoundTrip() {
        let probe = IcomLANProbe.areYouThere(senderID: 0x1234_5678)
        #expect(probe.count == 16)
        #expect(probe[4] == 0x03)
        #expect(!IcomLANProbe.isIAmHere(probe))
        var reply = probe
        reply[4] = 0x04
        #expect(IcomLANProbe.isIAmHere(reply))
    }

    // MARK: Private

    /// Build a one-radio `0xA8` capabilities packet the way an IC-9700 sends it.
    private func capabilitiesPacket(name: String, civ: UInt8, mac: [UInt8]) -> Data {
        var bytes = [UInt8](repeating: 0, count: 0xA8)
        bytes[0] = 0xA8
        for (idx, byte) in mac.enumerated() {
            bytes[0x42 + 10 + idx] = byte
        }
        for (idx, byte) in Array(name.utf8).enumerated() {
            bytes[0x52 + idx] = byte
        }
        bytes[0x94] = civ
        return Data(bytes)
    }
}
