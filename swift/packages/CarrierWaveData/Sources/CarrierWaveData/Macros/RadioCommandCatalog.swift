import Foundation
import OSLog

// MARK: - RadioCommandCatalogError

public enum RadioCommandCatalogError: Error, Equatable, Sendable {
    case missingCommand(id: String)
    case missingRequiredArg(command: String, arg: String)
    case unknownEnumValue(command: String, arg: String, value: String)
    case argOutOfRange(command: String, arg: String, value: String, min: Int?, max: Int?)
    case invalidArgValue(command: String, arg: String, value: String, expected: String)
    case malformedTemplate(command: String, detail: String)
}

// MARK: - RadioCommandCatalog

/// In-memory registry of vendor command specs loaded from JSON. The catalog
/// is the data-driven half of the macro system: adding a new CI-V command
/// requires shipping (or hot-loading) a new JSON entry, not a Swift change.
///
/// Specs are merged in insertion order — a later spec with the same `id`
/// overrides an earlier one. This lets a user-imported catalog overlay the
/// bundled one without rebuilding.
public final class RadioCommandCatalog: @unchecked Sendable {
    // MARK: Lifecycle

    public init(documents: [RadioCommandCatalogDocument] = []) {
        for doc in documents {
            register(doc)
        }
    }

    // MARK: Public

    /// Process-wide catalog — populated by `loadBundled()` at startup and
    /// extended by user-imported catalogs.
    public static let shared = RadioCommandCatalog()

    public var allCommands: [RadioCommandSpec] {
        lock.lock()
        defer { lock.unlock() }
        return Array(commands.values).sorted { $0.id < $1.id }
    }

    public func register(_ document: RadioCommandCatalogDocument) {
        lock.lock()
        defer { lock.unlock() }
        for spec in document.commands {
            commands[spec.id] = spec
        }
    }

    public func command(id: String) -> RadioCommandSpec? {
        lock.lock()
        defer { lock.unlock() }
        return commands[id]
    }

    public func commands(forProtocol rigProtocol: RadioCommandProtocol) -> [RadioCommandSpec] {
        allCommands.filter { $0.rigProtocol == rigProtocol }
    }

    /// Loads every `*.json` file under `Resources/RadioCommands/` in the
    /// CarrierWaveData bundle. Safe to call multiple times — duplicates
    /// override.
    public func loadBundled() {
        loadBundled(bundle: .module)
    }

