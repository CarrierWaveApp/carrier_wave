import CarrierWaveData
import Foundation

enum StatCategoryType: String, CaseIterable, Identifiable {
    case qsls
    case entities
    case grids
    case bands
    case parks
    case frequencies
    case bestFriends
    case bestHunters

    // MARK: Internal

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .qsls: "QSLs"
        case .entities: "DXCC Entities"
        case .grids: "Grids"
        case .bands: "Bands"
        case .parks: "Activations"
        case .frequencies: "Favorite Frequencies"
        case .bestFriends: "Best Friends"
        case .bestHunters: "Best Hunters"
        }
    }

    var icon: String {
        switch self {
        case .qsls: "checkmark.seal"
        case .entities: "globe"
        case .grids: "square.grid.3x3"
        case .bands: "waveform"
        case .parks: "leaf"
        case .frequencies: "dial.medium.fill"
        case .bestFriends: "person.2.fill"
        case .bestHunters: "scope"
        }
    }
}
