// Amateur License Scheme
//
// Layer above `LicenseClass` (which is intrinsically US-centric: Tech /
// General / Extra). `AmateurLicenseScheme` captures the broader fact
// that different countries grant different license tiers and that we
// cannot filter band-plan segments by "Extra class privileges" for an
// operator in Germany. Use this type when you need to decide *whether*
// to apply US-specific license filtering at all; use `LicenseClass`
// when you already know you're in the USA and want the raw tier.

import Foundation

// MARK: - AmateurLicenseScheme

/// The license regime under which the operator holds their amateur
/// radio authorization.
public enum AmateurLicenseScheme: String, Codable, CaseIterable, Sendable {
    /// Three-tier FCC system (Technician, General, Extra).
    case usa
    /// RAC / IC three-tier system (Basic, Basic w/ Honours, Advanced).
    case canada
    /// Ofcom three-tier system (Foundation, Intermediate, Full).
    case uk
    /// BNetzA two-tier system (Class E, Class A).
    case germany
    /// Four-tier system (4th, 3rd, 2nd, 1st class).
    case japan
    /// ACMA Foundation / Standard / Advanced.
    case australia
    /// IARU default for countries without a bundled scheme. Callers
    /// should treat this as "don't apply privilege filtering".
    case generic

    // MARK: Public

    /// Display name for settings/profile UI.
    public var displayName: String {
        switch self {
        case .usa: "United States (FCC)"
        case .canada: "Canada (ISED)"
        case .uk: "United Kingdom (Ofcom)"
        case .germany: "Germany (BNetzA)"
        case .japan: "Japan (MIC)"
        case .australia: "Australia (ACMA)"
        case .generic: "Other / Not listed"
        }
    }

    /// Whether `BandPlan` segment privilege filtering (Tech/General/Extra)
    /// should apply to this scheme. Today only `.usa` matches — the other
    /// schemes have different privilege structures and filtering by a
    /// foreign enum would produce nonsense results.
    public var appliesUSPrivilegeFiltering: Bool {
        self == .usa
    }

    /// Best-guess scheme for the operator's home DXCC entity name as
    /// returned by `LocationPrefixLookup`. Returns `.generic` when
    /// nothing matches so the caller can skip US-specific filtering.
    public static func inferred(
        fromEntityName entityName: String?
    ) -> AmateurLicenseScheme {
        guard let entityName else {
            return .generic
        }
        let name = entityName.lowercased()
        if name.contains("united states") || name == "alaska" || name == "hawaii" {
            return .usa
        }
        if name == "canada" {
            return .canada
        }
        if name.contains("england") || name.contains("scotland")
            || name.contains("wales") || name.contains("northern ireland")
            || name == "united kingdom"
        {
            return .uk
        }
        if name == "germany" || name == "fed. rep. of germany" {
            return .germany
        }
        if name == "japan" {
            return .japan
        }
        if name == "australia" {
            return .australia
        }
        return .generic
    }
}
