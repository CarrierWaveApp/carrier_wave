import Foundation

// MARK: - CIVBand

/// One of the two receivers in a dual-band Icom (IC-9700). In satellite mode
/// Main is the downlink (RX) and Sub is the uplink (TX).
public enum CIVBand: UInt8, Sendable, Equatable, CaseIterable {
    case main = 0x00
    case sub = 0x01

    // MARK: Public

    public var label: String {
        switch self {
        case .main: "Main"
        case .sub: "Sub"
        }
    }
}

// MARK: - CIVDuplex

/// Encoders and reply parsers for the IC-9700's Main/Sub band selection
/// (`07 D0/D1/D2`), satellite mode (`16 5A`) and the PTT read (`1C 00`).
///
/// The 9700 has no band-addressed frequency command: `25`/`26` address VFO
/// A/B of one band and return NG in satellite mode. Tuning Sub is therefore
/// a sequence — select Sub, `05` set frequency, reselect Main — which
/// `RadioSession.tuneSubBand` runs with polling paused so a `03` read can't
/// land on the wrong band. Reference: `docs/icom-ic9700-civ-protocol.md`.
///
/// Data arrays are passed to `CIVProtocol.buildFrame(to:command:data:)`.
public enum CIVDuplex {
    /// `07` — VFO / band selection command.
    public static let selectCommand: UInt8 = 0x07
    /// `16` — function on/off command (satellite mode lives under `5A`).
    public static let functionCommand: UInt8 = 0x16
    /// `1C` — transceiver status (PTT under sub-command `00`).
    public static let statusCommand: UInt8 = 0x1C

    /// `07 D2` read — reply is `07 D2 00|01`.
    public static let readSelectedBand: [UInt8] = [0xD2]

    /// `16 5A` read — reply is `16 5A 00|01`.
    public static let readSatelliteMode: [UInt8] = [0x5A]

    /// `1C 00` read — reply is `1C 00 00|01` (already decoded by
    /// `CIVProtocolHandler.decodePTTState`).
    public static let readPTT: [UInt8] = [0x00]

    /// `07 D0` / `07 D1` — make Main or Sub the selected band.
    public static func selectBand(_ band: CIVBand) -> [UInt8] {
        [band == .main ? 0xD0 : 0xD1]
    }

    /// `16 5A 00|01` — satellite mode off / on. Full duplex (RX on Main while
    /// TX on Sub) only exists with this on.
    public static func satelliteMode(on: Bool) -> [UInt8] {
        [0x5A, on ? 0x01 : 0x00]
    }

    /// Parse the reply to a `07 D2` read from `radio`. Nil for anything else.
    public static func parseSelectedBandReply(_ frame: CIVFrame, radio: UInt8) -> CIVBand? {
        guard frame.command == selectCommand,
              frame.to == CIVProtocol.controllerAddress,
              frame.from == radio,
              frame.data.count == 2,
              frame.data[0] == 0xD2
        else {
            return nil
        }
        return CIVBand(rawValue: frame.data[1])
    }

    /// Parse the reply to a `16 5A` read from `radio`. Nil for anything
    /// else, including NG and transceive broadcasts.
    public static func parseSatelliteModeReply(_ frame: CIVFrame, radio: UInt8) -> Bool? {
        guard frame.command == functionCommand,
              frame.to == CIVProtocol.controllerAddress,
              frame.from == radio,
              frame.data.count == 2,
              frame.data[0] == 0x5A,
              frame.data[1] <= 0x01
        else {
            return nil
        }
        return frame.data[1] == 0x01
    }

    /// True for the `FB` acknowledgement a radio sends after a set command.
    public static func isAck(_ frame: CIVFrame, radio: UInt8) -> Bool {
        frame.command == 0xFB && frame.from == radio && frame.to == CIVProtocol.controllerAddress
    }

    /// True for the `FA` negative acknowledgement.
    public static func isNak(_ frame: CIVFrame, radio: UInt8) -> Bool {
        frame.command == 0xFA && frame.from == radio && frame.to == CIVProtocol.controllerAddress
    }
}
