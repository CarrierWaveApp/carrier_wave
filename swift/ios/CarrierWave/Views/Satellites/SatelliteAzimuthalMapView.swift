import CarrierWaveCore
import CoreLocation
import SwiftUI

// MARK: - SatelliteAzimuthalMapView

/// Great-circle satellite chart replacing the MKMapView globe: range rings,
/// Natural Earth coastlines, and every ham satellite plotted by bearing and
/// distance from the observer's QTH. Rotates with the device compass unless
/// heading-locked.
struct SatelliteAzimuthalMapView: View {
    // MARK: Internal

    var positions: [SatellitePosition]
    var track: [SatellitePosition]
    /// Last-24 h community status per NORAD id (absent = AMSAT doesn't
    /// track the bird); drawn as a ring around each marker.
    var communityStatus: [Int: CommunityActivityStatus] = [:]
    /// Community reports for the selected bird, plotted at the reporter's
    /// grid square so you can see where it was actually copied.
    var reporters: [ReporterMark] = []
    var observer: CLLocationCoordinate2D?
    var positionsSyncedAt: Date
    var followsHeading: Bool
    let motion: AntennaMotionService

    @Binding var selectedNoradID: Int?

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { timeline in
                chart(size: geo.size, date: timeline.date)
            }
            .contentShape(Rectangle())
            .onTapGesture { location in
                handleTap(at: location, size: geo.size)
            }
            .gesture(
                MagnificationGesture()
                    .updating($pinchScale) { value, state, _ in
                        state = value
                    }
                    .onEnded { value in
                        zoomScale = Self.clampZoom(zoomScale * value)
                    }
            )
            .simultaneousGesture(
                DragGesture(minimumDistance: 8)
                    .onChanged { value in
                        applyPan(translation: value.translation, size: geo.size)
                    }
                    .onEnded { _ in
                        lastDragTranslation = .zero
                    }
            )
            .overlay(alignment: .topTrailing) {
                if chartCenterOverride != nil {
                    homeButton
                }
            }
        }
        .background(Color(.systemBackground))
    }

    // MARK: Private

    /// Distance rings drawn inside the antipode rim, in km.
    private static let ringDistancesKm: [Double] = [5_000, 10_000, 15_000]
    /// Extra close-in rings once zoomed far enough that the base rings
    /// have left the screen.
    private static let zoomedRingDistancesKm: [Double] = [1_000, 2_500]
    private static let maxZoom: CGFloat = 16

    /// Opening view: regional scale (~2,500 km ring in view) rather than
    /// the whole-earth disk — pinch out for the full antipode projection.
    private static let defaultZoom: CGFloat = 3

    @State private var zoomScale: CGFloat = SatelliteAzimuthalMapView.defaultZoom
    @GestureState private var pinchScale: CGFloat = 1
    /// Where the projection is centered when panned away from the QTH.
    /// nil = centered on the observer.
    @State private var chartCenterOverride: CLLocationCoordinate2D?
    /// Translation already applied during the in-flight drag, so each
    /// gesture change re-centers by only its incremental delta.
    @State private var lastDragTranslation: CGSize = .zero

    private var currentHeadingDeg: Double {
        followsHeading ? (motion.screenHeadingDeg ?? 0) : 0
    }

    /// The coordinate the projection is centered on right now.
    private var chartCenter: CLLocationCoordinate2D {
        chartCenterOverride ?? observer ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)
    }

    /// Recenter the projection on the QTH (zoom is left alone, like the
    /// system Maps location button).
    private var homeButton: some View {
        Button {
            chartCenterOverride = nil
        } label: {
            Image(systemName: "house.fill")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 40, height: 40)
                .background(.regularMaterial, in: Circle())
        }
        .accessibilityLabel("Recenter on your location")
        .padding(.trailing)
        .padding(.top, 56)
    }

    private func chart(size: CGSize, date: Date) -> some View {
        // Cache observable/model reads outside the Canvas closure.
        let chartFrame = frame(size: size)
        let displayed = displayedPositions(at: date)
        let selected = selectedNoradID
        let trackPoints = track
        let statuses = communityStatus
        let marks = reporters
        return Canvas { context, _ in
            drawRings(context: &context, frame: chartFrame)
            drawCoastlines(context: &context, frame: chartFrame)
            drawCompass(context: &context, frame: chartFrame)
            if let selected, let position = displayed.first(where: { $0.noradID == selected }) {
                drawFootprint(context: &context, frame: chartFrame, position: position)
                drawTrack(context: &context, frame: chartFrame, points: trackPoints)
                drawReporters(context: &context, frame: chartFrame, marks: marks)
            }
            drawSatellites(
                context: &context,
                frame: chartFrame,
                positions: displayed,
                selectedNoradID: selected,
                communityStatus: statuses
            )
            drawObserver(context: &context, frame: chartFrame)
        }
    }

    private static func clampZoom(_ value: CGFloat) -> CGFloat {
        min(maxZoom, max(1, value))
    }

    /// A drag moves the map's home point continuously: each incremental
    /// finger delta re-centers the projection on the coordinate that the
    /// delta pulls under the screen center, so the map tracks the finger
    /// with true re-projection (not a screen translation).
    private func applyPan(translation: CGSize, size: CGSize) {
        let delta = CGSize(
            width: translation.width - lastDragTranslation.width,
            height: translation.height - lastDragTranslation.height
        )
        lastDragTranslation = translation
        guard delta != .zero else {
            return
        }
        let current = frame(size: size)
        chartCenterOverride = current.coordinate(at: CGPoint(
            x: current.screenCenter.x - delta.width,
            y: current.screenCenter.y - delta.height
        ))
    }

    private func frame(size: CGSize) -> AzimuthalChartFrame {
        AzimuthalChartFrame(
            size: size,
            observer: chartCenter,
            headingDeg: currentHeadingDeg,
            zoom: Self.clampZoom(zoomScale * pinchScale)
        )
    }

    /// Dead-reckon each satellite forward from the last SGP4 sync so dots
    /// glide between the 5 s propagation ticks.
    private func displayedPositions(at date: Date) -> [SatellitePosition] {
        let elapsed = date.timeIntervalSince(positionsSyncedAt)
        guard elapsed > 0, elapsed < 30 else {
            return positions
        }
        return positions.map { position in
            var lon = position.longitude + position.lonRateDegPerSec * elapsed
            if lon > 180 {
                lon -= 360
            }
            if lon < -180 {
                lon += 360
            }
            return SatellitePosition(
                noradID: position.noradID,
                name: position.name,
                latitude: max(-90, min(90, position.latitude + position.latRateDegPerSec * elapsed)),
                longitude: lon,
                altitudeKm: position.altitudeKm
            )
        }
    }
}

