import Foundation

// MARK: - RadioStateCodec

/// Bidirectional codec for one radio setting's CAT payload. The read half
/// (`decode`) turns a query-response payload into a canonical value; the
/// write half (`encode`) turns a canonical value into a SET payload.
///
/// This pairing is exactly what the live `RadioCommandSpec` catalog lacks:
/// today commands are write-only (`template` encodes, nothing decodes), so
/// there is no way to read current state and diff it. A declarative
/// profile is impossible without it — hence the spike models it here.
public enum RadioStateCodec: Sendable, Equatable {
    /// Frequency in Hz as fixed-width zero-padded decimal (Elecraft/Kenwood
    /// `FA`/`FB` are 11 digits). Canonical value is Hz with leading zeros
    /// stripped, e.g. `"14074000"`.
    case frequencyHz(digits: Int)
    /// Elecraft/Kenwood `MD` single-digit mode code. Canonical value is the
    /// mode name, e.g. `"USB"`.
    case elecraftMode
    /// Fixed-width zero-padded unsigned integer (e.g. `PC` power, 3 digits).
    /// Canonical value strips leading zeros.
    case zeroPaddedInt(digits: Int)

    // MARK: Public

    /// Parse the payload portion of a query response (prefix and terminator
    /// already removed) into a canonical value. Returns nil when the payload
    /// doesn't fit this codec.
    public func decode(_ payload: String) -> String? {
        switch self {
        case .frequencyHz,
             .zeroPaddedInt:
            Self.stripLeadingZeros(payload)
        case .elecraftMode:
            Self.modeByCode[payload]
        }
    }

    /// Encode a canonical value into the payload of a SET command. Returns
    /// nil when the value is malformed or out of range for this codec.
    public func encode(_ value: String) -> String? {
        switch self {
        case let .frequencyHz(digits),
             let .zeroPaddedInt(digits):
            Self.zeroPad(value, width: digits)
        case .elecraftMode:
            Self.codeByMode[value.uppercased()]
        }
    }

    // MARK: Private

    /// Elecraft K-line `MD` codes shared by KX2/KX3/K3.
    private static let modeByCode: [String: String] = [
        "1": "LSB", "2": "USB", "3": "CW", "4": "FM",
        "5": "AM", "6": "DATA", "7": "CW-R", "9": "DATA-R",
    ]

    private static let codeByMode: [String: String] = [
        "LSB": "1", "USB": "2", "CW": "3", "FM": "4",
        "AM": "5", "DATA": "6", "CW-R": "7", "DATA-R": "9",
    ]

    private static func stripLeadingZeros(_ text: String) -> String? {
        guard !text.isEmpty, text.allSatisfy(\.isNumber) else {
            return nil
        }
        let trimmed = String(text.drop(while: { $0 == "0" }))
        return trimmed.isEmpty ? "0" : trimmed
    }

    private static func zeroPad(_ value: String, width: Int) -> String? {
        guard !value.isEmpty, value.allSatisfy(\.isNumber), value.count <= width else {
            return nil
        }
        return String(repeating: "0", count: width - value.count) + value
    }
}

// MARK: - RadioStateField

/// A single managed radio setting addressable in a declarative profile.
/// Pairs a CAT prefix with a codec so the planner can both read current
/// state (`readCommand` + `parse`) and write desired state (`setCommand`).
public struct RadioStateField: Sendable, Identifiable, Equatable {
    // MARK: Lifecycle

    public init(
        key: String,
        label: String,
        prefix: String,
        codec: RadioStateCodec,
        readable: Bool = true
    ) {
        self.key = key
        self.label = label
        self.prefix = prefix
        self.codec = codec
        self.readable = readable
    }

    // MARK: Public

    /// Canonical, vendor-neutral setting key — the profile address.
    public let key: String
    public let label: String
    /// CAT command prefix (Elecraft/Kenwood ASCII), e.g. `"FA"`, `"MD"`.
    public let prefix: String
    public let codec: RadioStateCodec
    /// False for settings with no CAT read route (e.g. KX2 RF Gain). These
    /// can be written blindly but never diffed or verified.
    public let readable: Bool

    public var id: String {
        key
    }

    /// The ASCII query that asks the radio for this setting's current value.
    public var readCommand: String {
        "\(prefix);"
    }

    /// Parse a raw query response (e.g. `"FA00014074000;"`) into a canonical
    /// value, or nil if it doesn't match this field.
    public func parse(response: String) -> String? {
        guard response.hasPrefix(prefix), response.hasSuffix(";") else {
            return nil
        }
        let body = response.dropFirst(prefix.count).dropLast()
        return codec.decode(String(body))
    }

