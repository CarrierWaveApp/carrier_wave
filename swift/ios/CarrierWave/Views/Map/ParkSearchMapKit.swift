// MapKit-backed parks/summits/radar map for the Map tab.
//
// SwiftUI's `Map` builder has no `MKTileOverlay` equivalent, so the radar
// previously lived in a layered MKMapView synced via `onMapCameraChange`.
// That always lagged one render-cycle behind. Putting boundaries, trails,
// pins, AND the NEXRAD tiles inside a single `MKMapView` makes them part of
// the same render pass — no sync, no drift.
//
// State stays in `ParkSearchMapView`; this file is the UIKit shell that the
// SwiftUI parent drives through bindings + a small set of callbacks.

import CarrierWaveData
import ClusterMap
import CoreLocation
import MapKit
import SwiftUI

// MARK: - ParkSearchMapKit

struct ParkSearchMapKit: UIViewRepresentable {
    // MARK: Bindings

    @Binding var region: MKCoordinateRegion

    // MARK: Data

    let selection: MapSelection?
    let boundaries: [ParkBoundary]
    let adminBoundaries: [AdminBoundary]
    let sotaZones: [SOTAZone]
    let wwffItems: [WWFFRenderItem]
    let trails: [TrailBoundary]
    let parks: [POTAPark]
    let summits: [SOTASummit]
    let boundaryRefs: Set<String>

    // MARK: Display flags

    let showBoundaries: Bool
    let showTrails: Bool
    let showParkPins: Bool
    let showSummitPins: Bool
    let showRadar: Bool
    let showGrids: Bool
    let showTiles: Bool
    let isZoomedIn: Bool

    /// Bump to ask the map to re-center on the user's location. Compared
    /// against the coordinator's last-applied token so repeat presses work.
    let recenterToken: Int

    /// Coarse fallback (saved home grid / last known fix) used only when
    /// location permission is denied and user tracking can't engage.
    let homeFallback: CLLocationCoordinate2D?

    // MARK: Callbacks

    let onRegionChange: (MKCoordinateRegion) -> Void
    let onTapCoordinate: (CLLocationCoordinate2D) -> Void

    // MARK: UIViewRepresentable

    func makeCoordinator() -> Coordinator {
        Coordinator(view: self)
    }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.showsUserLocation = true
        map.pointOfInterestFilter = .excludingAll
        map.showsCompass = false
        map.showsScale = false

        ParkAnnotationView.register(on: map)
        SummitAnnotationView.register(on: map)
        MapClusterAnnotationView.register(on: map)

        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:))
        )
        tap.delegate = context.coordinator
        map.addGestureRecognizer(tap)

        map.setRegion(region, animated: false)
        context.coordinator.lastAppliedRegion = map.region
        context.coordinator.lastRecenterToken = recenterToken
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        let coordinator = context.coordinator
        coordinator.view = self

        // Region sync (parent → map). Skip if the requested region matches
        // what we last applied — otherwise we'd fight the user's gesture.
        if !region.approximatelyEqual(to: coordinator.lastAppliedRegion) {
            coordinator.suppressNextRegionCallback = true
            map.setRegion(region, animated: true)
            coordinator.lastAppliedRegion = map.region
        }

        if recenterToken != coordinator.lastRecenterToken {
            coordinator.lastRecenterToken = recenterToken
            coordinator.recenterOnUser(map)
        }

        coordinator.syncRadar(on: map, enabled: showRadar)
        coordinator.syncGrids(on: map, enabled: showGrids)
        coordinator.syncTiles(on: map, enabled: showTiles)
        coordinator.syncAdmin(on: map, boundaries: adminBoundaries)
        coordinator.syncSotaZones(on: map, zones: sotaZones)
        coordinator.syncWWFF(on: map, items: wwffItems)
        coordinator.syncBoundaries(
            on: map,
            boundaries: showBoundaries ? boundaries : [],
            isZoomedIn: isZoomedIn
        )
        coordinator.syncTrails(on: map, trails: showTrails ? trails : [])
        // Feed pin data to the cluster manager. Only triggers a rebuild
        // when the input set actually changes — `updateUIView` fires on
        // every region change, but the data signature catches that.
        coordinator.syncClusterData(
            on: map,
            parks: parks,
            summits: summits,
            showParkPins: showParkPins,
            showSummitPins: showSummitPins
        )
        coordinator.refreshSelectionState(on: map)
    }
}

// MARK: ParkSearchMapKit.Coordinator

extension ParkSearchMapKit {
    final class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        // MARK: Lifecycle

        init(view: ParkSearchMapKit) {
            self.view = view
        }

