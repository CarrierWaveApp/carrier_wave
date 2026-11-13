import CarrierWaveCwFfi
import Foundation

// MARK: - ADIFCatalog

/// Canonical ADIF enumerations for use in pickers and validation.
///
/// The band/mode/submode tables are the shared Rust core's (`cw_domain::adif_catalog`);
/// this enum maps them into the Swift value types the pickers consume. The
/// US-state / Canadian-province catalog is not yet in Rust, so it lives here.
///
/// Reference: ADIF 3.1.7 (https://www.adif.org/317/ADIF_317.htm) enumerations for Band, Mode,
/// and Primary_Administrative_Subdivision.
nonisolated public enum ADIFCatalog {}

// MARK: - Mode Catalog

nonisolated public extension ADIFCatalog {
    struct Mode: Hashable, Sendable {
        // MARK: Lifecycle

        public init(code: String, category: ModeCategory, description: String) {
            self.code = code
            self.category = category
            self.description = description
        }

        init(ffi: FfiAdifMode) {
            self.init(
                code: ffi.code,
                category: ModeCategory(ffi: ffi.category),
                description: ffi.description
            )
        }

        // MARK: Public

        public let code: String
        public let category: ModeCategory
        public let description: String
    }

    enum ModeCategory: String, Hashable, Sendable, CaseIterable {
        case phone = "Phone"
        case cw = "CW"
        case digital = "Digital"
        case image = "Image"

        // MARK: Lifecycle

        init(ffi: FfiModeCategory) {
            switch ffi {
            case .phone: self = .phone
            case .cw: self = .cw
            case .digital: self = .digital
            case .image: self = .image
            }
        }
    }

    /// All ADIF 3.1.7 primary modes plus the most commonly-logged submodes,
    /// sourced from the shared Rust catalog (`cw_domain::adif_catalog`).
    static var modes: [Mode] {
        adifModes().map(Mode.init(ffi:))
    }

    /// Fast lookup by mode code (case-insensitive).
    static var modesByCode: [String: Mode] {
        var result: [String: Mode] = [:]
        for mode in modes {
            result[mode.code.uppercased()] = mode
        }
        return result
    }

    static func mode(forCode code: String) -> Mode? {
        adifModeForCode(code: code).map(Mode.init(ffi:))
    }
}

// MARK: - Band Catalog

nonisolated public extension ADIFCatalog {
    struct Band: Hashable, Sendable {
        // MARK: Lifecycle

        public init(code: String, description: String, minMHz: Double, maxMHz: Double) {
            self.code = code
            self.description = description
            self.minMHz = minMHz
            self.maxMHz = maxMHz
        }

        init(ffi: FfiAdifBand) {
            self.init(
                code: ffi.code,
                description: ffi.description,
                minMHz: ffi.minMhz,
                maxMHz: ffi.maxMhz
            )
        }

        // MARK: Public

        public let code: String
        public let description: String
        public let minMHz: Double
        public let maxMHz: Double
    }

    /// ADIF 3.1.7 band enumeration (ordered low-to-high in frequency), sourced
    /// from the shared Rust catalog (`cw_domain::adif_catalog`).
    static var bands: [Band] {
        adifBands().map(Band.init(ffi:))
    }

    static var bandsByCode: [String: Band] {
        var result: [String: Band] = [:]
        for band in bands {
            result[band.code.lowercased()] = band
        }
        return result
    }

    static func band(forCode code: String) -> Band? {
        adifBandForCode(code: code).map(Band.init(ffi:))
    }
}

// MARK: - State / Province Catalog