// MARK: - Drawing

private extension SatelliteAzimuthalMapView {
    func drawRings(context: inout GraphicsContext, frame: AzimuthalChartFrame) {
        let rimColor = Color.secondary.opacity(0.5)
        var distances = Self.ringDistancesKm
        if frame.zoom >= 3 {
            distances += Self.zoomedRingDistancesKm
        }
        for distance in distances {
            let radius = CGFloat(distance / AzimuthalChartFrame.maxDistanceKm) * frame.diskRadius
            let rect = CGRect(
                x: frame.center.x - radius,
                y: frame.center.y - radius,
                width: radius * 2,
                height: radius * 2
            )
            context.stroke(
                Path(ellipseIn: rect),
                with: .color(Color.secondary.opacity(0.18)),
                lineWidth: 1
            )
        }
        let rimRect = CGRect(
            x: frame.center.x - frame.diskRadius,
            y: frame.center.y - frame.diskRadius,
            width: frame.diskRadius * 2,
            height: frame.diskRadius * 2
        )
        context.stroke(Path(ellipseIn: rimRect), with: .color(rimColor), lineWidth: 1.5)
    }

    func drawCoastlines(context: inout GraphicsContext, frame: AzimuthalChartFrame) {
        var path = Path()
        for ring in CoastlineData.continents {
            var previous: CGPoint?
            for vertex in ring {
                // Points hugging the antipode blow up to the whole rim;
                // break the stroke rather than drawing tearing artifacts.
                guard frame.angularDistance(latDeg: vertex.lat, lonDeg: vertex.lon) < 3.05 else {
                    previous = nil
                    continue
                }
                let point = frame.point(latDeg: vertex.lat, lonDeg: vertex.lon)
                if let previous, hypot(point.x - previous.x, point.y - previous.y) < frame.diskRadius / 2 {
                    path.addLine(to: point)
                } else {
                    path.move(to: point)
                }
                previous = point
            }
        }
        context.stroke(path, with: .color(Color.secondary.opacity(0.45)), lineWidth: 0.8)
    }

    func drawCompass(context: inout GraphicsContext, frame: AzimuthalChartFrame) {
        let labels: [(String, Double)] = [("N", 0), ("E", 90), ("S", 180), ("W", 270)]
        for (label, bearing) in labels {
            let position = frame.compassPoint(bearingDeg: bearing)
            let text = Text(label)
                .font(.caption2.weight(label == "N" ? .bold : .regular))
                .foregroundStyle(label == "N" ? Color.orange : Color.secondary)
            context.draw(context.resolve(text), at: position)
        }
    }

