import CarrierWaveData
import Foundation
import SwiftData

@Model
nonisolated final class ChallengeSource {
    // MARK: Lifecycle

    init(
        id: UUID = UUID(),
        type: ChallengeSourceType,
        url: String,
        name: String,
        isEnabled: Bool = true,
        lastFetched: Date? = nil,
        lastError: String? = nil
    ) {
        self.id = id
        typeRawValue = type.rawValue
        self.url = url
        self.name = name
        self.isEnabled = isEnabled
        self.lastFetched = lastFetched
        self.lastError = lastError
    }

    // MARK: Internal

    var id = UUID()
    var typeRawValue = ChallengeSourceType.community.rawValue

    var url = ""
    var name = ""
    var isEnabled = true
    var lastFetched: Date?
    var lastError: String?

    /// Non-optional wrapper for CloudKit-required optional relationship
    var challenges: [ChallengeDefinition] {
        get { challengesRelation ?? [] }
        set { challengesRelation = newValue }
    }

    var type: ChallengeSourceType {
        get { ChallengeSourceType(rawValue: typeRawValue) ?? .community }
        set { typeRawValue = newValue.rawValue }
    }

    /// Whether this is the official Carrier Wave source
    var isOfficial: Bool {
        type == .official
    }

    /// Display name with trust indicator
    var displayNameWithTrust: String {
        switch type {
        case .official:
            "\(name) ✓"
        case .community:
            name
        case .invite:
            "\(name) (Invite)"
        }
    }

    // MARK: Private

    @Relationship(deleteRule: .cascade, inverse: \ChallengeDefinition.source)
    private var challengesRelation: [ChallengeDefinition]?
}
