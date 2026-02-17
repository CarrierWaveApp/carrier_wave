import SwiftUI
import WidgetKit

@main
struct CarrierWaveWidgetBundle: WidgetBundle {
    var body: some Widget {
        SolarWidget()
        StatsWidget()
        SpotsWidget()
        ActiveSessionWidget()
    }
}
