import Foundation

// MARK: - ProgramCapability

/// Capabilities that an activity program can declare.
/// Tiers are additive — a program with `adifUpload` typically also has `referenceField`.
enum ProgramCapability: String, Codable, Sendable, CaseIterable {
    /// Has a typed reference field (park, summit, lighthouse)
    case referenceField

    /// Can upload ADIF to the program's API
    case adifUpload

    /// Can browse spots for this program
    case browseSpots

    /// Can post self-spots
    case selfSpot

    /// Has a hunter/chaser workflow
    case hunter

    /// Has a reference → location lookup API (e.g., park cache)
    case locationLookup

    /// Tracks activation progress (e.g., X/10 QSOs)
    case progressTracking
}

// MARK: - ADIFFieldMapping

/// Maps program references to ADIF fields for export/upload.
struct ADIFFieldMapping: Codable, Sendable, Equatable {
    /// MY_SIG value (e.g., "POTA", "WWFF", "SOTA")
    let mySig: String?

    /// Field key for MY_SIG_INFO (defaults to the reference value)
    let mySigInfo: String?

    /// Custom SIG field name if not standard
    let sigField: String?

    /// Custom SIG_INFO field name if not standard
    let sigInfoField: String?
}

// MARK: - ActivityProgram

/// An on-air activity program definition fetched from the activities server.
/// Describes how the app should handle logging, validation, and export for this program.
struct ActivityProgram: Codable, Identifiable, Sendable, Equatable {
    /// Unique identifier slug (e.g., "pota", "sota", "wwff")
    let slug: String

    /// Full program name (e.g., "Parks on the Air")
    let name: String

    /// Short display name (e.g., "POTA")
    let shortName: String

    /// SF Symbol name for the program icon
    let icon: String

    /// Program website URL
    let website: String?

    /// Label for the reference input field (e.g., "Park Reference")
    let referenceLabel: String

    /// Regex pattern for validating references (e.g., "^[A-Za-z]{1,4}-\\d{1,6}$")
    let referenceFormat: String?

    /// Example reference for placeholder text (e.g., "K-1234")
    let referenceExample: String?

    /// Whether multiple references are allowed (POTA n-fer)
    let multiRefAllowed: Bool

    /// Minimum QSO count for a valid activation (10 for POTA, 4 for SOTA)
    let activationThreshold: Int?

    /// Whether rove mode is supported (multiple stops in one session)
    let supportsRove: Bool

    /// Program capabilities
    let capabilities: Set<ProgramCapability>

    /// ADIF field mapping for export/upload
    let adifFields: ADIFFieldMapping?

    var id: String {
        slug
    }

    // MARK: - Capability Checks

    /// Whether this program has a reference field (park, summit, etc.)
    var hasReferenceField: Bool {
        capabilities.contains(.referenceField)
    }

    /// Whether this program supports ADIF upload
    var canUpload: Bool {
        capabilities.contains(.adifUpload)
    }

    /// Whether this program has spots browsing
    var hasSpots: Bool {
        capabilities.contains(.browseSpots)
    }

    /// Whether this program supports self-spotting
    var canSelfSpot: Bool {
        capabilities.contains(.selfSpot)
    }

    /// Whether this is a casual (no-program) session
    var isCasual: Bool {
        slug == "casual"
    }
}

// MARK: - ActivityProgram Bridging

extension ActivityProgram {
    /// Bridge to the existing ActivationType enum for incremental migration.
    var activationType: ActivationType {
        ActivationType(rawValue: slug) ?? .casual
    }

    /// Create from an ActivationType for backward compatibility.
    init?(activationType: ActivationType, store: ActivityProgramStore) {
        guard let program = store.program(for: activationType.rawValue) else {
            return nil
        }
        self = program
    }
}

// MARK: - ProgramListResponse

/// Server response wrapper for the programs list endpoint.
struct ProgramListResponse: Codable, Sendable {
    let programs: [ActivityProgram]
    let version: Int
}
