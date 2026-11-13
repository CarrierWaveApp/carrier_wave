import CarrierWaveCore
import UIKit

// MARK: - RemoteSweepCoordinator+Spots

//
// Spot-feed merge logic. Each `radio.spot` event arrives as one
// `RemoteSpot`; this file replaces by id, keeps newest 200, and sorts by
// `spottedAt` descending. Lifted out of `RemoteSweepCoordinator.swift`
// so the main file's class body stays inside SwiftLint's
// `type_body_length` cap.
//

extension RemoteSweepCoordinator {
    func applySpot(_ spot: RemoteSpot) {
        if let idx = spots.firstIndex(where: { $0.id == spot.id }) {
            spots[idx] = spot
        } else {
            spots.append(spot)
        }
        spots.sort { $0.spottedAt > $1.spottedAt }
        if spots.count > 200 {
            spots = Array(spots.prefix(200))
        }
    }
}