nonisolated public extension ADIFCatalog {
    struct StateProvince: Hashable, Sendable, Identifiable {
        // MARK: Lifecycle

        public init(code: String, name: String, country: Country) {
            self.code = code
            self.name = name
            self.country = country
        }

        // MARK: Public

        public let code: String
        public let name: String
        public let country: Country

        public var id: String {
            "\(country.rawValue):\(code)"
        }
    }

    enum Country: String, Hashable, Sendable, CaseIterable {
        case usa = "USA"
        case canada = "Canada"
    }

    /// ADIF Primary_Administrative_Subdivision codes for USA (50 states + DC).
    static let usStates: [StateProvince] = [
        .init(code: "AL", name: "Alabama", country: .usa),
        .init(code: "AK", name: "Alaska", country: .usa),
        .init(code: "AZ", name: "Arizona", country: .usa),
        .init(code: "AR", name: "Arkansas", country: .usa),
        .init(code: "CA", name: "California", country: .usa),
        .init(code: "CO", name: "Colorado", country: .usa),
        .init(code: "CT", name: "Connecticut", country: .usa),
        .init(code: "DE", name: "Delaware", country: .usa),
        .init(code: "DC", name: "District of Columbia", country: .usa),
        .init(code: "FL", name: "Florida", country: .usa),
        .init(code: "GA", name: "Georgia", country: .usa),
        .init(code: "HI", name: "Hawaii", country: .usa),
        .init(code: "ID", name: "Idaho", country: .usa),
        .init(code: "IL", name: "Illinois", country: .usa),
        .init(code: "IN", name: "Indiana", country: .usa),
        .init(code: "IA", name: "Iowa", country: .usa),
        .init(code: "KS", name: "Kansas", country: .usa),
        .init(code: "KY", name: "Kentucky", country: .usa),
        .init(code: "LA", name: "Louisiana", country: .usa),
        .init(code: "ME", name: "Maine", country: .usa),
        .init(code: "MD", name: "Maryland", country: .usa),
        .init(code: "MA", name: "Massachusetts", country: .usa),
        .init(code: "MI", name: "Michigan", country: .usa),
        .init(code: "MN", name: "Minnesota", country: .usa),
        .init(code: "MS", name: "Mississippi", country: .usa),
        .init(code: "MO", name: "Missouri", country: .usa),
        .init(code: "MT", name: "Montana", country: .usa),
        .init(code: "NE", name: "Nebraska", country: .usa),
        .init(code: "NV", name: "Nevada", country: .usa),
        .init(code: "NH", name: "New Hampshire", country: .usa),
        .init(code: "NJ", name: "New Jersey", country: .usa),
        .init(code: "NM", name: "New Mexico", country: .usa),
        .init(code: "NY", name: "New York", country: .usa),
        .init(code: "NC", name: "North Carolina", country: .usa),
        .init(code: "ND", name: "North Dakota", country: .usa),
        .init(code: "OH", name: "Ohio", country: .usa),
        .init(code: "OK", name: "Oklahoma", country: .usa),
        .init(code: "OR", name: "Oregon", country: .usa),
        .init(code: "PA", name: "Pennsylvania", country: .usa),
        .init(code: "RI", name: "Rhode Island", country: .usa),
        .init(code: "SC", name: "South Carolina", country: .usa),
        .init(code: "SD", name: "South Dakota", country: .usa),
        .init(code: "TN", name: "Tennessee", country: .usa),
        .init(code: "TX", name: "Texas", country: .usa),
        .init(code: "UT", name: "Utah", country: .usa),
        .init(code: "VT", name: "Vermont", country: .usa),
        .init(code: "VA", name: "Virginia", country: .usa),
        .init(code: "WA", name: "Washington", country: .usa),
        .init(code: "WV", name: "West Virginia", country: .usa),
        .init(code: "WI", name: "Wisconsin", country: .usa),
        .init(code: "WY", name: "Wyoming", country: .usa),
    ]

    /// ADIF codes for Canadian provinces and territories.
    static let canadianProvinces: [StateProvince] = [
        .init(code: "AB", name: "Alberta", country: .canada),
        .init(code: "BC", name: "British Columbia", country: .canada),
        .init(code: "MB", name: "Manitoba", country: .canada),
        .init(code: "NB", name: "New Brunswick", country: .canada),
        .init(code: "NL", name: "Newfoundland and Labrador", country: .canada),
        .init(code: "NS", name: "Nova Scotia", country: .canada),
        .init(code: "NT", name: "Northwest Territories", country: .canada),
        .init(code: "NU", name: "Nunavut", country: .canada),
        .init(code: "ON", name: "Ontario", country: .canada),
        .init(code: "PE", name: "Prince Edward Island", country: .canada),
        .init(code: "QC", name: "Quebec", country: .canada),
        .init(code: "SK", name: "Saskatchewan", country: .canada),
        .init(code: "YT", name: "Yukon", country: .canada),
    ]

    /// All supported states/provinces in a single flat list.
    static let stateProvinces: [StateProvince] = usStates + canadianProvinces

    static func stateProvince(forCode code: String, country: Country? = nil) -> StateProvince? {
        let upper = code.trimmingCharacters(in: .whitespaces).uppercased()
        if let country {
            return stateProvinces.first { $0.code == upper && $0.country == country }
        }
        return stateProvinces.first { $0.code == upper }
    }
}
