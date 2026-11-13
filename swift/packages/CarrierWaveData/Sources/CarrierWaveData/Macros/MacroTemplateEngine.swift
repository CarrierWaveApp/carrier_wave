import Foundation

// MARK: - MacroTemplateError

public enum MacroTemplateError: Error, Equatable, Sendable {
    case unknownToken(String)
    case undeclaredBareToken(String)
    case malformed(String)
    case notBool(template: String, raw: String)
    case notInt(template: String, raw: String)
}

// MARK: - MacroTemplateEngine

/// Resolves namespaced placeholders inside user-authored macro string
/// params. Only `{arg.<name>}` and `{ctx.<name>}` tokens are accepted —
/// bare `{name}` is rejected so authors can't accidentally rely on
/// implicit globals leaking through.
///
/// - `arg.*` resolves against the macro's declared `RadioMacroArg` set
///   plus the values supplied to `MacroExecutor.execute(runtimeArgs:)`.
/// - `ctx.*` resolves against values populated by `readField` steps or
///   externally supplied context (passed as `values["ctx.<name>"]`).
public struct MacroTemplateEngine: Sendable {
    // MARK: Lifecycle

    public init(args: [RadioMacroArg]) {
        var dict: [String: RadioMacroArg] = [:]
        for arg in args {
            dict[arg.name] = arg
        }
        argsByName = dict
    }

    // MARK: Public

    public let argsByName: [String: RadioMacroArg]

    /// Expand `{arg.<name>}` / `{ctx.<name>}` placeholders inside
    /// `template`. Throws on bare `{foo}`, malformed `{...}` runs, or
    /// missing values.
    public func resolve(_ template: String, values: [String: String]) throws -> String {
        var out = ""
        var index = template.startIndex
        while index < template.endIndex {
            let char = template[index]
            if char == "{" {
                guard let endIndex = template[index...].firstIndex(of: "}") else {
                    throw MacroTemplateError.malformed(String(template[index...]))
                }
                let token = String(template[template.index(after: index) ..< endIndex])
                if !token.hasPrefix("arg."), !token.hasPrefix("ctx.") {
                    throw MacroTemplateError.undeclaredBareToken(token)
                }
                if token.hasPrefix("arg.") {
                    let name = String(token.dropFirst(4))
                    if argsByName[name] == nil {
                        throw MacroTemplateError.unknownToken(token)
                    }
                }
                guard let value = values[token] else {
                    throw MacroTemplateError.unknownToken(token)
                }
                out.append(value)
                index = template.index(after: endIndex)
            } else {
                out.append(char)
                index = template.index(after: index)
            }
        }
        return out
    }

    /// Strict bool coercion — accepts ONLY `"true"` / `"false"` after
    /// resolution. Used by `waitUntil` / `assert` expressions.
    public func resolveBool(_ template: String, values: [String: String]) throws -> Bool {
        let raw = try resolve(template, values: values)
        switch raw {
        case "true": return true
        case "false": return false
        default: throw MacroTemplateError.notBool(template: template, raw: raw)
        }
    }

    public func resolveInt(_ template: String, values: [String: String]) throws -> Int {
        let raw = try resolve(template, values: values)
        guard let value = Int(raw) else {
            throw MacroTemplateError.notInt(template: template, raw: raw)
        }
        return value
    }
}

// MARK: - MacroFormatError

public enum MacroFormatError: Error, Equatable, Sendable {
    case nonASCII(Character)
}

// MARK: - MacroFormat

/// Format-level guards applied before a value reaches the wire. Strict
/// ASCII enforcement for `sendCW` lives here so the verifier and runtime
/// share the same predicate.
public enum MacroFormat {
    @discardableResult
    public static func applyASCII(_ text: String) throws -> String {
        for char in text where !char.isASCII {
            throw MacroFormatError.nonASCII(char)
        }
        return text
    }
}
