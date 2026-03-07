// Activation Map View
//
// Full-screen map showing QSOs from a single POTA activation
// with RST-based contact coloring. For rove sessions, also shows
// numbered park stop markers and a dashed route line.

import CarrierWaveData
import MapKit
import SwiftUI
import UIKit

// MARK: - ActivationMapView

struct ActivationMapView: View {
    // MARK: Internal

    let activation: POTAActivation
    let parkName: String?
    var metadata: ActivationMetadata?
    var roveStops: [RoveStop] = []

    var body: some View {
        let _ = useMetricUnits // Trigger re-render when unit preference changes
        ZStack {
            mapContent

            // Stats overlay
            VStack {
                HStack(alignment: .top) {
                    statsOverlay
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        legendOverlay
                        activationStatsView
                    }
                }
                .padding()

                Spacer()

                // Selected QSO callout
                if let selected = selectedQSO {
                    ActivationQSOCallout(qso: selected)
                        .padding()
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .navigationTitle(activation.parkReference)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task {
                        await generateAndShare()
                    }
                } label: {
                    if isGeneratingShare {
                        ProgressView()
                    } else {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
                .disabled(isGeneratingShare)
            }
        }
        .task {
            computeMapData()
            if isWideSpan {
                try? await Task.sleep(for: .seconds(0.5))
                nudgeActivationCamera()
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let image = shareImage {
                ActivationMapShareSheet(image: image)
            }
        }
    }

    // MARK: Private

    @AppStorage("useMetricUnits") private var useMetricUnits = false

    @Environment(\.modelContext) private var modelContext
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var isWideSpan = false
    @State private var selectedQSO: QSO?
    @State private var annotations: [RSTAnnotation] = []
    @State private var arcs: [QSOArc] = []
    @State private var isGeneratingShare = false
    @State private var shareImage: UIImage?
    @State private var showShareSheet = false

    /// My coordinate (from myGrid on first QSO)
    private var myCoordinate: CLLocationCoordinate2D? {
        guard let grid = activation.qsos.first?.myGrid else {
            return nil
        }
        return MaidenheadConverter.coordinate(from: grid)
    }

    private var isRove: Bool {
        !roveStops.isEmpty
    }

    /// Coordinates for rove stops, falling back to first QSO grid
    private var roveStopCoordinates: [(stop: RoveStop, coordinate: CLLocationCoordinate2D)] {
        let fallbackGrid = activation.qsos.first?.myGrid
        return roveStops.compactMap { stop in
            let grid = stop.myGrid ?? fallbackGrid
            guard let grid, grid.count >= 4,
                  let coord = MaidenheadConverter.coordinate(from: grid)
            else {
                return nil
            }
            return (stop: stop, coordinate: coord)
        }
    }

    private var activationStatistics: MapStatistics {
        ActivationStatsHelper.statistics(for: activation)
    }

    private var activationRadio: String? {
        activation.qsos.compactMap(\.myRig).first
    }

    private var activationWatts: Int? {
        metadata?.watts ?? activation.qsos.compactMap(\.power).first
    }

    private var mapContent: some View {
        Map(position: $cameraPosition) {
            // QSO markers with RST coloring
            ForEach(annotations) { annotation in
                Annotation(
                    annotation.callsign,
                    coordinate: annotation.coordinate,
                    anchor: .bottom
                ) {
                    RSTMarkerView(
                        annotation: annotation,
                        isSelected: selectedQSO?.id == annotation.qsoId
                    )
                    .onTapGesture {
                        withAnimation {
                            if selectedQSO?.id == annotation.qsoId {
                                selectedQSO = nil
                            } else {
                                selectedQSO = activation.qsos.first {
                                    $0.id == annotation.qsoId
                                }
                            }
                        }
                    }
                }
            }

            // Geodesic arcs from my location to each QSO
            ForEach(arcs) { arc in
                MapPolyline(coordinates: arc.path)
                    .stroke(.white.opacity(0.5), lineWidth: 2.5)
            }

            // Rove stop markers
            ForEach(
                Array(roveStopCoordinates.enumerated()), id: \.element.stop.id
            ) { index, item in
                Annotation(
                    item.stop.parkReference,
                    coordinate: item.coordinate,
                    anchor: .bottom
                ) {
                    roveStopMarker(item.stop, index: index)
                }
            }

            // Route line between rove stops
            if roveStopCoordinates.count >= 2 {
                let coords = roveStopCoordinates.map(\.coordinate)
                MapPolyline(coordinates: coords)
                    .stroke(.green, style: StrokeStyle(
                        lineWidth: 3,
                        dash: [8, 4]
                    ))
            }

            // My location marker (non-rove only — rove stops show location)
            if !isRove, let myCoord = myCoordinate {
                Annotation("My Location", coordinate: myCoord, anchor: .bottom) {
                    MapPinMarker(color: .blue, size: 12)
                }
            }
        }
        .mapStyle(isWideSpan
            ? .imagery(elevation: .realistic)
            : .standard(elevation: .realistic))
    }
}

// MARK: - Overlays & Actions

private extension ActivationMapView {
    var statsOverlay: some View {
        VStack(alignment: .leading, spacing: 4) {
            if isRove {
                Text("Rove \u{2013} \(roveStops.count) stops")
                    .font(.caption)
                    .fontWeight(.medium)
            } else if let name = parkName {
                Text(name)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(2)
            }
            Text("\(activation.qsoCount) QSOs")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(activation.mappableQSOs.count) on map")
                .font(.caption2)
                .foregroundStyle(.secondary)
            if let radio = activationRadio {
                Text(radio)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    var activationStatsView: some View {
        let stats = activationStatistics
        return VStack(alignment: .trailing, spacing: 1) {
            if let duration = stats.activationDuration {
                activationStatRow(
                    label: "Time",
                    value: ActivationStatsHelper.formatDuration(duration)
                )
            }
            if let rate = stats.qsoRate {
                activationStatRow(
                    label: "Rate",
                    value: "\(String(format: "%.1f", rate))/hr"
                )
            }
            if let avg = stats.averageDistanceKm {
                activationStatRow(
                    label: "Avg",
                    value: ActivationStatsHelper.formatDistance(avg)
                )
            }
            if let max = stats.longestDistanceKm {
                activationStatRow(
                    label: "Max",
                    value: ActivationStatsHelper.formatDistance(max)
                )
            }
            if let watts = activationWatts {
                activationStatRow(
                    label: "Power",
                    value: "\(watts)W"
                )
            }
            if let wpm = stats.wattsPerMile {
                let displayWpm = UnitFormatter.useMetric ? wpm * 0.621371 : wpm
                activationStatRow(
                    label: UnitFormatter.wattsPerDistanceLabel(),
                    value: String(format: "%.2f", displayWpm)
                )
            }
            if let wpm = metadata?.averageWPM {
                activationStatRow(
                    label: "WPM",
                    value: "\(wpm)"
                )
            }
        }
        .padding(6)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 6))
    }

    var legendOverlay: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text("RST")
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            HStack(spacing: 4) {
                Circle().fill(.green).frame(width: 8, height: 8)
                Text("55+")
                    .font(.caption2)
            }
            HStack(spacing: 4) {
                Circle().fill(.yellow).frame(width: 8, height: 8)
                Text("45-54")
                    .font(.caption2)
            }
            HStack(spacing: 4) {
                Circle().fill(.red).frame(width: 8, height: 8)
                Text("<45")
                    .font(.caption2)
            }
        }
        .padding(8)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    func activationStatRow(label: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.system(size: 9, weight: .medium))
        }
    }

