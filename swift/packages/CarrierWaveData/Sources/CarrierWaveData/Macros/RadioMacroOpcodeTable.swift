import Foundation

// MARK: - RadioMacroOpcodeTable

/// Per-protocol opcode->capability table consulted by `MacroVerifier` when
/// inferring capabilities from a `.rawBytes` step. Patterns are loaded from
/// `Resources/macro-opcodes/<protocol>.json`; each pattern is a sequence of
/// hex byte tokens with `??` as a wildcard, matched as a sliding window
/// against the parsed raw-bytes payload. Unknown payloads must be treated
/// as transmit-capable by callers — see `allRecognized(forBytesHex:)`.
public struct RadioMacroOpcodeTable: Sendable {
    // MARK: Lifecycle

    private init(patterns: [Pattern], protocolName: String) {
        self.patterns = patterns
        self.protocolName = protocolName
    }

    // MARK: Public

    public let protocolName: String

    public static func load(for protocolName: String) -> RadioMacroOpcodeTable {
        guard
            let url = Bundle.module.url(
                forResource: "macro-opcodes/\(protocolName)",
                withExtension: "json"
            ),
            let data = try? Data(contentsOf: url),
            let file = try? JSONDecoder().decode(OpcodeFile.self, from: data)
        else {
            return RadioMacroOpcodeTable(patterns: [], protocolName: protocolName)
        }
        let parsed = file.opcodes.compactMap { entry -> Pattern? in
            guard let (mask, pattern) = Self.parseMatch(entry.match) else {
                return nil
            }
            return Pattern(mask: mask, pattern: pattern, caps: entry.capabilities)
        }
        return RadioMacroOpcodeTable(patterns: parsed, protocolName: file.protocol)
    }

    /// Returns the union of capability bits contributed by every pattern
    /// that matches anywhere inside the payload. Malformed hex returns an
    /// empty set so callers can decide on a default floor.
    public func capabilities(forBytesHex hex: String) -> RadioMacroCapabilities {
        guard let bytes = Self.parseHex(hex) else {
            return RadioMacroCapabilities()
        }
        return capabilities(forBytes: bytes)
    }

    public func capabilities(forBytes bytes: Data) -> RadioMacroCapabilities {
        var combined = RadioMacroCapabilities()
        for entry in patterns where matches(entry, in: bytes) {
            combined = combined.union(entry.caps)
        }
        return combined
    }

    /// Returns `true` if at least one pattern matched the payload — i.e. the
    /// table understood enough of it to make a capability claim. Callers
    /// (the verifier) treat `false` as "unknown payload" and floor the
    /// capability set at `transmits: true`.
    public func allRecognized(forBytesHex hex: String) -> Bool {
        guard let bytes = Self.parseHex(hex) else {
            return false
        }
        return allRecognized(forBytes: bytes)
    }

    public func allRecognized(forBytes bytes: Data) -> Bool {
        patterns.contains { matches($0, in: bytes) }
    }

    // MARK: Private

    private struct Pattern {
        let mask: Data
        let pattern: Data
        let caps: RadioMacroCapabilities
    }

    private struct OpcodeFile: Decodable {
        let `protocol`: String
        let opcodes: [OpcodeEntry]
    }

    private struct OpcodeEntry: Decodable {
        // MARK: Lifecycle

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            match = try container.decode(String.self, forKey: .match)
            // Opcode JSON omits unset capability bits — decode the slice
            // permissively so authors don't have to repeat `false` for
            // every flag they don't set.
            capabilities = try container.decode(
                OpcodeCapabilityFragment.self,
                forKey: .capabilities
            ).asCapabilities()
        }

        // MARK: Internal

        enum CodingKeys: String, CodingKey {
            case match
            case capabilities
        }

        let match: String
        let capabilities: RadioMacroCapabilities
    }

    private struct OpcodeCapabilityFragment: Decodable {
        let transmits: Bool?
        let changesFrequency: Bool?
        let changesMode: Bool?
        let changesPower: Bool?
        let usesRawBytes: Bool?

        func asCapabilities() -> RadioMacroCapabilities {
            RadioMacroCapabilities(
                transmits: transmits ?? false,
                changesFrequency: changesFrequency ?? false,
                changesMode: changesMode ?? false,
                changesPower: changesPower ?? false,
                usesRawBytes: usesRawBytes ?? false
            )
        }
    }

    private let patterns: [Pattern]

    private static func parseMatch(_ source: String) -> (Data, Data)? {
        var mask = Data()
        var pattern = Data()
        for token in source.split(separator: " ") {
            if token == "??" {
                mask.append(0x00)
                pattern.append(0x00)
            } else if let byte = UInt8(token, radix: 16) {
                mask.append(0xFF)
                pattern.append(byte)
            } else {
                return nil
            }
        }
        return (mask, pattern)
    }

    /// Wraps `MacroHex.parse` so opcode-table lookup is non-throwing —
    /// malformed payloads simply fall through to the "unrecognized" path
    /// instead of crashing the verifier.
    private static func parseHex(_ hex: String) -> Data? {
        try? MacroHex.parse(hex)
    }

    private func matches(_ pattern: Pattern, in bytes: Data) -> Bool {
        let patternCount = pattern.pattern.count
        guard patternCount > 0, bytes.count >= patternCount else {
            return false
        }
        let windowCount = bytes.count - patternCount + 1
        for offset in 0 ..< windowCount {
            var ok = true
            for index in 0 ..< patternCount {
                let byte = bytes[bytes.startIndex + offset + index]
                if (byte & pattern.mask[index]) != pattern.pattern[index] {
                    ok = false
                    break
                }
            }
            if ok {
                return true
            }
        }
        return false
    }
}
