// ClusterMap-based clustering for the parks/summits map.
//
// MapKit's built-in `clusteringIdentifier`-based clustering is main-thread-
// bound and does not scale beyond a few thousand annotations — at 22k
// (POTA + SOTA) it freezes the UI on every region change. Instead we use
// vospennikov/ClusterMap (an actor-backed quadtree) to do clustering off
// the main thread, and only ever feed MKMapView the visible cluster
// bubbles and de-clustered leaves for the current zoom/region.

import CarrierWaveData
import ClusterMap
import CoreLocation
import MapKit
import SwiftUI

// MARK: - MapPinItem

/// Value type fed into `ClusterManager`. Carries enough to identify a park
/// or summit and reconstruct an `MKAnnotation` when the cluster manager
/// reports it as a visible leaf. Full `POTAPark` / `SOTASummit` records are
/// looked up from their caches at materialization time — that keeps the
/// quadtree small (≈40 bytes per item) and side-steps the Sendability
/// question on those types.
nonisolated struct MapPinItem: CoordinateIdentifiable, Identifiable, Hashable {
    // MARK: Lifecycle

    init(park: POTAPark) {
        reference = park.reference
        id = "p:\(park.reference)"
        coordinate = CLLocationCoordinate2D(
            latitude: park.latitude ?? 0, longitude: park.longitude ?? 0
        )
        kind = .park
    }

    init(summit: SOTASummit) {
        reference = summit.code
        id = "s:\(summit.code)"
        coordinate = CLLocationCoordinate2D(
            latitude: summit.latitude ?? 0, longitude: summit.longitude ?? 0
        )
        kind = .summit
    }

    // MARK: Internal

    nonisolated enum Kind: Hashable {
        case park
        case summit
    }

    let id: String
    var coordinate: CLLocationCoordinate2D
    let kind: Kind
    /// POTA reference (e.g. `US-1234`) or SOTA code (e.g. `W4C/CM-001`).
    let reference: String

    static func == (lhs: MapPinItem, rhs: MapPinItem) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - MapClusterAnnotation

/// `MKAnnotation` wrapper around a `ClusterManager.ClusterAnnotation` so
/// MapKit can render a count bubble at the cluster's centroid.
final class MapClusterAnnotation: NSObject, MKAnnotation {
    // MARK: Lifecycle

    init(cluster: ClusterManager<MapPinItem>.ClusterAnnotation) {
        clusterID = cluster.id
        coordinate = cluster.coordinate
        let members = cluster.memberAnnotations
        memberCount = members.count
        var parks = 0
        var summits = 0
        for member in members {
            switch member.kind {
            case .park: parks += 1
            case .summit: summits += 1
            }
        }
        parkCount = parks
        summitCount = summits
        memberCoordinates = members.map(\.coordinate)
    }

    // MARK: Internal

    /// Stable identifier for the cluster within one `visibleAnnotations`
    /// generation in `ClusterManager`. Used by the diff applier to find the
    /// `MKAnnotation` previously added for a cluster that's now being
    /// removed (ClusterMap generates a fresh UUID per cluster per reload).
    let clusterID: UUID
    let coordinate: CLLocationCoordinate2D
    let memberCount: Int
    let parkCount: Int
    let summitCount: Int
    /// Snapshot of member coordinates so a tap can zoom-to-fit without
    /// going back to the cluster manager.
    let memberCoordinates: [CLLocationCoordinate2D]
}

// MARK: - MapClusterAnnotationView

final class MapClusterAnnotationView: MKAnnotationView {
    // MARK: Lifecycle

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        canShowCallout = false
        backgroundColor = .clear
        collisionMode = .circle
        displayPriority = .required
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    // MARK: Internal

    static let reuseID = "ClusterMapPinCluster"

    static func register(on map: MKMapView) {
        map.register(MapClusterAnnotationView.self, forAnnotationViewWithReuseIdentifier: reuseID)
    }

    static func dequeue(on map: MKMapView, for annotation: MapClusterAnnotation) -> MapClusterAnnotationView {
        let view = map.dequeueReusableAnnotationView(
            withIdentifier: reuseID, for: annotation
        ) as? MapClusterAnnotationView
            ?? MapClusterAnnotationView(annotation: annotation, reuseIdentifier: reuseID)
        view.annotation = annotation
        view.refresh()
        return view
    }

    func refresh() {
        guard let cluster = (annotation as? MapClusterAnnotation) else {
            return
        }
        let root = MapClusterBubbleView(
            count: cluster.memberCount,
            parkCount: cluster.parkCount,
            summitCount: cluster.summitCount
        )
        if let host = hostingController {
            host.rootView = root
        } else {
            let host = UIHostingController(rootView: root)
            host.view.backgroundColor = .clear
            host.view.translatesAutoresizingMaskIntoConstraints = false
            host.safeAreaRegions = []
            addSubview(host.view)
            NSLayoutConstraint.activate([
                host.view.centerXAnchor.constraint(equalTo: centerXAnchor),
                host.view.centerYAnchor.constraint(equalTo: centerYAnchor),
            ])
            hostingController = host
        }
        sizeToFitHosted()
    }

    // MARK: Private

    private var hostingController: UIHostingController<MapClusterBubbleView>?

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
        centerOffset = .zero
    }
}

// MARK: - MapClusterBubbleView

struct MapClusterBubbleView: View {
    // MARK: Internal

    let count: Int
    let parkCount: Int
    let summitCount: Int

    var body: some View {
        ZStack {
            Circle()
                .fill(fill)
                .overlay(Circle().stroke(.white, lineWidth: 2))
                .shadow(color: .black.opacity(0.25), radius: 2, x: 0, y: 1)
            Text(formatted)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()
        }
        .frame(width: diameter, height: diameter)
    }

    // MARK: Private

    private var diameter: CGFloat {
        switch count {
        case ..<10: 28
        case ..<100: 34
        case ..<1_000: 42
        default: 50
        }
    }

    private var fill: Color {
        if summitCount == 0 {
            return .green
        }
        if parkCount == 0 {
            return .brown
        }
        return .teal
    }

    private var formatted: String {
        if count >= 1_000 {
            return String(format: "%.1fk", Double(count) / 1_000)
        }
        return "\(count)"
    }
}
