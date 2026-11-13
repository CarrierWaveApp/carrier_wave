import Foundation

// MARK: - RegistryRef

/// Reference to the upstream registry entry a macro was imported from.
/// Lets the editor surface "newer version available" diffs against the
/// server-side macro registry.
public struct RegistryRef: Codable, Sendable, Hashable {
    // MARK: Lifecycle

    public init(slug: String, registryVersion: Int, publishedAt: Date) {
        self.slug = slug
        self.registryVersion = registryVersion
        self.publishedAt = publishedAt
    }

    // MARK: Public

    public var slug: String
    public var registryVersion: Int
    public var publishedAt: Date
}
