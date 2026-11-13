import CarrierWaveCore
import Foundation

// MARK: - RemoteOpConnection + Waterfall

//
// Initial-snapshot helpers for the `radio.waterfall` topic. Lifted out of
// `RemoteOpConnection.swift` so that file stays inside SwiftLint's
// `type_body_length` cap as we add new topics.
//

extension RemoteOpConnection {
    func sendCurrentWaterfallSnapshot() async {
        guard let service else {
            return
        }
        let event = await MainActor.run { service.currentWaterfallClearedEvent() }
        await sendFrame(.eventWaterfallCleared(event))
    }
}
