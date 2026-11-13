import Foundation

// MARK: - Adapter

public extension RegistryMacroDocument {
    /// Convert a server-shaped registry payload into the local
    /// `RadioMacroDocument` shape used by `MacroImportCoordinator`. This
    /// lets the existing import + verifier flow stay unchanged.
    func toRadioMacroDocument() -> RadioMacroDocument {
        let appliesToProtocols = spec.appliesTo.compactMap { RadioCommandProtocol(rawValue: $0) }
        let macroSpec = RadioMacroSpec(
            id: UUID(),
            name: spec.name,
            icon: spec.icon,
            description: spec.description,
            tags: spec.tags,
            appliesTo: appliesToProtocols,
            author: authorCallsign,
            capabilities: spec.capabilities,
            registry: RegistryRef(slug: slug, registryVersion: version, publishedAt: publishedAt),
            args: spec.args,
            steps: spec.steps
        )
        return RadioMacroDocument(format: format, macro: macroSpec)
    }
}