    /// Build the ASCII SET command that drives this setting to `value`, or
    /// nil if the value can't be encoded.
    public func setCommand(for value: String) -> String? {
        guard let encoded = codec.encode(value) else {
            return nil
        }
        return "\(prefix)\(encoded);"
    }
}

// MARK: - KX2 spike catalog

public extension RadioStateField {
    /// Minimal field set for the read-back spike on an Elecraft KX2 over
    /// Kenwood-style ASCII CAT. `rfGain` is deliberately marked unreadable
    /// to exercise the write-only path — on a real KX2 RF Gain (menu 155)
    /// has no CAT read route, matching the note in `kx2-ft8-setup.cwmacro`.
    static let kx2Spike: [RadioStateField] = [
        RadioStateField(key: "vfoA", label: "VFO A", prefix: "FA", codec: .frequencyHz(digits: 11)),
        RadioStateField(key: "mode", label: "Mode", prefix: "MD", codec: .elecraftMode),
        RadioStateField(key: "power", label: "TX Power (W)", prefix: "PC", codec: .zeroPaddedInt(digits: 3)),
        RadioStateField(
            key: "rfGain",
            label: "RF Gain",
            prefix: "RG",
            codec: .zeroPaddedInt(digits: 3),
            readable: false
        ),
    ]

    /// Full canonical operating-state catalog for an Elecraft KX2/K3 over
    /// Kenwood ASCII CAT. Used by the `RadioIntent` system to guarantee that
    /// every intent re-asserts every operating-relevant setting, so values
    /// from one intent can't leak into the next.
    ///
    /// Today only `vfoA` / `mode` / `power` are readable (those are the
    /// fields `RadioSession`'s poll loop + protocol handler already decode).
    /// The remaining fields are marked `readable: false` so the planner
    /// emits `.blindApply` rows for them — every intent run unconditionally
    /// rewrites them. Promoting a field to `readable: true` is a follow-up
    /// piece of work: add `encodeReadX` / `decodeX` to `KenwoodProtocolHandler`,
    /// extend `RadioSession.RadioState`, wire `processFrame`, and map the
    /// key in `RadioSessionStateGateway.currentValue(forKey:)`.
    static let kx2Canonical: [RadioStateField] = [
        // Readable (already polled + decoded by RadioSession).
        RadioStateField(key: "vfoA", label: "VFO A", prefix: "FA", codec: .frequencyHz(digits: 11)),
        RadioStateField(key: "mode", label: "Mode", prefix: "MD", codec: .elecraftMode),
        RadioStateField(key: "power", label: "TX Power (W)", prefix: "PC", codec: .zeroPaddedInt(digits: 3)),

        // Blind-apply (write-only until per-field decode lands).
        RadioStateField(
            key: "bandwidth",
            label: "Bandwidth (×10 Hz)",
            prefix: "BW",
            codec: .zeroPaddedInt(digits: 4),
            readable: false
        ),
        RadioStateField(
            key: "preamp",
            label: "Preamp",
            prefix: "PA",
            codec: .zeroPaddedInt(digits: 1),
            readable: false
        ),
        RadioStateField(
            key: "attenuator",
            label: "Attenuator",
            prefix: "RA",
            codec: .zeroPaddedInt(digits: 2),
            readable: false
        ),
        RadioStateField(
            key: "noiseBlanker",
            label: "Noise Blanker",
            prefix: "NB",
            codec: .zeroPaddedInt(digits: 1),
            readable: false
        ),
        RadioStateField(
            key: "vox",
            label: "VOX",
            prefix: "VX",
            codec: .zeroPaddedInt(digits: 1),
            readable: false
        ),
        RadioStateField(
            key: "speechComp",
            label: "Speech Comp",
            prefix: "CP",
            codec: .zeroPaddedInt(digits: 3),
            readable: false
        ),
        RadioStateField(
            key: "txVfo",
            label: "TX VFO",
            prefix: "FT",
            codec: .zeroPaddedInt(digits: 1),
            readable: false
        ),
        RadioStateField(
            key: "rit",
            label: "RIT",
            prefix: "RT",
            codec: .zeroPaddedInt(digits: 1),
            readable: false
        ),
        RadioStateField(
            key: "xit",
            label: "XIT",
            prefix: "XT",
            codec: .zeroPaddedInt(digits: 1),
            readable: false
        ),
    ]
}
