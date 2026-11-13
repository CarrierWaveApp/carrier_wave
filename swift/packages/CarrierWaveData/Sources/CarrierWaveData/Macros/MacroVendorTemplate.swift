import Foundation

// MARK: - MacroVendorTemplateError

/// Errors raised while expanding a vendor catalog template — these
/// templates use bare `{name}` and `{name:format}` placeholders whose
/// names match declared catalog params, NOT user-facing macro tokens.
enum MacroVendorTemplateError: Error, Equatable {
    case unknownToken(String)
    case unsupportedFormat(token: String, format: String)
    case invalidValue(token: String, value: String, expected: String)
    case malformedTemplate(String)
}

// MARK: - MacroVendorTemplate

/// Internal template helper used by `RadioCommandCatalog` to expand
/// vendor command templates into hex/ASCII payloads. Uses the legacy
/// permissive `{name}` lookup against catalog params + macro context; the
/// strict, user-facing `MacroTemplateEngine` is intentionally separate.
struct MacroVendorTemplate {
    // MARK: Lifecycle

    init(context: MacroContext, runtimeArgs: [String: String] = [:]) {
        self.context = context
        self.runtimeArgs = runtimeArgs
    }

    // MARK: Internal

    let context: MacroContext
    let runtimeArgs: [String: String]

    func resolve(_ template: String) throws -> String {
        var result = ""
        var index = template.startIndex
        while index < template.endIndex {
            let char = template[index]
            if char == "{" {
                let next = template.index(after: index)
                if next < template.endIndex, template[next] == "{" {
                    result.append("{")
                    index = template.index(after: next)
                    continue
                }
                guard let closing = template[next...].firstIndex(of: "}") else {
                    throw MacroVendorTemplateError.malformedTemplate(template)
                }
                let token = String(template[next ..< closing])
                try result.append(expand(token: token))
                index = template.index(after: closing)
            } else if char == "}" {
                let next = template.index(after: index)
                guard next < template.endIndex, template[next] == "}" else {
                    throw MacroVendorTemplateError.malformedTemplate(template)
                }
                result.append("}")
                index = template.index(after: next)
            } else {
                result.append(char)
                index = template.index(after: index)
            }
        }
        return result
    }

    // MARK: Private

    private func expand(token rawToken: String) throws -> String {
        let parts = rawToken.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        let name = String(parts[0]).trimmingCharacters(in: .whitespaces)
        let format = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespaces) : nil

        let value = try lookup(name: name)
        guard let format else {
            return value
        }
        return try MacroVendorFormat.apply(format, to: value, token: name)
    }

    private func lookup(name: String) throws -> String {
        if let runtime = runtimeArgs[name] {
            return runtime
        }
        if let contextValue = context.value(forToken: name.uppercased()) {
            return contextValue
        }
        throw MacroVendorTemplateError.unknownToken(name)
    }
}

// MARK: - MacroVendorFormat

/// Encoding directives applied via `{name:format}` syntax inside vendor
/// catalog templates. `bcd*` and `hex*` produce hex-byte strings; `dec*`
/// produces zero-padded ASCII decimals.
enum MacroVendorFormat {
    // MARK: Internal

    static func apply(_ format: String, to value: String, token: String) throws -> String {
        switch format.lowercased() {
        case "bcd2",
             "bcd3",
             "bcd4",
             "bcd5",
             "bcd6":
            let byteCount = Int(format.dropFirst(3)) ?? 0
            return try encodeBCD(value: value, byteCount: byteCount, token: token)
        case "hex2",
             "hex4",
             "hex6",
             "hex8":
            let byteCount = (Int(format.dropFirst(3)) ?? 0) / 2
            return try encodeHex(value: value, byteCount: byteCount, token: token)
        case "ascii":
            return value
                .map { String(format: "%02X", $0.asciiValue ?? 0x20) }
                .joined(separator: " ")
        default:
            if format.hasPrefix("dec"), let width = Int(format.dropFirst(3)) {
                return try encodeDecimal(value: value, width: width, token: token)
            }
            throw MacroVendorTemplateError.unsupportedFormat(token: token, format: format)
        }
    }

    // MARK: Private

    /// Encode a decimal value as N-byte BCD, LSB-first (CI-V convention).
    /// "7032000" with byteCount 5 → "00 20 70 03 00".
    private static func encodeBCD(value: String, byteCount: Int, token: String) throws -> String {
        guard let intValue = UInt64(value.trimmingCharacters(in: .whitespaces)) else {
            throw MacroVendorTemplateError.invalidValue(
                token: token, value: value, expected: "decimal integer"
            )
        }
        var digits = String(intValue)
        let required = byteCount * 2
        if digits.count > required {
            throw MacroVendorTemplateError.invalidValue(
                token: token, value: value, expected: "≤ \(required) digits for bcd\(byteCount)"
            )
        }
        digits = String(repeating: "0", count: required - digits.count) + digits
        var bytes: [String] = []
        bytes.reserveCapacity(byteCount)
        for byteIdx in 0 ..< byteCount {
            let highIdx = digits.index(digits.startIndex, offsetBy: byteIdx * 2)
            let lowIdx = digits.index(after: highIdx)
            let high = digits[highIdx]
            let low = digits[lowIdx]
            bytes.append("\(high)\(low)")
        }
        return bytes.reversed().joined(separator: " ")
    }

    /// Zero-pad a decimal value to `width` digits.
    private static func encodeDecimal(value: String, width: Int, token: String) throws -> String {
        guard let intValue = UInt64(value.trimmingCharacters(in: .whitespaces)) else {
            throw MacroVendorTemplateError.invalidValue(
                token: token, value: value, expected: "decimal integer"
            )
        }
        let digits = String(intValue)
        if digits.count > width {
            throw MacroVendorTemplateError.invalidValue(
                token: token, value: value, expected: "≤ \(width) digits for dec\(width)"
            )
        }
        return String(repeating: "0", count: width - digits.count) + digits
    }

    /// Encode an integer as N bytes of big-endian hex.
    private static func encodeHex(value: String, byteCount: Int, token: String) throws -> String {
        guard let intValue = UInt64(value.trimmingCharacters(in: .whitespaces)) else {
            throw MacroVendorTemplateError.invalidValue(
                token: token, value: value, expected: "decimal integer"
            )
        }
        let formatString = "%0\(byteCount * 2)X"
        let hex = String(format: formatString, intValue)
        var bytes: [String] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2, limitedBy: hex.endIndex) ?? hex.endIndex
            bytes.append(String(hex[index ..< next]))
            index = next
        }
        return bytes.joined(separator: " ")
    }
}
