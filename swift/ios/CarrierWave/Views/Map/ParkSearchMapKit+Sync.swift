// Overlay subclasses, annotation wrappers, SwiftUI-hosting annotation views,
// and the diff helpers `ParkSearchMapKit.Coordinator` uses to push the
// SwiftUI parent's data into the underlying MKMapView. Kept in this file so
// the main UIViewRepresentable stays under the 500-line cap and the sync
// helpers all live next to the types they touch.

import CarrierWaveData
import CoreLocation
import MapKit
import SwiftUI

// MARK: - BoundaryFillOverlay

nonisolated final class BoundaryFillOverlay: MKPolygon {
    var parkReference: String?
}

// MARK: - BoundarySkirtOverlay

nonisolated final class BoundarySkirtOverlay: MKPolygon {
    var parkReference: String?
}

// MARK: - TrailLineOverlay

nonisolated final class TrailLineOverlay: MKPolyline {
    var trailReference: String?
}

// MARK: - TrailSkirtOverlay

nonisolated final class TrailSkirtOverlay: MKPolygon {
    var trailReference: String?
}

// MARK: - ParkMapAnnotation

final class ParkMapAnnotation: NSObject, MKAnnotation {
    // MARK: Lifecycle

    init(park: POTAPark, latitude: Double, longitude: Double, hasBoundary: Bool) {
        self.park = park
        coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        self.hasBoundary = hasBoundary
    }

    // MARK: Internal

    let park: POTAPark
    let coordinate: CLLocationCoordinate2D
    var hasBoundary: Bool

    var title: String? {
        park.reference
    }
}

// MARK: - SummitMapAnnotation

final class SummitMapAnnotation: NSObject, MKAnnotation {
    // MARK: Lifecycle

    init(summit: SOTASummit, latitude: Double, longitude: Double) {
        self.summit = summit
        coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    // MARK: Internal

    let summit: SOTASummit
    let coordinate: CLLocationCoordinate2D

    var title: String? {
        summit.code
    }
}

// MARK: - ParkAnnotationView

final class ParkAnnotationView: MKAnnotationView {
    // MARK: Lifecycle

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        canShowCallout = false
        backgroundColor = .clear
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    // MARK: Internal

    static let reuseID = "ParkPin"

    static func register(on map: MKMapView) {
        map.register(ParkAnnotationView.self, forAnnotationViewWithReuseIdentifier: reuseID)
    }

    static func dequeue(
        on map: MKMapView,
        for annotation: ParkMapAnnotation,
        selection: MapSelection?
    ) -> ParkAnnotationView {
        let view = map.dequeueReusableAnnotationView(
            withIdentifier: reuseID, for: annotation
        ) as? ParkAnnotationView ?? ParkAnnotationView(annotation: annotation, reuseIdentifier: reuseID)
        view.annotation = annotation
        view.refresh(selection: selection)
        return view
    }