    func drawFootprint(
        context: inout GraphicsContext,
        frame: AzimuthalChartFrame,
        position: SatellitePosition
    ) {
        let earthRadius = 6_371.0
        let orbitRadius = earthRadius + position.altitudeKm
        guard orbitRadius > earthRadius else {
            return
        }
        let capRadius = acos(earthRadius / orbitRadius)
        let subLat = position.latitude * .pi / 180
        let subLon = position.longitude * .pi / 180
        var path = Path()
        for step in 0 ... 72 {
            let bearing = Double(step) / 72 * 2 * .pi
            let lat = asin(
                sin(subLat) * cos(capRadius) + cos(subLat) * sin(capRadius) * cos(bearing)
            )
            let lon = subLon + atan2(
                sin(bearing) * sin(capRadius) * cos(subLat),
                cos(capRadius) - sin(subLat) * sin(lat)
            )
            let point = frame.point(latDeg: lat * 180 / .pi, lonDeg: lon * 180 / .pi)
            if step == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()
        context.fill(path, with: .color(Color.teal.opacity(0.12)))
        context.stroke(path, with: .color(Color.teal.opacity(0.5)), lineWidth: 1)
    }

    func drawTrack(
        context: inout GraphicsContext,
        frame: AzimuthalChartFrame,
        points: [SatellitePosition]
    ) {
        guard points.count > 1 else {
            return
        }
        var path = Path()
        var previous: CGPoint?
        for position in points {
            let point = frame.point(latDeg: position.latitude, lonDeg: position.longitude)
            if let previous, hypot(point.x - previous.x, point.y - previous.y) < frame.diskRadius / 2 {
                path.addLine(to: point)
            } else {
                path.move(to: point)
            }
            previous = point
        }
        context.stroke(path, with: .color(Color.orange.opacity(0.6)), lineWidth: 2)
    }

    func drawSatellites(
        context: inout GraphicsContext,
        frame: AzimuthalChartFrame,
        positions: [SatellitePosition],
        selectedNoradID: Int?,
        communityStatus: [Int: CommunityActivityStatus]
    ) {
        for position in positions {
            let point = frame.point(latDeg: position.latitude, lonDeg: position.longitude)
            let isSelected = position.noradID == selectedNoradID
            let radius: CGFloat = isSelected ? 7 : 4
            let rect = CGRect(
                x: point.x - radius,
                y: point.y - radius,
                width: radius * 2,
                height: radius * 2
            )
            context.fill(
                Path(ellipseIn: rect),
                with: .color(isSelected ? Color.orange : Color.teal.opacity(0.85))
            )
            // Community ring: AMSAT's last-24 h colour; untracked birds get
            // no ring, quiet tracked birds a faint one.
            if let status = communityStatus[position.noradID] {
                let ringColor = status == .quiet ? Color.secondary.opacity(0.4) : status.color
                context.stroke(
                    Path(ellipseIn: rect.insetBy(dx: -2, dy: -2)),
                    with: .color(ringColor),
                    lineWidth: isSelected ? 2 : 1.5
                )
            }
            if isSelected {
                let name = Text(position.name)
                    .font(.caption2.weight(.semibold).monospaced())
                    .foregroundStyle(Color.orange)
                context.draw(
                    context.resolve(name),
                    at: CGPoint(x: point.x, y: point.y - 14)
                )
            }
        }
    }

    /// Reporter grid squares for the selected bird: small squares in the
    /// verdict colour, so "heard" clusters show where it was copied.
    func drawReporters(context: inout GraphicsContext, frame: AzimuthalChartFrame, marks: [ReporterMark]) {
        for mark in marks {
            let point = frame.point(latDeg: mark.latitude, lonDeg: mark.longitude)
            let rect = CGRect(x: point.x - 3, y: point.y - 3, width: 6, height: 6)
            context.fill(Path(roundedRect: rect, cornerRadius: 1.5), with: .color(mark.status.color))
            context.stroke(
                Path(roundedRect: rect, cornerRadius: 1.5),
                with: .color(Color(.systemBackground).opacity(0.8)),
                lineWidth: 0.8
            )
        }
    }

    func drawObserver(context: inout GraphicsContext, frame: AzimuthalChartFrame) {
        // The QTH is projected like everything else — when the chart is
        // panned to a new home point it drifts off-center accordingly.
        guard let observer else {
            return
        }
        let point = frame.point(latDeg: observer.latitude, lonDeg: observer.longitude)
        let radius: CGFloat = 3.5
        let rect = CGRect(
            x: point.x - radius,
            y: point.y - radius,
            width: radius * 2,
            height: radius * 2
        )
        context.fill(Path(ellipseIn: rect), with: .color(Color.accentColor))
        context.stroke(
            Path(ellipseIn: rect.insetBy(dx: -3, dy: -3)),
            with: .color(Color.accentColor.opacity(0.5)),
            lineWidth: 1
        )
    }

    /// Select the nearest satellite within a finger's reach; tapping empty
    /// chart deselects.
    func handleTap(at location: CGPoint, size: CGSize) {
        let chartFrame = frame(size: size)
        let displayed = displayedPositions(at: Date())
        var best: (noradID: Int, distance: CGFloat)?
        for position in displayed {
            let point = chartFrame.point(latDeg: position.latitude, lonDeg: position.longitude)
            let distance = hypot(point.x - location.x, point.y - location.y)
            if distance < 30, distance < (best?.distance ?? .infinity) {
                best = (position.noradID, distance)
            }
        }
        selectedNoradID = best?.noradID
    }
}
