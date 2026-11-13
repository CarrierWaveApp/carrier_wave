import Foundation
import GRDB

/// Per-callsign cached operator profile mirrored to the GRDB store.
///
/// Populated from prior QSOs at first launch and refreshed by QRZ lookups.
/// Lets the lookup pipeline return a result instantly from disk before the
/// network calls complete.
public struct OperatorProfileRow: Codable, Equatable, Sendable, FetchableRecord, PersistableRecord {
    // MARK: Lifecycle

    public init(
        callsign: String,
        name: String? = nil,
        firstName: String? = nil,
        nickname: String? = nil,
        qth: String? = nil,
        state: String? = nil,
        country: String? = nil,
        grid: String? = nil,
        licenseClass: String? = nil,
        source: String,
        updatedAt: Date = Date(),
        enrichedAt: Date? = nil
    ) {
        self.callsign = callsign.uppercased()
        self.name = name
        self.firstName = firstName
        self.nickname = nickname
        self.qth = qth
        self.state = state
        self.country = country
        self.grid = grid
        self.licenseClass = licenseClass
        self.source = source
        self.updatedAt = updatedAt
        self.enrichedAt = enrichedAt
    }

    // MARK: Public

    public static let databaseTableName = "operator_profiles"

    public var callsign: String
    public var name: String?
    public var firstName: String?
    public var nickname: String?
    public var qth: String?
    public var state: String?
    public var country: String?
    public var grid: String?
    public var licenseClass: String?
    public var source: String
    public var updatedAt: Date
    /// When the profile was last refreshed by a remote (QRZ) lookup.
    /// `nil` means the row was seeded from local QSO history only.
    public var enrichedAt: Date?

    /// Whether this row is non-empty enough to surface in the UI.
    public var hasMeaningfulData: Bool {
        name != nil || qth != nil || state != nil || country != nil || grid != nil
    }

    // MARK: Internal

    enum CodingKeys: String, CodingKey {
        case callsign
        case name
        case firstName = "first_name"
        case nickname
        case qth
        case state
        case country
        case grid
        case licenseClass = "license_class"
        case source
        case updatedAt = "updated_at"
        case enrichedAt = "enriched_at"
    }
}