    func refresh(selection: MapSelection?) {
        guard let park = (annotation as? ParkMapAnnotation) else {
            return
        }
        let isSelected = selection?.parkReference == park.park.reference
        let root = ParkPinView(
            park: park.park,
            hasBoundary: park.hasBoundary,
            isSelected: isSelected
        )
        if let host = hostingController {
            host.rootView = root
        } else {
            let host = UIHostingController(rootView: root)
            host.view.backgroundColor = .clear
            host.view.translatesAutoresizingMaskIntoConstraints = false
            host.disableSafeArea()
            addSubview(host.view)
            NSLayoutConstraint.activate([
                host.view.centerXAnchor.constraint(equalTo: centerXAnchor),
                host.view.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
            hostingController = host
        }
        sizeToFitHosted()
    }

    // MARK: Private

    private var hostingController: UIHostingController<ParkPinView>?

    private func sizeToFitHosted() {
        guard let host = hostingController else {
            return
        }
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        let size = host.view.intrinsicContentSize == .zero
            ? host.view.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
            : host.view.intrinsicContentSize
        bounds = CGRect(origin: .zero, size: size)
        centerOffset = CGPoint(x: 0, y: -size.height / 2)
    }
}

// MARK: - SummitAnnotationView

final class SummitAnnotationView: MKAnnotationView {
    // MARK: Lifecycle

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        canShowCallout = false
        backgroundColor = .clear
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    // MARK: Internal

    static let reuseID = "SummitPin"

    static func register(on map: MKMapView) {
        map.register(SummitAnnotationView.self, forAnnotationViewWithReuseIdentifier: reuseID)
    }

    static func dequeue(
        on map: MKMapView,
        for annotation: SummitMapAnnotation,
        selection: MapSelection?
    ) -> SummitAnnotationView {
        let view = map.dequeueReusableAnnotationView(
            withIdentifier: reuseID, for: annotation
        ) as? SummitAnnotationView ?? SummitAnnotationView(annotation: annotation, reuseIdentifier: reuseID)
        view.annotation = annotation
        view.refresh(selection: selection)
        return view
    }

    func refresh(selection: MapSelection?) {
        guard let summit = (annotation as? SummitMapAnnotation) else {
            return
        }
        let isSelected: Bool = if case let .summit(selected) = selection {
            selected.code == summit.summit.code
        } else {
            false
        }
        let root = SummitPinView(summit: summit.summit, isSelected: isSelected)
        if let host = hostingController {
            host.rootView = root
        } else {
            let host = UIHostingController(rootView: root)
            host.view.backgroundColor = .clear
            host.view.translatesAutoresizingMaskIntoConstraints = false
            host.disableSafeArea()
            addSubview(host.view)
            NSLayoutConstraint.activate([
                host.view.centerXAnchor.constraint(equalTo: centerXAnchor),
                host.view.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
            hostingController = host
        }
        sizeToFitHosted()
    }

    // MARK: Private

    private var hostingController: UIHostingController<SummitPinView>?

    private func sizeToFitHosted() {
        guard let host = hostingController else {
            return
        }
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        let size = host.view.intrinsicContentSize == .zero
            ? host.view.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
            : host.view.intrinsicContentSize
        bounds = CGRect(origin: .zero, size: size)
        centerOffset = CGPoint(x: 0, y: -size.height / 2)
    }
}

private extension UIHostingController {
    /// MKAnnotationView is not a UIViewController, so the hosting controller
    /// doesn't know its safe-area context. Without this, intrinsic content
    /// size picks up an unwanted inset and the pin floats above the anchor.
    func disableSafeArea() {
        safeAreaRegions = []
    }
}

// MARK: - Coordinator sync

extension ParkSearchMapKit.Coordinator {
    // MARK: - Radar

    func syncRadar(on map: MKMapView, enabled: Bool) {
        if enabled, radarOverlay == nil {
            let overlay = MKTileOverlay(urlTemplate: WeatherRadarService.radarTileURLTemplate)
            overlay.canReplaceMapContent = false
            overlay.minimumZ = 1
            overlay.maximumZ = 12
            map.addOverlay(overlay, level: .aboveLabels)
            radarOverlay = overlay
        } else if !enabled, let overlay = radarOverlay {
            map.removeOverlay(overlay)
            radarOverlay = nil
        }
    }

    // MARK: - Boundaries

    func syncBoundaries(on map: MKMapView, boundaries: [ParkBoundary], isZoomedIn: Bool) {
        let desiredRefs = Set(boundaries.map(\.reference))
        let zoomFlipped = isZoomedIn != lastZoomedIn

        // Remove gone boundaries (or all of them if zoom flipped, since the
        // skirt visibility / exterior choice changes).
        for ref in boundaryOverlays.keys where !desiredRefs.contains(ref) || zoomFlipped {
            if let overlays = boundaryOverlays[ref] {
                map.removeOverlays(overlays)
                boundaryOverlays[ref] = nil
            }
            if let overlays = skirtOverlays[ref] {
                map.removeOverlays(overlays)
                skirtOverlays[ref] = nil
            }
        }

        for boundary in boundaries {
            let needsAdd = boundaryOverlays[boundary.reference] == nil
            if !needsAdd {
                continue
            }
            var fills: [BoundaryFillOverlay] = []
            var skirts: [BoundarySkirtOverlay] = []
            for polygon in boundary.mergedPolygons {
                let coords = isZoomedIn ? polygon.exterior : polygon.zoomedOutExterior
                let fill = polygonOverlay(BoundaryFillOverlay.self, coordinates: coords)
                fill.parkReference = boundary.reference
                fills.append(fill)
                if isZoomedIn {
                    let skirt = polygonOverlay(BoundarySkirtOverlay.self, coordinates: polygon.skirt)
                    skirt.parkReference = boundary.reference
                    skirts.append(skirt)
                }
            }
            // Skirts go below fills so the fill outline stays crisp.
            map.addOverlays(skirts, level: .aboveRoads)
            map.addOverlays(fills, level: .aboveRoads)
            boundaryOverlays[boundary.reference] = fills
            if !skirts.isEmpty {
                skirtOverlays[boundary.reference] = skirts
            }
        }
        lastZoomedIn = isZoomedIn
    }

    // MARK: - Trails

    func syncTrails(on map: MKMapView, trails: [TrailBoundary]) {
        let desiredRefs = Set(trails.map(\.reference))
        for ref in trailLineOverlays.keys where !desiredRefs.contains(ref) {
            if let overlays = trailLineOverlays[ref] {
                map.removeOverlays(overlays)
                trailLineOverlays[ref] = nil
            }
            if let overlays = trailSkirtOverlays[ref] {
                map.removeOverlays(overlays)
                trailSkirtOverlays[ref] = nil
            }
        }

        for trail in trails where trailLineOverlays[trail.reference] == nil {
            var lines: [TrailLineOverlay] = []
            for line in trail.lines {
                let overlay = polylineOverlay(TrailLineOverlay.self, coordinates: line)
                overlay.trailReference = trail.reference
                lines.append(overlay)
            }
            var skirts: [TrailSkirtOverlay] = []
            for polygon in trail.skirtPolygons {
                let overlay = polygonOverlay(TrailSkirtOverlay.self, coordinates: polygon)
                overlay.trailReference = trail.reference
                skirts.append(overlay)
            }
            map.addOverlays(skirts, level: .aboveRoads)
            map.addOverlays(lines, level: .aboveRoads)
            trailLineOverlays[trail.reference] = lines
            trailSkirtOverlays[trail.reference] = skirts
        }
    }

    // MARK: - Selection refresh

    func refreshSelectionState(on map: MKMapView) {
        let oldSelection = lastSelection
        let newSelection = view.selection
        lastSelection = newSelection
        guard !equal(oldSelection, newSelection) else {
            return
        }

        // Redraw renderers whose colour/line-width depend on selection.
        for renderer in affectedRenderers(on: map, for: oldSelection, and: newSelection) {
            renderer.setNeedsDisplay()
        }

        // Refresh annotation pin SwiftUI hosting.
        for case let view as ParkAnnotationView in map.annotations.compactMap({ map.view(for: $0) }) {
            view.refresh(selection: newSelection)
        }
        for case let view as SummitAnnotationView in map.annotations.compactMap({ map.view(for: $0) }) {
            view.refresh(selection: newSelection)
        }
    }

    private func equal(_ lhs: MapSelection?, _ rhs: MapSelection?) -> Bool {
        switch (lhs, rhs) {
        case (.none, .none): true
        case let (.some(left), .some(right)): left == right
        default: false
        }
    }

    private func affectedRenderers(
        on map: MKMapView,
        for old: MapSelection?,
        and new: MapSelection?
    ) -> [MKOverlayRenderer] {
        let parkRefs = [old?.parkReference, new?.parkReference].compactMap(\.self)
        let trailRefs = [old?.trailReference, new?.trailReference].compactMap(\.self)
        var out: [MKOverlayRenderer] = []
        for ref in parkRefs {
            for overlay in boundaryOverlays[ref] ?? [] {
                if let renderer = map.renderer(for: overlay) {
                    out.append(renderer)
                }
            }
            for overlay in skirtOverlays[ref] ?? [] {
                if let renderer = map.renderer(for: overlay) {
                    out.append(renderer)
                }
            }
        }
        for ref in trailRefs {
            for overlay in trailLineOverlays[ref] ?? [] {
                if let renderer = map.renderer(for: overlay) {
                    out.append(renderer)
                }
            }
            for overlay in trailSkirtOverlays[ref] ?? [] {
                if let renderer = map.renderer(for: overlay) {
                    out.append(renderer)
                }
            }
        }
        return out
    }

    // MARK: - Polygon / polyline builders

    private func polygonOverlay<T: MKPolygon>(
        _: T.Type,
        coordinates: [CLLocationCoordinate2D]
    ) -> T {
        coordinates.withUnsafeBufferPointer { buf in
            T(coordinates: buf.baseAddress!, count: buf.count)
        }
    }

    private func polylineOverlay<T: MKPolyline>(
        _: T.Type,
        coordinates: [CLLocationCoordinate2D]
    ) -> T {
        coordinates.withUnsafeBufferPointer { buf in
            T(coordinates: buf.baseAddress!, count: buf.count)
        }
    }
}
