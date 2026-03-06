import Foundation

/// Elecraft K3/K4 protocol handler.
/// Extends Kenwood protocol with Elecraft-specific commands.
struct ElecraftProtocolHandler: RadioProtocolHandler {
    // MARK: Internal

    func encodeReadFrequency() -> Data? {
        kenwood.encodeReadFrequency()
    }

    func encodeReadMode() -> Data? {
        kenwood.encodeReadMode()
    }

    func encodeSetFrequency(_ freqMHz: Double) -> Data {
        kenwood.encodeSetFrequency(freqMHz)
    }

    func encodeSetMode(_ mode: String) -> Data {
        kenwood.encodeSetMode(mode)
    }

    func encodeSetPTT(_ on: Bool) -> Data {
        kenwood.encodeSetPTT(on)
    }

    func decodeFrequency(from data: Data) -> Double? {
        kenwood.decodeFrequency(from: data)
    }

    func decodeMode(from data: Data) -> String? {
        kenwood.decodeMode(from: data)
    }

    func decodePTTState(from data: Data) -> Bool? {
        kenwood.decodePTTState(from: data)
    }

    func encodeSetXIT(_ on: Bool) -> Data? {
        kenwood.encodeSetXIT(on)
    }

    func encodeSetXITOffset(_ hz: Int) -> Data? {
        kenwood.encodeSetXITOffset(hz)
    }

    func encodeClearRITXIT() -> Data? {
        kenwood.encodeClearRITXIT()
    }

    func encodeSendCW(_ text: String) -> Data? {
        "KY \(text);".data(using: .ascii)
    }

    func encodeAbortCW() -> Data? {
        "KY0;".data(using: .ascii)
    }

    // MARK: - Elecraft Extensions

    /// Read K3/K4 power output
    func encodeReadPower() -> Data? {
        "PC;".data(using: .ascii)
    }

    // MARK: Private

    private let kenwood = KenwoodProtocolHandler()
}
