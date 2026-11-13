import Foundation

// MARK: - ServiceType

public enum ServiceType: String, Codable, CaseIterable, Sendable {
    case qrz
    case pota
    case lofi
    case hamrs
    case lotw
    case clublog
    case eqsl

    // MARK: Public

    public var displayName: String {
        switch self {
        case .qrz: "QRZ"
        case .pota: "POTA"
        case .lofi: "LoFi"
        case .hamrs: "HAMRS"
        case .lotw: "LoTW"
        case .clublog: "Club Log"
        case .eqsl: "eQSL"
        }
    }

    /// Single-letter abbreviation for compact status indicators.
    public var initial: String {
        switch self {
        case .qrz: "Q"
        case .pota: "P"
        case .lofi: "L"
        case .hamrs: "H"
        case .lotw: "W"
        case .clublog: "C"
        case .eqsl: "E"
        }
    }

    public var supportsUpload: Bool {
        switch self {
        case .qrz,
             .pota,
             .eqsl:
            true
        case .lofi,
             .lotw,
             .hamrs,
             .clublog:
            false
        }
    }

    public var supportsDownload: Bool {
        switch self {
        case .qrz,
             .pota,
             .lofi,
             .hamrs,
             .lotw,
             .eqsl:
            true
        case .clublog:
            false // "Coming Soon"
        }
    }

    /// Whether this service supports configurable sync direction.
    /// Only bidirectional services (upload + download) offer a mode picker.
    public var supportsSyncModeSelection: Bool {
        supportsUpload && supportsDownload
    }
}

// MARK: - SyncMode

/// Per-service sync direction. Only meaningful for services that support both upload and download.
public enum SyncMode: String, Codable, CaseIterable, Sendable {
    /// Upload and download (default)
    case bidirectional
    /// Upload only — skip downloading QSOs from this service
    case uploadOnly
    /// Download only — skip uploading QSOs to this service
    case downloadOnly

    // MARK: Public

    public var displayName: String {
        switch self {
        case .bidirectional: "Bidirectional"
        case .uploadOnly: "Upload Only"
        case .downloadOnly: "Download Only"
        }
    }

    public var isUploadEnabled: Bool {
        self != .downloadOnly
    }

    public var isDownloadEnabled: Bool {
        self != .uploadOnly
    }
}
