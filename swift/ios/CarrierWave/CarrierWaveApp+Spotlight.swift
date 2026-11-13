import CarrierWaveData
import CoreSpotlight
import Foundation
import WidgetKit

extension CarrierWaveApp {
    /// Reports the `home-screen` ecosystem signal if any Carrier Wave
    /// widget is currently installed on the user's Home Screen /
    /// Lock Screen.
    func detectHomeScreenWidget() async {
        let configurations = await (try? WidgetCenter.shared.currentConfigurations()) ?? []
        if !configurations.isEmpty {
            AchievementSignalService.shared.reportSignal(.homeScreen)
        }
    }

    /// Handle taps on CoreSpotlight search results. Parses the unique
    /// identifier out of the activity and re-posts as an in-app
    /// notification so downstream views can navigate to the entity.
    func handleSpotlightActivity(_ activity: NSUserActivity) {
        guard
            let identifier = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
            let entity = SpotlightConstants.parseUniqueIdentifier(identifier)
        else {
            return
        }
        switch entity {
        case let .qso(id):
            NotificationCenter.default.post(
                name: .didOpenSpotlightQSO, object: nil, userInfo: ["qsoID": id]
            )
        case let .session(id):
            NotificationCenter.default.post(
                name: .didOpenSpotlightSession, object: nil, userInfo: ["sessionID": id]
            )
        }
    }
}
