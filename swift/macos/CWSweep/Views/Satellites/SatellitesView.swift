import CarrierWaveData
import SwiftUI

// MARK: - SatellitesView

/// Root of the Satellites workspace: header strip · (pass sidebar | sky plot
/// + pass details) · synthetic waterfall · status row. Everything renders
/// from `SatellitePassModel.frame`; the model keeps ticking (CAT + rotator)
/// when the operator switches sidebar items, so this view never stops it.
struct SatellitesView: View {
    // MARK: Internal

    let model: SatellitePassModel

    var body: some View {
        VStack(spacing: 0) {
            SatellitesHeaderView(model: model, waterfallCorrected: $waterfallCorrected)
            hairline
            HStack(spacing: 0) {
                SatellitePassSidebarView(model: model)
                    .frame(width: Self.sidebarWidth)
                Rectangle()
                    .fill(SatelliteTheme.hairline)
                    .frame(width: 1)
                mainArea
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            hairline
            SatelliteWaterfallView(frame: model.frame, corrected: waterfallCorrected)
                .frame(height: Self.waterfallHeight)
            hairline
            SatelliteStatusRowView(model: model, callsign: stationCallsign)
        }
        .background(SatelliteTheme.background)
        .environment(\.colorScheme, .dark)
        .rotatorArrowKeys(model.rotator)
        .navigationTitle("CW Sweep — Satellites")
        .task {
            stationCallsign = Self.readStationCallsign()
            model.start()
        }
    }

    // MARK: Private

    private static let sidebarWidth: CGFloat = 250
    private static let skyColumnWidth: CGFloat = 360
    private static let waterfallHeight: CGFloat = 176

    @AppStorage("satellite.waterfallCorrected") private var waterfallCorrected = true
    @State private var stationCallsign = ""

    private var mainArea: some View {
        HStack(alignment: .top, spacing: 16) {
            SatelliteSkyColumnView(model: model)
                .frame(width: Self.skyColumnWidth)
            ScrollView(.vertical) {
                SatellitePassDetailView(model: model)
            }
            .scrollIndicators(.hidden)
            .frame(maxWidth: .infinity)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var hairline: some View {
        Rectangle()
            .fill(SatelliteTheme.hairline)
            .frame(height: 1)
    }

    private static func readStationCallsign() -> String {
        (try? KeychainHelper.shared.readString(for: KeychainHelper.Keys.currentCallsign))
            ?? UserDefaults.standard.string(forKey: "myCallsign")
            ?? ""
    }
}
