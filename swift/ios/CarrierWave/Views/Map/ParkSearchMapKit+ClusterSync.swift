// Cluster-manager driven annotation sync for the parks/summits map.
//
// Replaces the previous per-annotation `map.addAnnotation` / `removeAnnotation`
// diff with a `ClusterManager`-driven flow: all 22k pins are fed into the
// actor-backed quadtree once at startup, and every region change yields a
// small `Difference` (just the visible cluster bubbles + de-clustered
// leaves) that we apply to `MKMapView`. The map never sees more than a
// few hundred annotations at any time.

import CarrierWaveData
import ClusterMap
import CoreLocation
import MapKit

// MARK: - ClusterDataSignature

/// Cheap fingerprint of the SwiftUI-supplied park/summit arrays so we only
/// rebuild the cluster manager when the input set actually changes (not on
/// every `updateUIView` triggered by an unrelated state change).
struct ClusterDataSignature: Equatable {
    let parkCount: Int
    let summitCount: Int
    let firstParkRef: String?
    let firstSummitCode: String?
    let showParkPins: Bool
    let showSummitPins: Bool
}

// MARK: - Coordinator integration

extension ParkSearchMapKit.Coordinator {
    /// Rebuild the cluster manager when the SwiftUI-supplied park/summit
    /// arrays change. The actual quadtree work runs on the
    /// `ClusterManager` actor so the main thread isn't blocked.
    func syncClusterData(
        on map: MKMapView,
        parks: [POTAPark],
        summits: [SOTASummit],
        showParkPins: Bool,
        showSummitPins: Bool
    ) {
        let parksToFeed = showParkPins ? parks : []
        let summitsToFeed = showSummitPins ? summits : []
        let signature = ClusterDataSignature(
            parkCount: parksToFeed.count,
            summitCount: summitsToFeed.count,
            firstParkRef: parksToFeed.first?.reference,
            firstSummitCode: summitsToFeed.first?.code,
            showParkPins: showParkPins,
            showSummitPins: showSummitPins
        )
        guard signature != lastClusterDataSignature else {
            return
        }
        lastClusterDataSignature = signature

        let items = buildPinItems(parks: parksToFeed, summits: summitsToFeed)
        let manager = clusterManager

        clusterRebuildTask?.cancel()
        clusterRebuildTask = Task { @MainActor [weak self] in
            await manager.removeAll()
            await manager.add(items)
            guard !Task.isCancelled else {
                return
            }
            await self?.reloadClusterDisplay(on: map)
        }
    }

    /// Debounced reload trigger for region changes. Coalesces the rapid
    /// `regionDidChange` callbacks during pan inertia into a single
    /// quadtree query.
    func triggerClusterReload(on map: MKMapView) {
        clusterReloadTask?.cancel()
        clusterReloadTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(80))
            guard !Task.isCancelled else {
                return
            }
            await self?.reloadClusterDisplay(on: map)
        }
    }

    /// Query the cluster manager for the current region and apply the diff.
    func reloadClusterDisplay(on map: MKMapView) async {
        let diff = await clusterManager.reload(
            mapViewSize: map.bounds.size,
            coordinateRegion: map.region
        )
        guard !Task.isCancelled else {
            return
        }
        applyClusterDiff(diff, on: map)
    }

    /// Zoom-fit the bounding rect of a cluster's members so a tap on the
    /// bubble drills down without manual pinching.
    func zoomToCluster(_ cluster: MapClusterAnnotation, on map: MKMapView) {
        let coords = cluster.memberCoordinates
        guard !coords.isEmpty else {
            return
        }
        var minLat = coords[0].latitude
        var maxLat = minLat
        var minLon = coords[0].longitude
        var maxLon = minLon
        for coord in coords.dropFirst() {
            minLat = min(minLat, coord.latitude)
            maxLat = max(maxLat, coord.latitude)
            minLon = min(minLon, coord.longitude)
            maxLon = max(maxLon, coord.longitude)
        }
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max(0.02, (maxLat - minLat) * 1.4),
            longitudeDelta: max(0.02, (maxLon - minLon) * 1.4)
        )
        map.setRegion(MKCoordinateRegion(center: center, span: span), animated: true)
    }

    // MARK: - Private helpers

    private func buildPinItems(parks: [POTAPark], summits: [SOTASummit]) -> [MapPinItem] {
        var items: [MapPinItem] = []
        items.reserveCapacity(parks.count + summits.count)
        for park in parks where park.latitude != nil && park.longitude != nil {
            items.append(MapPinItem(park: park))
        }
        for summit in summits where summit.latitude != nil && summit.longitude != nil {
            items.append(MapPinItem(summit: summit))
        }
        return items
    }

    private func applyClusterDiff(
        _ diff: ClusterManager<MapPinItem>.Difference, on map: MKMapView
    ) {
        var toRemove: [MKAnnotation] = []
        for removal in diff.removals {
            switch removal {
            case let .annotation(item):
                if let anno = clusterLeafByID.removeValue(forKey: item.id) {
                    toRemove.append(anno)
                }
            case let .cluster(cluster):
                if let anno = clusterBubbleByID.removeValue(forKey: cluster.id) {
                    toRemove.append(anno)
                }
            }
        }
        if !toRemove.isEmpty {
            map.removeAnnotations(toRemove)
        }

        var toAdd: [MKAnnotation] = []
        for insertion in diff.insertions {
            switch insertion {
            case let .annotation(item):
                guard let anno = makeLeafAnnotation(item) else {
                    continue
                }
                clusterLeafByID[item.id] = anno
                toAdd.append(anno)
            case let .cluster(cluster):
                let anno = MapClusterAnnotation(cluster: cluster)
                clusterBubbleByID[cluster.id] = anno
                toAdd.append(anno)
            }
        }
        if !toAdd.isEmpty {
            map.addAnnotations(toAdd)
        }
    }

    /// Materialize a leaf `MapPinItem` into the existing
    /// `ParkMapAnnotation` / `SummitMapAnnotation` wrapper that the
    /// `ParkAnnotationView` / `SummitAnnotationView` dequeue path expects.
    /// The full `POTAPark` / `SOTASummit` is looked up from its cache on
    /// demand — keeps the quadtree payload small.
    private func makeLeafAnnotation(_ item: MapPinItem) -> MKAnnotation? {
        switch item.kind {
        case .park:
            guard let park = POTAParksCache.shared.parkSync(for: item.reference) else {
                return nil
            }
            let hasBoundary = view.boundaryRefs.contains(park.reference)
            return ParkMapAnnotation(
                park: park,
                latitude: item.coordinate.latitude,
                longitude: item.coordinate.longitude,
                hasBoundary: hasBoundary
            )
        case .summit:
            guard let summit = SOTASummitsCache.shared.summitSync(for: item.reference) else {
                return nil
            }
            return SummitMapAnnotation(
                summit: summit,
                latitude: item.coordinate.latitude,
                longitude: item.coordinate.longitude
            )
        }
    }
}
