// Weather Radar View
//
// Full-screen sheet showing the NEXRAD radar overlay on a map centered
// on the user's grid or current location, plus active NWS alerts.

import CarrierWaveCore
import CarrierWaveData
import CoreLocation
import MapKit
import SwiftUI

// MARK: - WeatherRadarView

struct WeatherRadarView: View {
    // MARK: Lifecycle

    init(grid: String? = nil) {
        self.grid = grid
    }

    // MARK: Internal

    var body: some View {
        ZStack(alignment: .topLeading) {
            RadarMap(centerCoordinate: centerCoordinate, radarOpacity: opacity)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    WeatherAlertsBanner(alerts: alerts)

                    if isLoadingAlerts, alerts.isEmpty {
                        loadingPill
                    } else if let alertsError {
                        errorPill(alertsError)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)

                Spacer()

                HStack {
                    Spacer()
                    attributionFooter
                    Spacer()
                }
            }
        }
        .navigationTitle("Weather Radar")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Picker("Opacity", selection: $opacity) {
                        Text("100%").tag(1.0)
                        Text("75%").tag(0.75)
                        Text("50%").tag(0.5)
                        Text("25%").tag(0.25)
                    }
                    Button {
                        Task { await reloadAlerts() }
                    } label: {
                        Label("Refresh Alerts", systemImage: "arrow.clockwise")
                    }
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
            }
        }
        .task {
            await resolveCenterIfNeeded()
            await reloadAlerts()
        }
    }

    // MARK: Private

    /// Center of the contiguous US, used when no grid or location is available.
    private static let fallbackUSCenter = CLLocationCoordinate2D(
        latitude: 39.5, longitude: -98.35
    )

    @State private var centerCoordinate: CLLocationCoordinate2D?
    @State private var alerts: [NWSAlert] = []
    @State private var isLoadingAlerts = false
    @State private var alertsError: String?
    @State private var opacity: Double = 0.75
    @State private var locationManager = RadarLocationManager()

    private let grid: String?

    private let radarService = WeatherRadarService()

    private var loadingPill: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Checking for active alerts…")
                .font(.caption)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.thinMaterial, in: Capsule())
        .padding(.top, 8)
    }

    private var attributionFooter: some View {
        Text(WeatherRadarService.radarAttribution)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.thinMaterial, in: Capsule())
            .padding(.bottom, 8)
    }

    private func errorPill(_ message: String) -> some View {
        Text(message)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.thinMaterial, in: Capsule())
            .padding(.top, 8)
    }

    /// Convert a Maidenhead grid square to a coordinate (center of the square).
    /// Mirrors the math in `NOAAClient.gridToCoordinates` — duplicated here so the
    /// service stays free of CoreLocation imports.
    private static func coordinate(forGrid grid: String) -> CLLocationCoordinate2D? {
        let upper = grid.uppercased()
        guard upper.count >= 4 else {
            return nil
        }
        let chars = Array(upper)
        guard
            let lon1 = chars[0].asciiValue, let lat1 = chars[1].asciiValue,
            lon1 >= 65, lon1 <= 82, lat1 >= 65, lat1 <= 82,
            let lon2 = chars[2].wholeNumberValue, let lat2 = chars[3].wholeNumberValue
        else {
            return nil
        }
        var longitude = Double(lon1 - 65) * 20 - 180 + Double(lon2) * 2 + 1
        var latitude = Double(lat1 - 65) * 10 - 90 + Double(lat2) + 0.5
        if upper.count >= 6,
           let lon3 = chars[4].asciiValue, let lat3 = chars[5].asciiValue,
           lon3 >= 65, lon3 <= 88, lat3 >= 65, lat3 <= 88
        {
            longitude += Double(lon3 - 65) * (2.0 / 24.0) + (1.0 / 24.0)
            latitude += Double(lat3 - 65) * (1.0 / 24.0) + (0.5 / 24.0)
        }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    private func resolveCenterIfNeeded() async {
        if centerCoordinate != nil {
            return
        }

        if let grid, let coord = Self.coordinate(forGrid: grid) {
            centerCoordinate = coord
            return
        }

        locationManager.requestLocation()
        for _ in 0 ..< 20 {
            if let location = locationManager.location {
                centerCoordinate = location.coordinate
                return
            }
            if locationManager.authorizationStatus == .denied {
                centerCoordinate = Self.fallbackUSCenter
                return
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        centerCoordinate = Self.fallbackUSCenter
    }

    private func reloadAlerts() async {
        // Wait for a center if it hasn't resolved yet.
        if centerCoordinate == nil {
            await resolveCenterIfNeeded()
        }
        guard let coord = centerCoordinate else {
            return
        }

        isLoadingAlerts = true
        alertsError = nil
        defer { isLoadingAlerts = false }

        do {
            alerts = try await radarService.fetchAlerts(
                latitude: coord.latitude,
                longitude: coord.longitude
            )
        } catch {
            alertsError = "Couldn't load NWS alerts: \(error.localizedDescription)"
        }
    }
}

// MARK: - RadarMap

/// MKMapView wrapper that overlays the NEXRAD tile layer. SwiftUI Map doesn't
/// expose `MKTileOverlay` content directly, so we wrap UIKit.
private struct RadarMap: UIViewRepresentable {
    final class Coordinator: NSObject, MKMapViewDelegate {
        // MARK: Lifecycle

        init(opacity: Double) {
            self.opacity = opacity
        }

        // MARK: Internal

        var opacity: Double
        var hasSetInitialRegion = false
        weak var radarOverlay: MKTileOverlay?
        weak var tileRenderer: MKTileOverlayRenderer?

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let tile = overlay as? MKTileOverlay else {
                return MKOverlayRenderer(overlay: overlay)
            }
            let renderer = MKTileOverlayRenderer(tileOverlay: tile)
            renderer.alpha = opacity
            tileRenderer = renderer
            return renderer
        }
    }

    let centerCoordinate: CLLocationCoordinate2D?
    let radarOpacity: Double

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.showsUserLocation = true
        map.pointOfInterestFilter = .excludingAll

        let overlay = MKTileOverlay(urlTemplate: WeatherRadarService.radarTileURLTemplate)
        overlay.canReplaceMapContent = false
        overlay.minimumZ = 1
        overlay.maximumZ = 12
        map.addOverlay(overlay, level: .aboveLabels)
        context.coordinator.radarOverlay = overlay

        // Default region — continental US scale. Will be refined when center resolves.
        let initialCenter = centerCoordinate ?? CLLocationCoordinate2D(
            latitude: 39.5, longitude: -98.35
        )
        map.setRegion(
            MKCoordinateRegion(
                center: initialCenter,
                span: MKCoordinateSpan(latitudeDelta: 8, longitudeDelta: 12)
            ),
            animated: false
        )
        context.coordinator.hasSetInitialRegion = centerCoordinate != nil
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.opacity = radarOpacity
        if let renderer = context.coordinator.tileRenderer {
            renderer.alpha = radarOpacity
        }
        if let center = centerCoordinate, !context.coordinator.hasSetInitialRegion {
            map.setRegion(
                MKCoordinateRegion(
                    center: center,
                    span: MKCoordinateSpan(latitudeDelta: 2.5, longitudeDelta: 3.5)
                ),
                animated: true
            )
            context.coordinator.hasSetInitialRegion = true
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(opacity: radarOpacity)
    }
}

// MARK: - RadarLocationManager

@Observable
private final class RadarLocationManager: NSObject, CLLocationManagerDelegate {
    // MARK: Lifecycle

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    // MARK: Internal

    var location: CLLocation?
    var authorizationStatus: CLAuthorizationStatus = .notDetermined

    func requestLocation() {
        manager.requestWhenInUseAuthorization()
        manager.requestLocation()
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        let last = locations.last
        Task { @MainActor in
            self.location = last
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        // Silent — the view falls back to the US center after a timeout.
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorizationStatus = status
        }
    }

    // MARK: Private

    private let manager = CLLocationManager()
}

#Preview {
    NavigationStack {
        WeatherRadarView(grid: "EM10")
    }
}
