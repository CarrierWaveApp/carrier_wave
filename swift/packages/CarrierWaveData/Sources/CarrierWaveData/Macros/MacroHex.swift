import Foundation

// MARK: - MacroHexError

enum MacroHexError: Error, Equatable {
    case oddDigitCount(String)
    case nonHexPair(String)
}

// MARK: - MacroHex

/// Parses a hex-byte string (with optional whitespace and `0x` prefixes)
/// into raw bytes. Shared helper between the catalog encoder and raw step
/// dispatch. Throws a `MacroHexError` that the executor wraps with the
/// offending step's index.
enum MacroHex {
    static func parse(_ text: String) throws -> Data {
        let cleaned = text
            .replacingOccurrences(of: "0x", with: "", options: .caseInsensitive)
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()
        guard cleaned.count.isMultiple(of: 2) else {
            throw MacroHexError.oddDigitCount(text)
        }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(cleaned.count / 2)
        var index = cleaned.startIndex
        while index < cleaned.endIndex {
            let next = cleaned.index(index, offsetBy: 2)
            guard let byte = UInt8(cleaned[index ..< next], radix: 16) else {
                throw MacroHexError.nonHexPair(String(cleaned[index ..< next]))
            }
            bytes.append(byte)
            index = next
        }
        return Data(bytes)
    }
}
