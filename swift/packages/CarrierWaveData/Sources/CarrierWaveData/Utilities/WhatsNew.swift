import Foundation

// MARK: - WhatsNewItemKind

public enum WhatsNewItemKind: String, Sendable, CaseIterable {
    case feature
    case improvement
    case fix

    // MARK: Public

    public var label: String {
        switch self {
        case .feature: "New"
        case .improvement: "Improved"
        case .fix: "Fixed"
        }
    }

    public var iconName: String {
        switch self {
        case .feature: "sparkles"
        case .improvement: "arrow.up.right.circle"
        case .fix: "wrench.and.screwdriver"
        }
    }
}

// MARK: - WhatsNewItem

public struct WhatsNewItem: Sendable, Identifiable, Hashable {
    // MARK: Lifecycle

    public init(
        kind: WhatsNewItemKind,
        title: String,
        detail: String? = nil,
        link: URL? = nil,
        linkLabel: String? = nil
    ) {
        self.kind = kind
        self.title = title
        self.detail = detail
        self.link = link
        self.linkLabel = linkLabel
    }

    // MARK: Public

    public let kind: WhatsNewItemKind
    public let title: String
    public let detail: String?
    /// Optional external URL surfaced as a small link below the detail.
    public let link: URL?
    /// Display text for the link button. Defaults to "Learn more" when nil.
    public let linkLabel: String?

    public var id: String {
        "\(kind.rawValue):\(title)"
    }
}

// MARK: - WhatsNewEntry

/// A single release's notes. `version` is a semver-like string matching
/// `CFBundleShortVersionString` (e.g. `"0.8.0"`). `platforms` controls which
/// apps display the entry — same monorepo ships both iOS and macOS.
public struct WhatsNewEntry: Sendable, Identifiable, Hashable {
    // MARK: Lifecycle

    public init(
        version: String,
        date: Date,
        headline: String,
        platforms: Set<WhatsNewPlatform> = [.iOS, .macOS],
        items: [WhatsNewItem]
    ) {
        self.version = version
        self.date = date
        self.headline = headline
        self.platforms = platforms
        self.items = items
    }

    // MARK: Public

    public let version: String
    public let date: Date
    public let headline: String
    public let platforms: Set<WhatsNewPlatform>
    public let items: [WhatsNewItem]

    public var id: String {
        version
    }
}

// MARK: - WhatsNewPlatform

public enum WhatsNewPlatform: String, Sendable, CaseIterable {
    case iOS
    case macOS
}

// MARK: - WhatsNewVersion

/// Lexical-safe semver comparison. Pre-release tags ("-beta") are dropped
/// before parsing so `"0.8.0-beta.1"` sorts equal to `"0.8.0"`.
public struct WhatsNewVersion: Comparable, Sendable, Hashable {
    // MARK: Lifecycle

    public init(_ raw: String) {
        let trimmed = raw.split(separator: "-").first.map(String.init) ?? raw
        let parts = trimmed.split(separator: ".").compactMap { Int($0) }
        major = parts.indices.contains(0) ? parts[0] : 0
        minor = parts.indices.contains(1) ? parts[1] : 0
        patch = parts.indices.contains(2) ? parts[2] : 0
    }

    // MARK: Public

    public let major: Int
    public let minor: Int
    public let patch: Int

    public static func < (lhs: WhatsNewVersion, rhs: WhatsNewVersion) -> Bool {
        if lhs.major != rhs.major {
            return lhs.major < rhs.major
        }
        if lhs.minor != rhs.minor {
            return lhs.minor < rhs.minor
        }
        return lhs.patch < rhs.patch
    }
}
