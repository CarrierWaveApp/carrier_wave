import SwiftUI
import WidgetKit

@main
struct CarrierWaveWidgetBundle: WidgetBundle {
    var body: some Widget {
        SolarWidget()
        StatsWidget()
        SpotsWidget()
        NeedsWidget()
        ActiveSessionWidget()
        HuntWidget()
        SatellitePassLiveActivity()
        LoggingSessionLiveActivity()
    }
}
