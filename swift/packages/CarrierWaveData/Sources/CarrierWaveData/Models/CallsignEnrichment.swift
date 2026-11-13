// Callsign Enrichment models.
//
// These mirror the JSON wire format produced by the Carrier Wave activities
// server's `/callsign-enrichment/dataset` endpoint. The server polls
// upstream membership lists (CWops today, SKCC and others later), normalizes
// them into per-(callsign, source) rows, and exposes the full set as a
// dataset for client-side caching.
//
// Two pieces:
//   - Wire types (`CallsignEnrichmentDataset` etc.) that match the compact
//     JSON keys the server emits.
//   - A friendlier runtime type (`CallsignEnrichmentEntry`) the iOS and
//     macOS clients use to render chips and prefill contest exchanges.

import Foundation

// MARK: - CallsignEnrichmentDatasetSource

/// Per-source metadata returned alongside the dataset.
public struct CallsignEnrichmentDatasetSource: Codable, Sendable, Hashable {
    // MARK: Lifecycle

    public init(slug: String, name: String, emoji: String?, lastFetchedAt: Date?) {
        self.slug = slug
        self.name = name
        self.emoji = emoji
        self.lastFetchedAt = lastFetchedAt
    }

    // MARK: Public

    public let slug: String
    public let name: String
    public let emoji: String?
    public let lastFetchedAt: Date?

    // MARK: Internal

    enum CodingKeys: String, CodingKey {
        case slug
        case name
        case emoji
        case lastFetchedAt = "last_fetched_at"
    }
}

// MARK: - CallsignEnrichmentDatasetMembership

/// Compact per-membership row in the dataset.
public struct CallsignEnrichmentDatasetMembership: Codable, Sendable, Hashable {
    // MARK: Lifecycle

    public init(
        sourceSlug: String,
        name: String?,
        memberNumber: String?,
        emoji: String?,
        note: String?
    ) {
        self.sourceSlug = sourceSlug
        self.name = name
        self.memberNumber = memberNumber
        self.emoji = emoji
        self.note = note
    }

    // MARK: Public

    public let sourceSlug: String
    public let name: String?
    public let memberNumber: String?
    public let emoji: String?
    public let note: String?

    // MARK: Internal

    enum CodingKeys: String, CodingKey {
        case sourceSlug = "s"
        case name = "n"
        case memberNumber = "#"
        case emoji = "e"
        case note = "t"
    }
}

// MARK: - CallsignEnrichmentDatasetEntry

/// One entry in the dataset, scoped to a single uppercase callsign.
public struct CallsignEnrichmentDatasetEntry: Codable, Sendable, Hashable {
    // MARK: Lifecycle

    public init(callsign: String, memberships: [CallsignEnrichmentDatasetMembership]) {
        self.callsign = callsign
        self.memberships = memberships
    }

    // MARK: Public

    public let callsign: String
    public let memberships: [CallsignEnrichmentDatasetMembership]

    // MARK: Internal

    enum CodingKeys: String, CodingKey {
        case callsign = "c"
        case memberships = "m"
    }
}

// MARK: - CallsignEnrichmentDataset

/// Full dataset returned by `GET /callsign-enrichment/dataset`.
public struct CallsignEnrichmentDataset: Codable, Sendable {
    // MARK: Lifecycle

    public init(
        sources: [CallsignEnrichmentDatasetSource],
        callsigns: [CallsignEnrichmentDatasetEntry],
        generatedAt: Date
    ) {
        self.sources = sources
        self.callsigns = callsigns
        self.generatedAt = generatedAt
    }

    // MARK: Public

    public let sources: [CallsignEnrichmentDatasetSource]
    public let callsigns: [CallsignEnrichmentDatasetEntry]
    public let generatedAt: Date

    // MARK: Internal

    enum CodingKeys: String, CodingKey {
        case sources
        case callsigns
        case generatedAt = "generated_at"
    }
}

// MARK: - CallsignEnrichmentMembership

/// One organisation membership for a callsign, ready for UI rendering.
public struct CallsignEnrichmentMembership: Sendable, Hashable, Codable {
    // MARK: Lifecycle

    public init(
        sourceSlug: String,
        sourceName: String,
        emoji: String?,
        name: String?,
        memberNumber: String?,
        note: String?
    ) {
        self.sourceSlug = sourceSlug
        self.sourceName = sourceName
        self.emoji = emoji
        self.name = name
        self.memberNumber = memberNumber
        self.note = note
    }

    // MARK: Public

    /// Source slug (e.g. "cwops").
    public let sourceSlug: String
    /// Display name of the source (e.g. "CWops").
    public let sourceName: String
    /// Emoji to render in the chip.
    public let emoji: String?
    /// Operator name as recorded in the source (may differ from QRZ).
    public let name: String?
    /// Member number, digits only, no `#` prefix.
    public let memberNumber: String?
    /// Free-form note left over after parsing.
    public let note: String?

    /// Canonical chip label for UI: e.g. "🎹 CWops #1532".
    public var chipLabel: String {
        let prefix = emoji.map { "\($0) " } ?? ""
        if let number = memberNumber, !number.isEmpty {
            return "\(prefix)\(sourceName) #\(number)"
        }
        return "\(prefix)\(sourceName)"
    }

    /// Exchange string for contests that take Name + Member Number
    /// (e.g. CWT). Returns nil if either piece is missing.
    public var nameAndNumberExchange: String? {
        guard let name = name?.trimmingCharacters(in: .whitespaces),
              !name.isEmpty,
              let number = memberNumber, !number.isEmpty
        else {
            return nil
        }
        return "\(name) \(number)"
    }
}

// MARK: - CallsignEnrichmentEntry

/// All memberships matched for one callsign, ready for use in the
/// callsign-card UI and contest exchange prefill.
public struct CallsignEnrichmentEntry: Sendable, Hashable, Codable {
    // MARK: Lifecycle

    public init(callsign: String, memberships: [CallsignEnrichmentMembership]) {
        self.callsign = callsign.uppercased()
        self.memberships = memberships
    }

    // MARK: Public

    public let callsign: String
    public let memberships: [CallsignEnrichmentMembership]

    public func membership(forSourceSlug slug: String) -> CallsignEnrichmentMembership? {
        memberships.first { $0.sourceSlug == slug }
    }
}

// MARK: - Dataset → runtime conversion

public extension CallsignEnrichmentDataset {
    /// Project the wire dataset into a `[callsign: CallsignEnrichmentEntry]`
    /// dictionary, resolving per-row emoji fallbacks against per-source
    /// emoji defaults. The cache uses this map for O(1) lookup.
    func indexedByCallsign() -> [String: CallsignEnrichmentEntry] {
        let sourcesBySlug: [String: CallsignEnrichmentDatasetSource] = Dictionary(
            uniqueKeysWithValues: sources.map { ($0.slug, $0) }
        )

        var result: [String: CallsignEnrichmentEntry] = [:]
        result.reserveCapacity(callsigns.count)
        for entry in callsigns {
            let memberships = entry.memberships.map { row in
                let source = sourcesBySlug[row.sourceSlug]
                return CallsignEnrichmentMembership(
                    sourceSlug: row.sourceSlug,
                    sourceName: source?.name ?? row.sourceSlug,
                    emoji: row.emoji ?? source?.emoji,
                    name: row.name,
                    memberNumber: row.memberNumber,
                    note: row.note
                )
            }
            let upper = entry.callsign.uppercased()
            result[upper] = CallsignEnrichmentEntry(
                callsign: upper,
                memberships: memberships
            )
        }
        return result
    }
}
