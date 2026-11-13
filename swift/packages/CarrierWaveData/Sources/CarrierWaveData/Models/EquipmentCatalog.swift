import Foundation

// MARK: - EquipmentCategory

/// Top-level equipment category for the canonical gear catalog.
public enum EquipmentCategory: String, Codable, Sendable, CaseIterable, Identifiable {
    case radio
    case antenna
    case key
    case microphone
    case accessory

    // MARK: Public

    public var id: String {
        rawValue
    }

    public var displayName: String {
        switch self {
        case .radio: "Radio"
        case .antenna: "Antenna"
        case .key: "Key"
        case .microphone: "Microphone"
        case .accessory: "Accessory"
        }
    }

    public var icon: String {
        switch self {
        case .radio: "radio"
        case .antenna: "antenna.radiowaves.left.and.right"
        case .key: "pianokeys"
        case .microphone: "mic"
        case .accessory: "wrench.and.screwdriver"
        }
    }
}

// MARK: - OperatingMode

/// Modes a piece of equipment supports.
public enum OperatingMode: String, Codable, Sendable, CaseIterable {
    case cw = "CW"
    case ssb = "SSB"
    case am = "AM"
    case fm = "FM"
    case ft8 = "FT8"
    case ft4 = "FT4"
    case digital = "DIGITAL"

    // MARK: Public

    /// Mode families for broad matching (e.g., "CW" matches CW sessions).
    public var family: String {
        switch self {
        case .cw: "CW"
        case .ssb,
             .am,
             .fm: "PHONE"
        case .ft8,
             .ft4,
             .digital: "DIGITAL"
        }
    }
}

// MARK: - PortabilityClass

/// How portable a piece of equipment is.
public enum PortabilityClass: String, Codable, Sendable {
    case pocket
    case backpack
    case portable
    case mobile
    case base

    // MARK: Public

    public var displayName: String {
        switch self {
        case .pocket: "Pocket"
        case .backpack: "Backpack"
        case .portable: "Portable"
        case .mobile: "Mobile"
        case .base: "Base Station"
        }
    }

    /// Weight class hint for scoring (lower = more portable).
    public var portabilityScore: Double {
        switch self {
        case .pocket: 1.0
        case .backpack: 0.8
        case .portable: 0.6
        case .mobile: 0.4
        case .base: 0.2
        }
    }
}

// MARK: - CatalogEntry

/// A canonical equipment entry from the shared community catalog.
///
/// Served by the activities server. Each entry has a unique slug
/// (e.g., "elecraft-kx2") and structured specs that the recommendation
/// engine uses to reason about gear compatibility and capabilities.
public struct CatalogEntry: Codable, Sendable, Identifiable, Equatable {
    // MARK: Lifecycle

    public init(
        id: String,
        name: String,
        manufacturer: String,
        category: EquipmentCategory,
        bands: [String] = [],
        modes: [OperatingMode] = [],
        maxPowerWatts: Int? = nil,
        portability: PortabilityClass = .portable,
        weightGrams: Int? = nil,
        description: String? = nil,
        aliases: [String] = [],
        imageURL: String? = nil,
        antennaConnector: String? = nil,
        powerConnector: String? = nil,
        keyJack: String? = nil,
        micJack: String? = nil
    ) {
        self.id = id
        self.name = name
        self.manufacturer = manufacturer
        self.category = category
        self.bands = bands
        self.modes = modes
        self.maxPowerWatts = maxPowerWatts
        self.portability = portability
        self.weightGrams = weightGrams
        self.description = description
        self.aliases = aliases
        self.imageURL = imageURL
        self.antennaConnector = antennaConnector
        self.powerConnector = powerConnector
        self.keyJack = keyJack
        self.micJack = micJack
    }

    // MARK: Public

    /// Unique slug (e.g., "lnr-mtr-4b", "elecraft-kx2").
    public let id: String

    /// Display name (e.g., "Mountain Topper MTR-4B").
    public let name: String

    /// Manufacturer name (e.g., "LNR Precision").
    public let manufacturer: String

    /// Equipment category.
    public let category: EquipmentCategory

    /// Bands this equipment covers (e.g., ["40m", "30m", "20m", "15m"]).
    /// Empty for accessories that aren't band-specific.
    public let bands: [String]

    /// Operating modes supported.
    /// Empty for antennas/accessories (inherit from radio).
    public let modes: [OperatingMode]

    /// Maximum power output in watts (radios only).
    public let maxPowerWatts: Int?

    /// Portability classification.
    public let portability: PortabilityClass

    /// Weight in grams (nil if unknown).
    public let weightGrams: Int?

    /// Short description for display.
    public let description: String?

    /// Alternate names and common misspellings for fuzzy matching.
    /// E.g., ["mtr4b", "mtr-4b", "mountain topper 4b"]
    public let aliases: [String]

    /// URL to product image (optional).
    public let imageURL: String?

    /// RF connector type (e.g., "BNC", "SO-239", "SMA", "N-Type").
    public let antennaConnector: String?

    /// Power connector type (e.g., "Anderson Powerpole", "barrel").
    public let powerConnector: String?

    /// Key jack type (e.g., "3.5mm", "1/4in").
    public let keyJack: String?

    /// Microphone jack type (e.g., "8-pin round", "RJ-45").
    public let micJack: String?

    /// Full display name with manufacturer.
    public var fullName: String {
        "\(manufacturer) \(name)"
    }

    /// Whether this radio supports a given mode.
    public func supportsMode(_ mode: String) -> Bool {
        let upper = mode.uppercased()
        return modes.contains { $0.rawValue == upper || $0.family == upper }
    }

    /// Whether this equipment covers a given band.
    public func supportsBand(_ band: String) -> Bool {
        bands.isEmpty || bands.contains(band)
    }
}

// MARK: - CatalogSearchResult

/// Result from fuzzy-matching a user-entered equipment name
/// against the canonical catalog.
public struct CatalogSearchResult: Sendable {
    // MARK: Lifecycle

    public init(entry: CatalogEntry, confidence: Double, originalInput: String) {
        self.entry = entry
        self.confidence = confidence
        self.originalInput = originalInput
    }

    // MARK: Public

    /// The matched catalog entry.
    public let entry: CatalogEntry

    /// Match confidence (0.0–1.0). Above 0.8 is a strong match.
    public let confidence: Double

    /// The user's original input that was matched.
    public let originalInput: String
}
