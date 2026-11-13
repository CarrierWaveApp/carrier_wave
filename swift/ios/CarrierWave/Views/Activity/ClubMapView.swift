import CarrierWaveCore
import CarrierWaveData
@preconcurrency import MapKit
import SwiftUI

// MARK: - MemberLocation

/// Resolved location for a club member — a grid centroid until `QrzApi.locate`
/// refines it to a precise coordinate.
struct MemberLocation: Identifiable {
    let callsign: String
    let coordinate: CLLocationCoordinate2D
    let role: String
    let status: FfiMemberOnlineStatus?

    var id: String {
        callsign
    }
}

// MARK: - ClubMapView

struct ClubMapView: View {
    // MARK: Internal

    let club: FfiClub
    var memberStatuses: [String: FfiMemberStatus]

    // MARK: - State

    @AppStorage("shareMapStyle") var shareMapStyleRaw = "adaptive"
    @State var memberLocations: [MemberLocation] = []
    @State var isLoading = false

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
                    if mapStyle.usesCustomRenderer {
                        ThemedMapImage(
                            coordinates: memberLocations.map(\.coordinate),
                            myCoordinate: nil,
                            style: mapStyle
                        )
                    } else {
                        ClusteredMapView(
                            locations: memberLocations,
                            useGlobe: useGlobeStyle
                        )
                    }
                    if isLoading {
                        loadingOverlay
                    }
                }
            }
        }
        .task { await loadMemberLocations() }
    }

    // MARK: Private

    private var mapStyle: ShareMapStyle {
        ShareMapStyle(rawValue: shareMapStyleRaw) ?? .adaptive
    }

    private var useGlobeStyle: Bool {
        mapStyle.shouldUseGlobe(isWideSpan: mapBounds?.requiresGlobeView ?? false)
    }

    private var mapBounds: FfiMapBounds? {
        mapBoundsFor(coords: memberLocations.map {
            FfiCoordinate(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude)
        })
    }

    private var loadingView: some View {
        ProgressView("Loading member locations…")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var loadingOverlay: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("Refining locations…")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .padding(.top, 8)
    }
}

// MARK: - Data Loading

extension ClubMapView {
    /// Grid-first render: build annotations synchronously from each member's
    /// `lastGrid` centroid so the map paints instantly, then refine via a single
    /// `QrzApi.locate` call across all members (cache makes repeat opens cheap).
    /// A returned `FfiCallsignLocation` replaces that member's centroid with a
    /// precise coordinate; members with no grid gain a pin. Best-effort — a
    /// `locate` failure leaves the grid pins rendered.
    func loadMemberLocations() async {
        let rawMembers = await ClubsSyncService.shared.members(inClubId: club.id)

        memberLocations = rawMembers.compactMap { member in
            gridLocation(for: member)
        }.sorted { $0.callsign < $1.callsign }

        guard !rawMembers.isEmpty else {
            return
        }

        isLoading = true
        defer { isLoading = false }

        let refined = await refinedLocations(for: rawMembers)
        guard !refined.isEmpty else {
            return
        }

        memberLocations = rawMembers.compactMap { member in
            if let location = refined[member.callsign.uppercased()] {
                return MemberLocation(
                    callsign: member.callsign,
                    coordinate: location,
                    role: member.role,
                    status: memberStatuses[member.callsign.uppercased()]?.status
                )
            }
            return gridLocation(for: member)
        }.sorted { $0.callsign < $1.callsign }
    }

    private func gridLocation(for member: FfiClubMember) -> MemberLocation? {
        guard let grid = member.lastGrid,
              let coord = maidenheadCoordinate(grid: grid)
        else {
            return nil
        }
        return MemberLocation(
            callsign: member.callsign,
            coordinate: CLLocationCoordinate2D(latitude: coord.latitude, longitude: coord.longitude),
            role: member.role,
            status: memberStatuses[member.callsign.uppercased()]?.status
        )
    }

    /// Resolves precise coordinates for all member callsigns via `QrzApi.locate`.
    /// Keyed by uppercase callsign to match the returned `FfiCallsignLocation`s.
    private func refinedLocations(
        for members: [FfiClubMember]
    ) async -> [String: CLLocationCoordinate2D] {
        do {
            let store = try await CwStoreProvider.shared.store()
            let qrzApi = try QrzApi.withStore(secure: KeychainSecureStore(), store: store)
            let callsigns = members.map(\.callsign)
            let results = try await Task.detached { try await qrzApi.locate(callsigns: callsigns) }.value
            return results.reduce(into: [:]) { partial, location in
                partial[location.callsign.uppercased()] = CLLocationCoordinate2D(
                    latitude: location.latitude, longitude: location.longitude
                )
            }
        } catch {
            RadioService.shared.addLog(.error, "Club map location refinement failed: \(error)")
            return [:]
        }
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
            for status: FfiMemberOnlineStatus?
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
    var useGlobe: Bool = false

    func makeUIView(
        context: Context
    ) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.preferredConfiguration = mapConfiguration
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
        mapView.preferredConfiguration = mapConfiguration
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

    private var mapConfiguration: MKMapConfiguration {
        if useGlobe {
            return MKImageryMapConfiguration(
                elevationStyle: .realistic
            )
        }
        return MKStandardMapConfiguration(
            elevationStyle: .realistic
        )
    }

    private func regionForAnnotations(
        _ annotations: [MemberAnnotation]
    ) -> MKCoordinateRegion {
        let coords = annotations.map {
            FfiCoordinate(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude)
        }
        guard let bounds = mapBoundsFor(coords: coords) else {
            return MKCoordinateRegion(
                center: annotations[0].coordinate,
                latitudinalMeters: 200_000,
                longitudinalMeters: 200_000
            )
        }
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: bounds.centerLat, longitude: bounds.centerLon),
            span: MKCoordinateSpan(latitudeDelta: bounds.cameraLatSpan, longitudeDelta: bounds.cameraLonSpan)
        )
    }
}

// MARK: - Preview

#Preview {
    ClubMapView(
        club: FfiClub(
            id: "preview",
            name: "Preview Club",
            callsign: nil,
            description: nil,
            notesUrl: nil,
            notesTitle: nil,
            hasLogo: false,
            cachedMemberCount: 0,
            lastSyncedAt: 0
        ),
        memberStatuses: [:]
    )
}
