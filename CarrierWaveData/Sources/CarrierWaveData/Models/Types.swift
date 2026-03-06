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
    case logger
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
