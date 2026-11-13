import Foundation
import SwiftData

// MARK: - RadioMacro

/// SwiftData model for a user-authored radio macro. Steps and args are
/// serialized as JSON blobs to avoid schema migrations whenever the step
/// enum gains a case — the `format` version stored alongside is checked at
/// decode time. CloudKit sync rides the existing journal engine like other
/// CarrierWaveData models.
@Model
nonisolated public final class RadioMacro {
    // MARK: Lifecycle

    public init(
        id: UUID = UUID(),
        name: String,
        icon: String? = nil,
        macroDescription: String? = nil,
        tagsCSV: String = "",
        appliesToCSV: String = "",
        author: String? = nil,
        argsJSON: Data = Data(),
        stepsJSON: Data = Data(),
        capabilitiesJSON: Data = Data(),
        registryJSON: Data = Data(),
        format: Int = RadioMacroDocument.currentFormat,
        sortOrder: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        tombstoned: Bool = false,
        tombstoneReason: String? = nil
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.macroDescription = macroDescription
        self.tagsCSV = tagsCSV
        self.appliesToCSV = appliesToCSV
        self.author = author
        self.argsJSON = argsJSON
        self.stepsJSON = stepsJSON
        self.capabilitiesJSON = capabilitiesJSON
        self.registryJSON = registryJSON
        self.format = format
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.tombstoned = tombstoned
        self.tombstoneReason = tombstoneReason
    }

    // MARK: Public

    @Attribute(.unique) public var id = UUID()
    public var name: String = ""
    public var icon: String?
    public var macroDescription: String?
    public var tagsCSV: String = ""
    public var appliesToCSV: String = ""
    public var author: String?
    public var argsJSON = Data()
    public var stepsJSON = Data()
    public var capabilitiesJSON = Data()
    public var registryJSON = Data()
    public var format: Int = RadioMacroDocument.currentFormat
    public var sortOrder: Int = 0
    public var createdAt = Date()
    public var updatedAt = Date()
    public var tombstoned: Bool = false
    public var tombstoneReason: String?
    public var cloudDirtyFlag = false

    public var tags: [String] {
        get { tagsCSV.split(separator: ",").map { String($0) } }
        set {
            tagsCSV = newValue.joined(separator: ",")
            updatedAt = Date()
        }
    }

    public var appliesTo: [RadioCommandProtocol] {
        get {
            appliesToCSV
                .split(separator: ",")
                .compactMap { RadioCommandProtocol(rawValue: String($0)) }
        }
        set {
            appliesToCSV = newValue.map(\.rawValue).joined(separator: ",")
            updatedAt = Date()
        }
    }

    public var args: [RadioMacroArg] {
        get {
            guard !argsJSON.isEmpty else {
                return []
            }
            return (try? JSONDecoder().decode([RadioMacroArg].self, from: argsJSON)) ?? []
        }
        set {
            argsJSON = (try? JSONEncoder().encode(newValue)) ?? Data()
            updatedAt = Date()
        }
    }

    public var steps: [RadioMacroStep] {
        get {
            guard !stepsJSON.isEmpty else {
                return []
            }
            return (try? JSONDecoder().decode([RadioMacroStep].self, from: stepsJSON)) ?? []
        }
        set {
            stepsJSON = (try? JSONEncoder().encode(newValue)) ?? Data()
            updatedAt = Date()
        }
    }

    public var capabilities: RadioMacroCapabilities {
        get {
            guard !capabilitiesJSON.isEmpty else {
                return RadioMacroCapabilities()
            }
            return (try? JSONDecoder().decode(RadioMacroCapabilities.self, from: capabilitiesJSON))
                ?? RadioMacroCapabilities()
        }
        set {
            capabilitiesJSON = (try? JSONEncoder().encode(newValue)) ?? Data()
            updatedAt = Date()
        }
    }

    public var registry: RegistryRef? {
        get {
            guard !registryJSON.isEmpty else {
                return nil
            }
            return try? JSONDecoder().decode(RegistryRef.self, from: registryJSON)
        }
        set {
            if let newValue {
                registryJSON = (try? JSONEncoder().encode(newValue)) ?? Data()
            } else {
                registryJSON = Data()
            }
            updatedAt = Date()
        }
    }

    public static func from(spec: RadioMacroSpec, sortOrder: Int = 0) -> RadioMacro {
        let macro = RadioMacro(
            id: spec.id,
            name: spec.name,
            icon: spec.icon,
            macroDescription: spec.description,
            author: spec.author,
            sortOrder: sortOrder
        )
        macro.tags = spec.tags ?? []
        macro.appliesTo = spec.appliesTo ?? []
        macro.args = spec.args
        macro.steps = spec.steps
        macro.capabilities = spec.capabilities
        macro.registry = spec.registry
        return macro
    }

    public func toSpec() -> RadioMacroSpec {
        RadioMacroSpec(
            id: id,
            name: name,
            icon: icon,
            description: macroDescription,
            tags: tags.isEmpty ? nil : tags,
            appliesTo: appliesTo.isEmpty ? nil : appliesTo,
            author: author,
            capabilities: capabilities,
            registry: registry,
            args: args,
            steps: steps
        )
    }
}
