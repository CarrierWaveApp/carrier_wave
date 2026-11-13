import Foundation

// MARK: - RadioMacroStep

/// A single step in a `RadioMacro`. Cases mirror `macro-step-schema.json`
/// 1:1 — codegen produces matching Rust/Swift artifacts (capability
/// inference, decode tables).
///
/// **Typed associated values.** Numeric and bool params carry their
/// concrete type; only string params can contain `{arg.<name>}` /
/// `{ctx.<name>}` placeholders that `MacroTemplateEngine` resolves at
/// dispatch.
///
/// `kind` is the discriminator in JSON encoding. Adding a new kind is a
/// contract change shipped in lockstep with codegen + bridge firmware —
/// vendor-specific commands belong in the catalog, not as new cases.
public enum RadioMacroStep: Codable, Hashable, Sendable {
    case delay(durationMs: UInt64)
    case setFrequency(hz: UInt64)
    case setMode(mode: String)
    case setPowerWatts(watts: UInt64)
    case setPTT(on: Bool)
    case sendCW(text: String)
    case vendorCommand(commandId: String, args: [String: String]?)
    case rawBytes(protocol: String, bytes: String)
    case readField(field: String, into: String)
    case waitUntil(expr: String, timeoutMs: UInt64)
    case assert(expr: String, message: String)

    // MARK: Public

    // MARK: - Kind discriminator

    public enum Kind: String, Codable, CaseIterable, Sendable {
        case delay
        case setFrequency
        case setMode
        case setPowerWatts
        case setPTT
        case sendCW
        case vendorCommand
        case rawBytes
        case readField
        case waitUntil
        case assert
    }

    public var kind: Kind {
        switch self {
        case .delay: .delay
        case .setFrequency: .setFrequency
        case .setMode: .setMode
        case .setPowerWatts: .setPowerWatts
        case .setPTT: .setPTT
        case .sendCW: .sendCW
        case .vendorCommand: .vendorCommand
        case .rawBytes: .rawBytes
        case .readField: .readField
        case .waitUntil: .waitUntil
        case .assert: .assert
        }
    }

    /// Stable, human-readable rendering of vendor-command arguments,
    /// e.g. `menu=1, value=on`. Keys are sorted so the output is
    /// deterministic regardless of dictionary iteration order. Shared by
    /// the iOS/macOS step summaries and the registry diff helper.
    public static func formatVendorArgs(_ args: [String: String]) -> String {
        args
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: ", ")
    }
}

// MARK: - Codable

public extension RadioMacroStep {
    enum CodingKeys: String, CodingKey {
        case kind
        case durationMs
        case hz
        case mode
        case watts
        case on
        case text
        case commandId
        case args
        case rigProtocol = "protocol"
        case bytes
        case field
        case into
        case expr
        case timeoutMs
        case message
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .delay:
            self = try .delay(durationMs: container.decode(UInt64.self, forKey: .durationMs))
        case .setFrequency:
            self = try .setFrequency(hz: container.decode(UInt64.self, forKey: .hz))
        case .setMode:
            self = try .setMode(mode: container.decode(String.self, forKey: .mode))
        case .setPowerWatts:
            self = try .setPowerWatts(watts: container.decode(UInt64.self, forKey: .watts))
        case .setPTT:
            self = try .setPTT(on: container.decode(Bool.self, forKey: .on))
        case .sendCW:
            self = try .sendCW(text: container.decode(String.self, forKey: .text))
        case .vendorCommand:
            self = try .vendorCommand(
                commandId: container.decode(String.self, forKey: .commandId),
                args: container.decodeIfPresent([String: String].self, forKey: .args)
            )
        case .rawBytes:
            self = try .rawBytes(
                protocol: container.decode(String.self, forKey: .rigProtocol),
                bytes: container.decode(String.self, forKey: .bytes)
            )
        case .readField:
            self = try .readField(
                field: container.decode(String.self, forKey: .field),
                into: container.decode(String.self, forKey: .into)
            )
        case .waitUntil:
            self = try .waitUntil(
                expr: container.decode(String.self, forKey: .expr),
                timeoutMs: container.decode(UInt64.self, forKey: .timeoutMs)
            )
        case .assert:
            self = try .assert(
                expr: container.decode(String.self, forKey: .expr),
                message: container.decode(String.self, forKey: .message)
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        switch self {
        case let .delay(durationMs):
            try container.encode(durationMs, forKey: .durationMs)
        case let .setFrequency(hz):
            try container.encode(hz, forKey: .hz)
        case let .setMode(mode):
            try container.encode(mode, forKey: .mode)
        case let .setPowerWatts(watts):
            try container.encode(watts, forKey: .watts)
        case let .setPTT(on):
            try container.encode(on, forKey: .on)
        case let .sendCW(text):
            try container.encode(text, forKey: .text)
        case let .vendorCommand(commandId, args):
            try container.encode(commandId, forKey: .commandId)
            if let args, !args.isEmpty {
                try container.encode(args, forKey: .args)
            }
        case let .rawBytes(protocolName, bytes):
            try container.encode(protocolName, forKey: .rigProtocol)
            try container.encode(bytes, forKey: .bytes)
        case let .readField(field, into):
            try container.encode(field, forKey: .field)
            try container.encode(into, forKey: .into)
        case let .waitUntil(expr, timeoutMs):
            try container.encode(expr, forKey: .expr)
            try container.encode(timeoutMs, forKey: .timeoutMs)
        case let .assert(expr, message):
            try container.encode(expr, forKey: .expr)
            try container.encode(message, forKey: .message)
        }
    }
}
