import Foundation

// MARK: - RadioCommandCatalogDocument

/// Top-level shape of a `*.json` catalog file shipped in
/// `Resources/RadioCommands/`. Schema is versioned so we can evolve the
/// format without breaking older clients that ship an older catalog.
public struct RadioCommandCatalogDocument: Codable, Sendable {
    // MARK: Lifecycle

    public init(version: Int, commands: [RadioCommandSpec]) {
        self.version = version
        self.commands = commands
    }

    // MARK: Public

    public var version: Int
    public var commands: [RadioCommandSpec]
}

// MARK: - RadioCommandSpec

/// A single vendor command in the catalog. `template` is a hex-byte string
/// with `{param}` and `{param:format}` placeholders. The encoder resolves
/// placeholders against the macro's runtime args + context, parses the
/// result into bytes, and frames it for the target protocol.
public struct RadioCommandSpec: Codable, Sendable, Identifiable {
    // MARK: Lifecycle

    public init(
        id: String,
        label: String,
        rigProtocol: RadioCommandProtocol,
        category: String? = nil,
        supports: [String]? = nil,
        params: [RadioCommandParam] = [],
        template: String,
        notes: String? = nil
    ) {
        self.id = id
        self.label = label
        self.rigProtocol = rigProtocol
        self.category = category
        self.supports = supports
        self.params = params
        self.template = template
        self.notes = notes
    }

    // MARK: Public

    public let id: String
    public let label: String
    public let rigProtocol: RadioCommandProtocol
    public let category: String?
    public let supports: [String]?
    public let params: [RadioCommandParam]
    public let template: String
    public let notes: String?

    // MARK: Internal

    enum CodingKeys: String, CodingKey {
        case id
        case label
        case rigProtocol = "protocol"
        case category
        case supports
        case params
        case template
        case notes
    }
}

// MARK: - RadioCommandProtocol

public enum RadioCommandProtocol: String, Codable, Sendable, CaseIterable {
    case civ
    case kenwood
    case yaesu
    case flex
}

// MARK: - RadioCommandParam

public struct RadioCommandParam: Codable, Sendable, Identifiable {
    // MARK: Lifecycle

    public init(
        name: String,
        label: String? = nil,
        type: RadioCommandParamType,
        values: [RadioCommandParamValue]? = nil,
        min: Int? = nil,
        max: Int? = nil,
        defaultValue: String? = nil,
        encoding: String? = nil
    ) {
        self.name = name
        self.label = label
        self.type = type
        self.values = values
        self.min = min
        self.max = max
        self.defaultValue = defaultValue
        self.encoding = encoding
    }

    // MARK: Public

    public let name: String
    public let label: String?
    public let type: RadioCommandParamType
    public let values: [RadioCommandParamValue]?
    public let min: Int?
    public let max: Int?
    public let defaultValue: String?
    /// Default encoding format applied when the template references this
    /// param without an explicit `:format` hint (e.g. `bcd5` for `freqHz`).
    public let encoding: String?

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
        case encoding
    }
}

// MARK: - RadioCommandParamType

public enum RadioCommandParamType: String, Codable, Sendable, Hashable {
    case bool
    case enumeration = "enum"
    case uint8
    case uint16
    case uint32
    case uint64
    case freqHz
    case frequency
    case string
}

// MARK: - RadioCommandParamValue

/// A single discrete value of an `enum`-typed param. `encoded` is what the
/// template engine substitutes for `{param}` references — typically a hex
/// byte pair like `"01"`, but may be any literal.
public struct RadioCommandParamValue: Codable, Sendable, Identifiable, Hashable {
    // MARK: Lifecycle

    public init(id: String, label: String, encoded: String) {
        self.id = id
        self.label = label
        self.encoded = encoded
    }

    // MARK: Public

    public let id: String
    public let label: String
    public let encoded: String
}
