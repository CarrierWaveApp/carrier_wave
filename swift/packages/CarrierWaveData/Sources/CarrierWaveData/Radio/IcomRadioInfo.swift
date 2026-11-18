import Foundation

// MARK: - IcomRadioInfo

/// What an Icom LAN/WiFi radio says about itself in the `0xA8` capabilities
/// packet it sends after a successful RS-BA1 login. This is the only place
/// the protocol names the model: the pre-login "I am here" reply is empty.
///
/// Layout (wfview `capabilities_packet` + first `radio_cap_packet`):
/// a 0x42-byte header, then per radio a 16-byte GUID (MAC at GUID+10),
/// a 32-byte NUL-padded name at 0x52, a 32-byte audio device name, a
/// 2-byte connection type, and the CI-V address at 0x94.
public struct IcomRadioInfo: Sendable, Hashable, Codable {
    // MARK: Lifecycle

    public init(name: String, civAddress: UInt8, macAddress: String?) {
        self.name = name
        self.civAddress = civAddress
        self.macAddress = macAddress
    }

    // MARK: Public

    /// Radio name as the radio reports it, e.g. "IC-9700".
    public let name: String
    /// CI-V address the radio answers on (0xA2 for an IC-9700).
    public let civAddress: UInt8
    /// "00:90:c7:16:87:4d" style, when the GUID carries one.
    public let macAddress: String?

    /// Parse the first radio in a `0xA8` capabilities packet. Returns nil for
    /// anything too short to hold a CI-V address.
    public static func parse(capabilitiesPacket pkt: Data) -> IcomRadioInfo? {
        let bytes = [UInt8](pkt)
        guard bytes.count > Offset.civ, bytes[0] == 0xA8 else {
            return nil
        }
        let nameBytes = bytes[Offset.name ..< Offset.name + 32].prefix { $0 != 0 }
        let name = (String(bytes: nameBytes, encoding: .utf8) ?? "")
            .trimmingCharacters(in: .whitespaces)
        let mac = bytes[Offset.mac ..< Offset.mac + 6]
        let macAddress = mac.allSatisfy { $0 == 0 }
            ? nil
            : mac.map { String(format: "%02x", $0) }.joined(separator: ":")
        return IcomRadioInfo(name: name, civAddress: bytes[Offset.civ], macAddress: macAddress)
    }

    // MARK: Private

    private enum Offset {
        static let mac = 0x42 + 10
        static let name = 0x52
        static let civ = 0x94
    }
}

// MARK: - IcomLANProbe

/// Unauthenticated RS-BA1 presence probe, used to find Icom radios on the LAN.
/// Any radio with Network Control on answers an "are you there" (type 0x03)
/// on the control port with an "I am here" (type 0x04).
public enum IcomLANProbe {
    /// 16-byte "are you there" control packet.
    public static func areYouThere(senderID: UInt32) -> Data {
        var pkt = Data(count: 16)
        pkt[0] = 0x10
        pkt[4] = 0x03
        withUnsafeBytes(of: senderID.littleEndian) { pkt.replaceSubrange(8 ..< 12, with: $0) }
        return pkt
    }

    /// True for a 16-byte "I am here" reply.
    public static func isIAmHere(_ pkt: Data) -> Bool {
        let bytes = [UInt8](pkt)
        return bytes.count == 16 && bytes[0] == 0x10 && bytes[4] == 0x04
    }
}