    /// Marker for a rove stop showing park reference and stop number
    func roveStopMarker(_ stop: RoveStop, index: Int) -> some View {
        let primaryPark = ParkReference.split(stop.parkReference).first
            ?? stop.parkReference

        return VStack(spacing: 2) {
            ZStack {
                Circle()
                    .fill(stop.isActive ? Color.green : Color(.systemGray3))
                    .frame(width: 28, height: 28)
                Text("\(index + 1)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
            }

            Text(primaryPark)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.green)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(.ultraThinMaterial, in: Capsule())
        }
    }

    func computeMapData() {
        var newAnnotations: [RSTAnnotation] = []
        var newArcs: [QSOArc] = []

        for qso in activation.mappableQSOs {
            guard let grid = qso.theirGrid,
                  let coord = MaidenheadConverter.coordinate(from: grid)
            else {
                continue
            }

            let rstColor = RSTColorHelper.color(
                rstSent: qso.rstSent,
                rstReceived: qso.rstReceived
            )

            newAnnotations.append(
                RSTAnnotation(
                    qsoId: qso.id,
                    callsign: qso.callsign,
                    coordinate: coord,
                    color: rstColor,
                    rstSent: qso.rstSent,
                    rstReceived: qso.rstReceived
                )
            )

            // Create arc if we have my location
            if let myCoord = myCoordinate {
                newArcs.append(
                    QSOArc(
                        id: qso.id.uuidString,
                        from: myCoord,
                        to: coord,
                        callsign: qso.callsign
                    )
                )
            }
        }

        annotations = newAnnotations
        arcs = newArcs

        // Set initial camera to show all annotations + rove stops
        var allCoords = newAnnotations.map(\.coordinate)
        allCoords.append(contentsOf: roveStopCoordinates.map(\.coordinate))
        let coordsForCamera = allCoords
        let myCoord = isRove ? nil : myCoordinate
        isWideSpan = ActivationMapHelpers.requiresGlobeView(
            qsoCoordinates: coordsForCamera,
            myCoordinate: myCoord
        )
        cameraPosition = ActivationMapHelpers.mapCameraPosition(
            qsoCoordinates: coordsForCamera,
            myCoordinate: myCoord
        )
    }

    private func nudgeActivationCamera() {
        guard let region = cameraPosition.region else {
            return
        }
        cameraPosition = .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: region.center.latitude + 0.001,
                longitude: region.center.longitude
            ),
            span: region.span
        ))
    }

    func generateAndShare() async {
        isGeneratingShare = true

        let statisticianMode = UserDefaults.standard.bool(
            forKey: "statisticianMode"
        )
        let advancedStats: ActivationStatistics? =
            if statisticianMode {
                ActivationStatistics.compute(
                    from: activation, metadata: metadata
                )
            } else {
                nil
            }

        let image = await ActivationShareRenderer.renderWithMap(
            activation: activation,
            parkName: parkName,
            myGrid: activation.qsos.first?.myGrid,
            metadata: metadata,
            statisticianStats: advancedStats
        )

        isGeneratingShare = false

        guard let image else {
            return
        }

        shareImage = image
        showShareSheet = true
    }
}

// MARK: - ActivationMapShareSheet

/// UIKit share sheet for activation map images
private struct ActivationMapShareSheet: UIViewControllerRepresentable {
    let image: UIImage

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(
            activityItems: [image],
            applicationActivities: nil
        )
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Preview

#Preview {
    NavigationStack {
        ActivationMapView(
            activation: POTAActivation(
                parkReference: "US-0001",
                utcDate: Date(),
                callsign: "W1AW",
                qsos: []
            ),
            parkName: "Acadia National Park"
        )
    }
}