        // MARK: Internal

        var view: ParkSearchMapKit
        var lastAppliedRegion = MKCoordinateRegion()
        var lastRecenterToken = 0
        var suppressNextRegionCallback = false

        /// Held to read the current authorization status when the user taps the
        /// recenter arrow. `showsUserLocation = true` drives the actual prompt.
        let locationManager = CLLocationManager()

        // Existing overlays/annotations indexed by stable reference so we
        // can diff incrementally rather than redraw every camera change
        // (which would flicker and tank performance with many parks).
        var radarOverlay: MKTileOverlay?
        var boundaryOverlays: [String: [BoundaryFillOverlay]] = [:]
        var skirtOverlays: [String: [BoundarySkirtOverlay]] = [:]
        var trailLineOverlays: [String: [TrailLineOverlay]] = [:]
        var trailSkirtOverlays: [String: [TrailSkirtOverlay]] = [:]
        // Grid-square / TOTA-tile boundary overlays. Diffed by signature so we
        // only rebuild when the set of visible cells actually changes.
        var gridLineOverlays: [GridLineOverlay] = []
        var tileLineOverlays: [TileLineOverlay] = []
        var lastGridSignature = ""
        var lastTileSignature = ""
        /// Admin (state/county) outline overlays, keyed by boundary id.
        var adminOverlays: [String: [MKPolyline]] = [:]
        /// SOTA activation-zone fill overlays, keyed by summit code.
        var sotaZoneOverlays: [String: [SotaZoneFillOverlay]] = [:]
        // WWFF fill/marker overlays, keyed by WWFF code.
        var wwffOverlays: [String: [MKPolygon]] = [:]
        var lastZoomedIn = false
        var lastSelection: MapSelection?

        // Cluster manager state. The map only ever sees what's in these
        // dicts — never the full 22k pin set.
        let clusterManager = ClusterManager<MapPinItem>()
        var clusterLeafByID: [String: MKAnnotation] = [:]
        var clusterBubbleByID: [UUID: MapClusterAnnotation] = [:]
        var lastClusterDataSignature: ClusterDataSignature?
        var clusterRebuildTask: Task<Void, Never>?
        var clusterReloadTask: Task<Void, Never>?

