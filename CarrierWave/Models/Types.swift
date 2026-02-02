import Foundation

// MARK: - ImportSource

enum ImportSource: String, Codable, Sendable {
    case lofi
    case adifFile
    case icloud
    case qrz
    case pota
    case hamrs
    case lotw
    case logger
}

// MARK: - ServiceType

enum ServiceType: String, Codable, CaseIterable, Sendable {
    case qrz
    case pota
    case lofi
    case hamrs
    case lotw

    // MARK: Internal

    nonisolated var displayName: String {
        switch self {
        case .qrz: "QRZ"
        case .pota: "POTA"
        case .lofi: "LoFi"
        case .hamrs: "HAMRS"
        case .lotw: "LoTW"
        }
    }

    nonisolated var supportsUpload: Bool {
        switch self {
        case .qrz,
             .pota,
             .hamrs:
            true
        case .lofi,
             .lotw:
            false
        }
    }

    /// Convert to ImportSource for comparison
    nonisolated var toImportSource: ImportSource {
        switch self {
        case .qrz: .qrz
        case .pota: .pota
        case .lofi: .lofi
        case .hamrs: .hamrs
        case .lotw: .lotw
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
