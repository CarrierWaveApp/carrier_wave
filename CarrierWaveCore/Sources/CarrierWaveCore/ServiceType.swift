import Foundation

// MARK: - ServiceType

public enum ServiceType: String, Codable, CaseIterable, Sendable {
    case qrz
    case pota
    case lofi
    case hamrs
    case lotw

    // MARK: Public

    public var displayName: String {
        switch self {
        case .qrz: "QRZ"
        case .pota: "POTA"
        case .lofi: "LoFi"
        case .hamrs: "HAMRS"
        case .lotw: "LoTW"
        }
    }

    public var supportsUpload: Bool {
        switch self {
        case .qrz,
             .pota:
            true
        case .lofi,
             .lotw,
             .hamrs:
            false
        }
    }
}