        // MARK: - MKMapViewDelegate

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated _: Bool) {
            let newRegion = mapView.region
            lastAppliedRegion = newRegion
            // Always sync the parent's `@State` binding so user pans don't
            // get clobbered the next time `updateUIView` runs. Without this,
            // any unrelated state change (boundary fetch, summit refresh)
            // makes the next `updateUIView` think the user-driven region
            // disagrees with the parent state and snaps the map back to the
            // last programmatically-set region.
            view.region = newRegion
            // Recompute clusters for the new region (debounced inside).
            triggerClusterReload(on: mapView)
            if suppressNextRegionCallback {
                suppressNextRegionCallback = false
                return
            }
            view.onRegionChange(newRegion)
        }

        // MARK: - Tap handling

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let map = gesture.view as? MKMapView else {
                return
            }
            let point = gesture.location(in: map)
            let hit = map.hitTest(point, with: nil)
            if hit is MKAnnotationView || hit?.superview is MKAnnotationView {
                return
            }
            let coordinate = map.convert(point, toCoordinateFrom: map)
            view.onTapCoordinate(coordinate)
        }

        func gestureRecognizer(
            _: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith _: UIGestureRecognizer
        ) -> Bool {
            true
        }

        // MARK: - Recenter on user

        /// Center the map on the user. Prefers `.follow` user tracking, which
        /// snaps to the live GPS fix now (or as soon as it arrives). Only when
        /// location access is explicitly denied/restricted do we fall back to
        /// the coarse home grid so the button still does something useful.
        func recenterOnUser(_ map: MKMapView) {
            let status = locationManager.authorizationStatus
            let denied = status == .denied || status == .restricted
            if !denied {
                map.setUserTrackingMode(.follow, animated: true)
                return
            }
            guard let home = view.homeFallback else {
                return
            }
            suppressNextRegionCallback = true
            let region = MKCoordinateRegion(
                center: home,
                span: MKCoordinateSpan(latitudeDelta: 1, longitudeDelta: 1)
            )
            map.setRegion(region, animated: true)
            lastAppliedRegion = map.region
        }

        // MARK: - Overlay rendering

        func mapView(_: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            switch overlay {
            case let tile as MKTileOverlay:
                let renderer = MKTileOverlayRenderer(tileOverlay: tile)
                renderer.alpha = 0.7
                return renderer
            case let fill as BoundaryFillOverlay:
                let renderer = MKPolygonRenderer(polygon: fill)
                let selected = view.selection?.parkReference == fill.parkReference
                renderer.fillColor = selected
                    ? UIColor.systemGreen.withAlphaComponent(0.3)
                    : UIColor.systemGreen.withAlphaComponent(0.15)
                renderer.strokeColor = .systemGreen
                renderer.lineWidth = selected ? 3 : 2
                return renderer
            case let skirt as BoundarySkirtOverlay:
                let renderer = MKPolygonRenderer(polygon: skirt)
                let selected = view.selection?.parkReference == skirt.parkReference
                renderer.fillColor = selected
                    ? UIColor.systemOrange.withAlphaComponent(0.25)
                    : UIColor.systemOrange.withAlphaComponent(0.1)
                renderer.strokeColor = UIColor.systemOrange.withAlphaComponent(0.3)
                renderer.lineWidth = 1
                return renderer
            case let grid as GridLineOverlay:
                return lineRenderer(grid, color: .systemCyan)
            case let tile as TileLineOverlay:
                return lineRenderer(tile, color: .systemPurple)
            case let state as StateLineOverlay:
                return lineRenderer(state, color: .systemIndigo, width: 2, alpha: 0.7)
            case let county as CountyLineOverlay:
                return lineRenderer(county, color: .systemGray, width: 1, alpha: 0.6)
            case let zone as SotaZoneFillOverlay:
                return zoneFillRenderer(zone)
            default:
                return trailRenderer(for: overlay)
                    ?? wwffRenderer(for: overlay)
                    ?? MKOverlayRenderer(overlay: overlay)
            }
        }

        // MARK: - Annotation views

        func mapView(_ map: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation {
                return nil
            }
            if let cluster = annotation as? MapClusterAnnotation {
                return MapClusterAnnotationView.dequeue(on: map, for: cluster)
            }
            if let park = annotation as? ParkMapAnnotation {
                return ParkAnnotationView.dequeue(on: map, for: park, selection: view.selection)
            }
            if let summit = annotation as? SummitMapAnnotation {
                return SummitAnnotationView.dequeue(on: map, for: summit, selection: view.selection)
            }
            return nil
        }

        func mapView(_ map: MKMapView, didSelect annotationView: MKAnnotationView) {
            guard let annotation = annotationView.annotation else {
                return
            }
            if let cluster = annotation as? MapClusterAnnotation {
                map.deselectAnnotation(cluster, animated: false)
                zoomToCluster(cluster, on: map)
                return
            }
            if let park = annotation as? ParkMapAnnotation {
                view.onTapCoordinate(park.coordinate)
            } else if let summit = annotation as? SummitMapAnnotation {
                view.onTapCoordinate(summit.coordinate)
            }
        }

        // MARK: Private

        /// Renderers for the historic-trail overlays (line + skirt), split out
        /// to keep `rendererFor` under the function-length limit.
        private func trailRenderer(for overlay: MKOverlay) -> MKOverlayRenderer? {
            switch overlay {
            case let line as TrailLineOverlay:
                let renderer = MKPolylineRenderer(polyline: line)
                let selected = view.selection?.trailReference == line.trailReference
                renderer.strokeColor = .systemBrown
                renderer.lineWidth = selected ? 4 : 3
                return renderer
            case let skirt as TrailSkirtOverlay:
                let renderer = MKPolygonRenderer(polygon: skirt)
                let selected = view.selection?.trailReference == skirt.trailReference
                renderer.fillColor = selected
                    ? UIColor.systemBrown.withAlphaComponent(0.25)
                    : UIColor.systemBrown.withAlphaComponent(0.1)
                renderer.strokeColor = UIColor.systemBrown.withAlphaComponent(0.3)
                renderer.lineWidth = 1
                return renderer
            default:
                return nil
            }
        }
    }
}

// MARK: - MKCoordinateRegion helpers

extension MKCoordinateRegion {
    /// Default starting region — geographic centre of CONUS, wide enough to
    /// frame the lower 48. Used when no home grid is known.
    static let continentalUS = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 39.5, longitude: -98.35),
        span: MKCoordinateSpan(latitudeDelta: 35, longitudeDelta: 50)
    )

    func approximatelyEqual(to other: MKCoordinateRegion) -> Bool {
        let tol = 1e-6
        return abs(center.latitude - other.center.latitude) < tol
            && abs(center.longitude - other.center.longitude) < tol
            && abs(span.latitudeDelta - other.span.latitudeDelta) < tol
            && abs(span.longitudeDelta - other.span.longitudeDelta) < tol
    }
}
