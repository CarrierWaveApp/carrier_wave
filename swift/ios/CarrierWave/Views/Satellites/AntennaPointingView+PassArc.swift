import SwiftUI

// MARK: - Pass arc

/// The pointing screen's pass plot (below-horizon state): the next pass's
/// arc across the sky from the engine ground track, rotated so the boom
/// azimuth is up — the same convention as the compass tape above it.
extension AntennaPointingView {
    func isBelowHorizon(_ frame: PointingFrame) -> Bool {
        if case .belowHorizon = frame.phase {
            return true
        }
        return false
    }

    @ViewBuilder
    func passArcPlot(_ frame: PointingFrame, at date: Date) -> some View {
        if case let .belowHorizon(nextPass) = frame.phase, nextPass != nil, !passArc.isEmpty {
            SatellitePassArcView(
                arc: passArc,
                pass: nextPass,
                liveAzDeg: nil,
                liveElDeg: nil,
                headingDeg: frame.pointingAzDeg ?? 0,
                now: date.addingTimeInterval(model.timeOffset)
            )
            .frame(height: 200)
        }
    }

    /// Keep the arc anchored to the first pass that hasn't set yet,
    /// re-forecasting once the current one has.
    func refreshPassArc() async {
        guard let noradID = model.selectedNoradID else {
            return
        }
        let now = Date().addingTimeInterval(model.timeOffset)
        if let first = forecast.passes.first, first.los <= now {
            forecast = await model.passForecast(for: noradID)
        }
        let anchor = forecast.passes.first { $0.los > now }?.aos
        guard anchor != passArcAnchor else {
            return
        }
        passArcAnchor = anchor
        if let anchor {
            passArc = await model.skyArc(for: noradID, from: anchor)
        } else {
            passArc = []
        }
    }
}
