import Foundation

/// Radio command protocol type for iOS radio connections.
enum RigProtocol: String, Codable, CaseIterable {
    case civ
    case kenwood

    // MARK: Internal

    var displayName: String {
        switch self {
        case .civ: "CI-V (Icom)"
        case .kenwood: "Kenwood/Elecraft"
        }
    }
}
