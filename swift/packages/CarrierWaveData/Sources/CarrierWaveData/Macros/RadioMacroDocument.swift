import Foundation

// MARK: - RadioMacroDocumentError

public enum RadioMacroDocumentError: Error, Equatable, Sendable {
    /// Decoded a `.cwmacro` blob with `format == 1`. v2 is a clean break;
    /// no migration path is provided. Re-author or re-export from a newer
    /// publisher.
    case unsupportedV1
    case unsupportedFormat(Int)
}

// MARK: - RadioMacroDocument

/// File format wrapper for a `.cwmacro` import/export blob. Versioned via
/// `format` so older apps can refuse cleanly when a newer schema appears.
public struct RadioMacroDocument: Codable, Sendable {
    // MARK: Lifecycle

    public init(format: Int = Self.currentFormat, macro: RadioMacroSpec) {
        self.format = format
        self.macro = macro
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let format = try container.decode(Int.self, forKey: .format)
        if format == 1 {
            throw RadioMacroDocumentError.unsupportedV1
        }
        if format != Self.currentFormat {
            throw RadioMacroDocumentError.unsupportedFormat(format)
        }
        self.format = format
        macro = try container.decode(RadioMacroSpec.self, forKey: .macro)
    }

    // MARK: Public

    public enum CodingKeys: String, CodingKey {
        case format
        case macro
    }

    public static let currentFormat = 2

    public var format: Int
    public var macro: RadioMacroSpec
}

// MARK: - RadioMacroSpec

/// The codable shape of a macro, mirroring the SwiftData `RadioMacro` model
/// but Sendable and standalone for import/export and round-trip testing.
public struct RadioMacroSpec: Codable, Sendable, Identifiable, Hashable {
    // MARK: Lifecycle

    public init(
        id: UUID = UUID(),
        name: String,
        icon: String? = nil,
        description: String? = nil,
        tags: [String]? = nil,
        appliesTo: [RadioCommandProtocol]? = nil,
        author: String? = nil,
        capabilities: RadioMacroCapabilities = RadioMacroCapabilities(),
        registry: RegistryRef? = nil,
        args: [RadioMacroArg] = [],
        steps: [RadioMacroStep] = []
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.description = description
        self.tags = tags
        self.appliesTo = appliesTo
        self.author = author
        self.capabilities = capabilities
        self.registry = registry
        self.args = args
        self.steps = steps
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        icon = try container.decodeIfPresent(String.self, forKey: .icon)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        tags = try container.decodeIfPresent([String].self, forKey: .tags)
        appliesTo = try container.decodeIfPresent([RadioCommandProtocol].self, forKey: .appliesTo)
        author = try container.decodeIfPresent(String.self, forKey: .author)
        capabilities = try container.decodeIfPresent(
            RadioMacroCapabilities.self, forKey: .capabilities
        ) ?? RadioMacroCapabilities()
        registry = try container.decodeIfPresent(RegistryRef.self, forKey: .registry)
        args = try container.decodeIfPresent([RadioMacroArg].self, forKey: .args) ?? []
        steps = try container.decodeIfPresent([RadioMacroStep].self, forKey: .steps) ?? []
    }

    // MARK: Public

    public enum CodingKeys: String, CodingKey {
        case id
        case name
        case icon
        case description
        case tags
        case appliesTo
        case author
        case capabilities
        case registry
        case args
        case steps
    }

    public var id: UUID
    public var name: String
    public var icon: String?
    public var description: String?
    public var tags: [String]?
    public var appliesTo: [RadioCommandProtocol]?
    public var author: String?
    public var capabilities: RadioMacroCapabilities
    public var registry: RegistryRef?
    public var args: [RadioMacroArg]
    public var steps: [RadioMacroStep]
}

// MARK: - RadioMacroArg

/// A user-visible parameter the macro asks for at invocation time. The
/// editor renders the appropriate input control per `type`; the executor
/// validates and substitutes the resulting value into placeholders.
public struct RadioMacroArg: Codable, Sendable, Identifiable, Hashable {
    // MARK: Lifecycle

    public init(
        name: String,
        label: String? = nil,
        type: RadioCommandParamType,
        values: [RadioCommandParamValue]? = nil,
        min: Int? = nil,
        max: Int? = nil,
        defaultValue: String? = nil
    ) {
        self.name = name
        self.label = label
        self.type = type
        self.values = values
        self.min = min
        self.max = max
        self.defaultValue = defaultValue
    }

    // MARK: Public

    public let name: String
    public let label: String?
    public let type: RadioCommandParamType
    public let values: [RadioCommandParamValue]?
    public let min: Int?
    public let max: Int?
    public let defaultValue: String?

    public var id: String {
        name
    }

    // MARK: Internal

    enum CodingKeys: String, CodingKey {
        case name
        case label
        case type
        case values
        case min
        case max
        case defaultValue = "default"
    }
}

// MARK: - Coding helpers

public extension RadioMacroDocument {
    static func decode(from data: Data) throws -> RadioMacroDocument {
        let decoder = JSONDecoder()
        return try decoder.decode(RadioMacroDocument.self, from: data)
    }

    func encode(pretty: Bool = true) throws -> Data {
        let encoder = JSONEncoder()
        if pretty {
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        } else {
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        }
        return try encoder.encode(self)
    }
}
