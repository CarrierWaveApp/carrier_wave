import CarrierWaveCore
import Foundation

/// Re-export ServiceType from CarrierWaveCore
public typealias ServiceType = CarrierWaveCore.ServiceType

// MARK: - ImportSource

enum ImportSource: String, Codable, Sendable {
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

extension ServiceType {
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

// MARK: - HuntedSpotBehavior

enum HuntedSpotBehavior: String, CaseIterable {
    case crossOut
    case hide

    // MARK: Internal

    var label: String {
        switch self {
        case .crossOut: "Cross Out"
        case .hide: "Hide"
        }
    }
}

// MARK: - String Helpers

extension String {
    /// Returns self if non-empty, otherwise nil
    nonisolated var nonEmpty: String? {
        isEmpty ? nil : self
    }
}

extension String? {
    /// Returns self if non-nil and non-empty, otherwise nil
    nonisolated var nonEmpty: String? {
        guard let value = self, !value.isEmpty else {
            return nil
        }
        return value
    }
}