    /// Test/seed hook — load `*.json` from `RadioCommands/` in an arbitrary
    /// bundle. Production callers should prefer the no-arg overload.
    public func loadBundled(bundle: Bundle) {
        guard let urls = bundle.urls(forResourcesWithExtension: "json", subdirectory: "RadioCommands")
        else {
            Self.log.error("No RadioCommands bundle subdirectory found")
            return
        }
        let decoder = JSONDecoder()
        for url in urls.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            do {
                let data = try Data(contentsOf: url)
                let document = try decoder.decode(RadioCommandCatalogDocument.self, from: data)
                register(document)
            } catch {
                Self.log.error("Failed to load catalog \(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
    }

    // MARK: Private

    private static let log = Logger(subsystem: "app.carrierwave.data", category: "RadioCommandCatalog")

    private let lock = NSLock()
    private var commands: [String: RadioCommandSpec] = [:]
}

// MARK: - RadioCommandSpec + encoding

public extension RadioCommandSpec {
    /// Resolve the catalog template into the raw payload bytes (CI-V: cmd +
    /// sub + data; Kenwood: ASCII command before any trailing `;`). Framing
    /// (CI-V preamble/address/terminator, Kenwood terminator) is added by
    /// the executor at dispatch time using the connected radio's address.
    func encodePayload(args: [String: String], context: MacroContext) throws -> Data {
        let vendor = MacroVendorTemplate(context: context, runtimeArgs: args)
        let resolvedArgs = try buildResolvedArgs(callerArgs: args, vendor: vendor)
        let resolved = try resolveTemplate(args: resolvedArgs, context: context)
        switch rigProtocol {
        case .civ,
             .flex:
            return try parseHexBytes(resolved)
        case .kenwood,
             .yaesu:
            return Data(resolved.utf8)
        }
    }

    private func buildResolvedArgs(
        callerArgs: [String: String],
        vendor: MacroVendorTemplate
    ) throws -> [String: String] {
        var resolved: [String: String] = [:]
        for param in params {
            let raw = try resolveArgRaw(param: param, callerArgs: callerArgs, vendor: vendor)
            resolved[param.name] = try coerce(param: param, raw: raw)
        }
        return resolved
    }

    private func resolveArgRaw(
        param: RadioCommandParam,
        callerArgs: [String: String],
        vendor: MacroVendorTemplate
    ) throws -> String {
        let raw = callerArgs[param.name] ?? param.defaultValue
        guard let raw else {
            throw RadioCommandCatalogError.missingRequiredArg(command: id, arg: param.name)
        }
        do {
            return try vendor.resolve(raw)
        } catch {
            throw RadioCommandCatalogError.invalidArgValue(
                command: id, arg: param.name, value: raw, expected: "resolvable template"
            )
        }
    }

    private func coerce(param: RadioCommandParam, raw: String) throws -> String {
        switch param.type {
        case .enumeration:
            guard let match = param.values?.first(where: { $0.id == raw }) else {
                throw RadioCommandCatalogError.unknownEnumValue(
                    command: id, arg: param.name, value: raw
                )
            }
            return match.encoded
        case .bool:
            return try coerceBool(raw, param: param)
        case .uint8,
             .uint16,
             .uint32,
             .uint64,
             .freqHz,
             .frequency:
            return try coerceUInt(raw, param: param)
        case .string:
            return raw
        }
    }

    private func coerceBool(_ raw: String, param: RadioCommandParam) throws -> String {
        switch raw.lowercased() {
        case "true",
             "1",
             "on",
             "yes": return "1"
        case "false",
             "0",
             "off",
             "no": return "0"
        default:
            throw RadioCommandCatalogError.invalidArgValue(
                command: id, arg: param.name, value: raw, expected: "Bool"
            )
        }
    }

    private func coerceUInt(_ raw: String, param: RadioCommandParam) throws -> String {
        guard let value = UInt64(raw.trimmingCharacters(in: .whitespaces)) else {
            throw RadioCommandCatalogError.invalidArgValue(
                command: id, arg: param.name, value: raw, expected: "unsigned integer"
            )
        }
        if let minimum = param.min, Int(value) < minimum {
            throw RadioCommandCatalogError.argOutOfRange(
                command: id, arg: param.name, value: raw, min: minimum, max: param.max
            )
        }
        if let maximum = param.max, Int(value) > maximum {
            throw RadioCommandCatalogError.argOutOfRange(
                command: id, arg: param.name, value: raw, min: param.min, max: maximum
            )
        }
        return String(value)
    }

    private func resolveTemplate(
        args: [String: String],
        context: MacroContext
    ) throws -> String {
        // Apply per-param default encoding by rewriting bare {name} to {name:encoding}
        var rewritten = template
        for param in params {
            guard let encoding = param.encoding else {
                continue
            }
            rewritten = rewritten.replacingOccurrences(
                of: "{\(param.name)}",
                with: "{\(param.name):\(encoding)}"
            )
        }
        let vendor = MacroVendorTemplate(context: context, runtimeArgs: args)
        return try vendor.resolve(rewritten)
    }

    private func parseHexBytes(_ text: String) throws -> Data {
        let cleaned = text
            .replacingOccurrences(of: "0x", with: "", options: .caseInsensitive)
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()
        guard cleaned.count.isMultiple(of: 2) else {
            throw RadioCommandCatalogError.malformedTemplate(
                command: id, detail: "odd hex digit count after resolution: '\(text)'"
            )
        }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(cleaned.count / 2)
        var index = cleaned.startIndex
        while index < cleaned.endIndex {
            let next = cleaned.index(index, offsetBy: 2)
            guard let byte = UInt8(cleaned[index ..< next], radix: 16) else {
                throw RadioCommandCatalogError.malformedTemplate(
                    command: id, detail: "non-hex pair near '\(cleaned[index ..< next])'"
                )
            }
            bytes.append(byte)
            index = next
        }
        return Data(bytes)
    }
}
