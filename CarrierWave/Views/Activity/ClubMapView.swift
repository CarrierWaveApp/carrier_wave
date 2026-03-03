@preconcurrency import MapKit
import SwiftData
import SwiftUI

// MARK: - MemberLocation

/// Resolved location for a club member from HamDB lookup
struct MemberLocation: Identifiable {
    let callsign: String
    let coordinate: CLLocationCoordinate2D
    let role: String
    let status: MemberOnlineStatus?

    var id: String {
        callsign
    }
}

// MARK: - MemberLookupInput

/// Input for a member location lookup, avoiding large tuples.
struct MemberLookupInput {
    let callsign: String
    let role: String
    let status: MemberOnlineStatus?
}

// MARK: - ClubMapView

struct ClubMapView: View {
    // MARK: Internal

    let club: Club
    var memberStatuses: [String: MemberStatusDTO]

    // MARK: - State

    @State var memberLocations: [MemberLocation] = []
    @State var isLoading = false
    @State var resolvedCount = 0
    @State var totalCount = 0

    var body: some View {
        Group {
            if isLoading, memberLocations.isEmpty {
                loadingView
            } else if !isLoading, memberLocations.isEmpty {
                ContentUnavailableView(
                    "No Locations",
                    systemImage: "map",
                    description: Text(
                        "Could not resolve member locations"
                    )
                )
            } else {
                ZStack(alignment: .top) {
                    ClusteredMapView(
                        locations: memberLocations
                    )
                    if isLoading {
                        loadingOverlay
                    }
                }
            }
        }
        .task { await lookupLocations() }
    }

    // MARK: Private

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView(
                value: totalCount > 0
                    ? Double(resolvedCount) / Double(totalCount)
                    : 0
            )
            .frame(width: 200)
            Text(
                totalCount > 0
                    ? "Looking up locations (\(resolvedCount)/\(totalCount))…"
                    : "Looking up member locations…"
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var loadingOverlay: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("\(resolvedCount)/\(totalCount) locations")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .padding(.top, 8)
    }
}

// MARK: - ClusteredMapView

private struct ClusteredMapView: UIViewRepresentable {
    // MARK: Internal

    // MARK: - Coordinator

    final class Coordinator: NSObject, MKMapViewDelegate {
        // MARK: Internal

        func mapView(
            _ mapView: MKMapView,
            viewFor annotation: MKAnnotation
        ) -> MKAnnotationView? {
            if let cluster = annotation as? MKClusterAnnotation {
                return configureCluster(
                    cluster, on: mapView
                )
            }
            guard let member = annotation as? MemberAnnotation
            else {
                return nil
            }
            return configureMember(member, on: mapView)
        }

        // MARK: Private

        private func configureMember(
            _ member: MemberAnnotation,
            on mapView: MKMapView
        ) -> MKAnnotationView {
            let view = mapView
                .dequeueReusableAnnotationView(
                    withIdentifier: "member",
                    for: member
                ) as! MKMarkerAnnotationView // swiftlint:disable:this force_cast
            view.annotation = member
            view.markerTintColor = memberColor(
                for: member.status
            )
            view.glyphImage = UIImage(
                systemName: "antenna.radiowaves.left.and.right"
            )
            view.titleVisibility = .adaptive
            view.subtitleVisibility = .hidden
            view.displayPriority = member.status == .onAir
                ? .required : .defaultHigh
            view.clusteringIdentifier = "clubMember"
            return view
        }

        private func configureCluster(
            _ cluster: MKClusterAnnotation,
            on mapView: MKMapView
        ) -> MKAnnotationView {
            let view = mapView
                .dequeueReusableAnnotationView(
                    withIdentifier: "cluster",
                    for: cluster
                ) as! MKMarkerAnnotationView // swiftlint:disable:this force_cast
            view.annotation = cluster
            let members = cluster.memberAnnotations
                .compactMap { $0 as? MemberAnnotation }
            let hasOnAir = members.contains {
                $0.status == .onAir
            }
            view.markerTintColor = hasOnAir
                ? .systemGreen : .systemBlue
            view.glyphText = "\(cluster.memberAnnotations.count)"
            return view
        }

        private func memberColor(
            for status: MemberOnlineStatus?
        ) -> UIColor {
            switch status {
            case .onAir: .systemGreen
            case .recentlyActive: .systemYellow
            case .inactive,
                 .none: .systemBlue
            }
        }
    }

    let locations: [MemberLocation]

    func makeUIView(
        context: Context
    ) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.register(
            MKMarkerAnnotationView.self,
            forAnnotationViewWithReuseIdentifier: "member"
        )
        mapView.register(
            MKMarkerAnnotationView.self,
            forAnnotationViewWithReuseIdentifier: "cluster"
        )
        return mapView
    }

    func updateUIView(
        _ mapView: MKMapView,
        context: Context
    ) {
        mapView.removeAnnotations(mapView.annotations)

        let annotations = locations.map {
            MemberAnnotation(location: $0)
        }
        mapView.addAnnotations(annotations)

        guard !annotations.isEmpty else {
            return
        }
        let region = regionForAnnotations(annotations)
        mapView.setRegion(region, animated: false)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    // MARK: Private

    private func regionForAnnotations(
        _ annotations: [MemberAnnotation]
    ) -> MKCoordinateRegion {
        if annotations.count == 1 {
            return MKCoordinateRegion(
                center: annotations[0].coordinate,
                latitudinalMeters: 200_000,
                longitudinalMeters: 200_000
            )
        }

        var minLat = annotations[0].coordinate.latitude
        var maxLat = minLat
        var minLon = annotations[0].coordinate.longitude
        var maxLon = minLon

        for ann in annotations {
            let coord = ann.coordinate
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
            latitudeDelta: max((maxLat - minLat) * 1.3, 0.5),
            longitudeDelta: max((maxLon - minLon) * 1.3, 0.5)
        )
        return MKCoordinateRegion(center: center, span: span)
    }
}

// MARK: - Array+Chunked

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}

// MARK: - Preview

#Preview {
    ClubMapView(
        club: Club(
            serverId: UUID(),
            name: "Preview Club"
        ),
        memberStatuses: [:]
    )
    .modelContainer(
        for: [Club.self, ClubMember.self],
        inMemory: true
    )
}
