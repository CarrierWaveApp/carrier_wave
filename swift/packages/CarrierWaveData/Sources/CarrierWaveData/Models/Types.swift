import CarrierWaveCore
import Foundation

/// Re-export ServiceType from CarrierWaveCore
public typealias ServiceType = CarrierWaveCore.ServiceType

// MARK: - ImportSource

public enum ImportSource: String, Codable, Sendable {
    case lofi
    case adifFile
    case icloud
    case qrz
    case pota
    case hamrs
    case lotw
    case clublog
    case eqsl
    case logger
    case scanned
    case satTracker = "sat" // CSN S.A.T. satellite tracker push (CAR-343)
    /// QSO received live from WSJT-X over its UDP broadcast (CAR-282).
    case wsjtx
}

// MARK: - ServiceType Extensions

public extension ServiceType {
    /// Convert to ImportSource for comparison
    nonisolated var toImportSource: ImportSource {
        switch self {
        case .qrz: .qrz
        case .pota: .pota
        case .lofi: .lofi
        case .hamrs: .hamrs
        case .lotw: .lotw
        case .clublog: .clublog
        case .eqsl: .eqsl
        }
    }
}

// MARK: - CommentParkAction

/// What to do with park references found in ADIF COMMENT/notes fields
public enum CommentParkAction: String, CaseIterable, Sendable {
    /// Ignore park references in comments entirely
    case ignore
    /// Treat as the other station's park (theirParkReference) — default
    case theirPark
    /// Treat as our activation park (parkReference / MY_SIG_INFO)
    case myPark

    // MARK: Public

    /// Read the current setting from UserDefaults (thread-safe)
    public static var current: CommentParkAction {
        let raw = UserDefaults.standard.string(forKey: "commentParkAction") ?? "theirPark"
        return CommentParkAction(rawValue: raw) ?? .theirPark
    }

    public var label: String {
        switch self {
        case .ignore: "Ignore"
        case .theirPark: "Their Park"
        case .myPark: "My Park"
        }
    }

    public var description: String {
        switch self {
        case .ignore: "Don't extract park references from comments"
        case .theirPark: "Set as the other station's park (hunter QSO)"
        case .myPark: "Set as your activation park (activator QSO)"
        }
    }
}

// MARK: - HuntedSpotBehavior

public enum HuntedSpotBehavior: String, CaseIterable {
    case crossOut
    case hide

    // MARK: Public

    public var label: String {
        switch self {
        case .crossOut: "Cross Out"
        case .hide: "Hide"
        }
    }
}

// MARK: - ShareMapStyle

/// Controls how QSO maps render in share cards, brag sheets, and session views.
/// Does not affect the main QSO map.
public enum ShareMapStyle: String, CaseIterable, Sendable {
    /// Standard 2D map, switching to 3D globe when span exceeds 90°
    case adaptive
    /// Always use a flat 2D map
    case flat
    /// Always use a 3D globe view
    case globe
    /// Always use azimuthal equidistant projection centered on operator
    case azimuthal
    /// Deep indigo/purple color palette
    case midnight
    /// Warm amber/brown color palette
    case warm
    /// Deep blue ocean chart color palette
    case ocean
    /// Cool grey-blue arctic/steel color palette
    case arctic
    /// Ember red-orange signal heat color palette
    case ember

    // MARK: Public

    /// Read the current setting from UserDefaults (thread-safe)
    public static var current: ShareMapStyle {
        let raw = UserDefaults.standard.string(forKey: "shareMapStyle") ?? "adaptive"
        return ShareMapStyle(rawValue: raw) ?? .adaptive
    }

    /// Whether this style uses a custom flat renderer instead of MapKit
    public var usesCustomRenderer: Bool {
        switch self {
        case .azimuthal,
             .midnight,
             .warm,
             .ocean,
             .arctic,
             .ember: true
        case .adaptive,
             .flat,
             .globe: false
        }
    }

    public var label: String {
        switch self {
        case .adaptive: "Auto (2D/3D)"
        case .flat: "2D Only"
        case .globe: "3D Only"
        case .azimuthal: "Azimuthal"
        case .midnight: "Midnight"
        case .warm: "Warm"
        case .ocean: "Ocean"
        case .arctic: "Arctic"
        case .ember: "Ember"
        }
    }

    public var description: String {
        switch self {
        case .adaptive: "Standard map for local QSOs, globe for worldwide"
        case .flat: "Always use a flat map projection"
        case .globe: "Always use a 3D globe view"
        case .azimuthal: "Azimuthal equidistant projection centered on your QTH"
        case .midnight: "Deep indigo custom map"
        case .warm: "Warm amber custom map"
        case .ocean: "Deep blue ocean chart"
        case .arctic: "Cool grey-blue steel map"
        case .ember: "Red-orange signal heat map"
        }
    }

    /// Whether to use globe/3D for the given span, considering the user's preference
    public func shouldUseGlobe(isWideSpan: Bool) -> Bool {
        switch self {
        case .adaptive: isWideSpan
        case .globe: true
        case .flat,
             .azimuthal,
             .midnight,
             .warm,
             .ocean,
             .arctic,
             .ember: false
        }
    }
}

// MARK: - String Helpers

public extension String {
    /// Returns self if non-empty, otherwise nil
    nonisolated var nonEmpty: String? {
        isEmpty ? nil : self
    }
}

public extension String? {
    /// Returns self if non-nil and non-empty, otherwise nil
    nonisolated var nonEmpty: String? {
        guard let value = self, !value.isEmpty else {
            return nil
        }
        return value
    }
}
