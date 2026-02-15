import Foundation

// MARK: - ServiceType

public enum ServiceType: String, Codable, CaseIterable, Sendable {
    case qrz
    case pota
    case lofi
    case hamrs
    case lotw
    case clublog

    // MARK: Public

    public var displayName: String {
        switch self {
        case .qrz: "QRZ"
        case .pota: "POTA"
        case .lofi: "LoFi"
        case .hamrs: "HAMRS"
        case .lotw: "LoTW"
        case .clublog: "Club Log"
        }
    }

    public var supportsUpload: Bool {
        switch self {
        case .qrz,
             .pota,
             .clublog:
            true
        case .lofi,
             .lotw,
             .hamrs:
            false
        }
    }
}
