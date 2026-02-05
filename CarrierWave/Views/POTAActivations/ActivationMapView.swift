// Activation Map View
//
// Full-screen map showing QSOs from a single POTA activation
// with RST-based contact coloring.

import CarrierWaveCore
import MapKit
import SwiftUI
import UIKit

// MARK: - ActivationMapView

struct ActivationMapView: View {
    // MARK: Internal

    let activation: POTAActivation
    let parkName: String?

    var body: some View {
        ZStack {
            mapContent

            // Stats overlay
            VStack {
                HStack {
                    statsOverlay
                    Spacer()
                    legendOverlay
                }
                .padding()

                Spacer()

                // Selected QSO callout
                if let selected = selectedQSO {
                    qsoCallout(for: selected)
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
        .onAppear {
            computeMapData()
        }
        .sheet(isPresented: $showShareSheet) {
            if let image = shareImage {
                ActivationMapShareSheet(image: image)
            }
        }
    }

    // MARK: Private

    @Environment(\.modelContext) private var modelContext
    @State private var cameraPosition: MapCameraPosition = .automatic
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
                                selectedQSO = activation.qsos.first { $0.id == annotation.qsoId }
                            }
                        }
                    }
                }
            }

            // Geodesic arcs from my location to each QSO
            ForEach(arcs) { arc in
                MapPolyline(coordinates: arc.geodesicPath())
                    .stroke(.blue.opacity(0.4), lineWidth: 2)
            }

            // My location marker
            if let myCoord = myCoordinate {
                Annotation("My Location", coordinate: myCoord, anchor: .center) {
                    Circle()
                        .fill(.blue)
                        .frame(width: 12, height: 12)
                        .overlay(
                            Circle()
                                .stroke(.white, lineWidth: 2)
                        )
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic))
    }

    private var statsOverlay: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let name = parkName {
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
        }
        .padding(8)
        .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private var legendOverlay: some View {
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
        .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private func qsoCallout(for qso: QSO) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(qso.callsign)
                    .font(.headline)
                Spacer()
                Text(qso.band)
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.2))
                    .clipShape(Capsule())
                Text(qso.mode)
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.green.opacity(0.2))
                    .clipShape(Capsule())
            }

            HStack {
                if let grid = qso.theirGrid {
                    Text(grid)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let sent = qso.rstSent {
                    Text("S: \(sent)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let rcvd = qso.rstReceived {
                    Text("R: \(rcvd)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let name = qso.name {
                Text(name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func computeMapData() {
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

        // Set initial camera to show all annotations
        if let region = ActivationMapHelpers.mapRegion(
            qsoCoordinates: newAnnotations.map(\.coordinate),
            myCoordinate: myCoordinate
        ) {
            cameraPosition = .region(region)
        }
    }

    private func generateAndShare() async {
        isGeneratingShare = true

        let image = await ActivationShareRenderer.renderWithMap(
            activation: activation,
            parkName: parkName,
            myGrid: activation.qsos.first?.myGrid
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

// MARK: - RSTAnnotation

/// Annotation with RST-based color information
struct RSTAnnotation: Identifiable {
    let qsoId: UUID
    let callsign: String
    let coordinate: CLLocationCoordinate2D
    let color: Color
    let rstSent: String?
    let rstReceived: String?

    var id: UUID {
        qsoId
    }
}

// MARK: - RSTMarkerView

struct RSTMarkerView: View {
    let annotation: RSTAnnotation
    var isSelected: Bool = false

    var body: some View {
        Circle()
            .fill(annotation.color)
            .frame(width: isSelected ? 16 : 12, height: isSelected ? 16 : 12)
            .overlay(
                Circle()
                    .stroke(isSelected ? Color.white : Color.clear, lineWidth: 2)
            )
            .shadow(radius: isSelected ? 4 : 2)
            .animation(.easeInOut(duration: 0.2), value: isSelected)
    }
}

// MARK: - RSTColorHelper

enum RSTColorHelper {
    /// Compute color based on average of RST sent and received
    /// Green: average >= 55 (excellent)
    /// Yellow: average >= 45 (good)
    /// Red: average < 45 (weak)
    static func color(rstSent: String?, rstReceived: String?) -> Color {
        let avg = averageRST(rstSent, rstReceived)
        if avg >= 55 {
            return .green
        } else if avg >= 45 {
            return .yellow
        } else {
            return .red
        }
    }

    /// Parse RST string and extract numeric value
    /// "599" -> 59, "59" -> 59, "579" -> 57, "449" -> 44
    static func parseRST(_ rst: String?) -> Int? {
        guard let rst, !rst.isEmpty else {
            return nil
        }

        // Remove any non-numeric characters
        let digits = rst.filter(\.isNumber)

        guard !digits.isEmpty else {
            return nil
        }

        // For 3-digit RST (CW/digital): take first two digits (RS portion)
        // For 2-digit RS (phone): take both digits
        if digits.count >= 2 {
            let rs = String(digits.prefix(2))
            return Int(rs)
        } else if digits.count == 1 {
            // Single digit, multiply by 10 (e.g., "5" -> 50)
            return Int(digits)! * 10
        }

        return nil
    }

    /// Calculate average of sent and received RST values
    /// Returns default of 55 if neither can be parsed
    static func averageRST(_ sent: String?, _ received: String?) -> Int {
        let sentValue = parseRST(sent)
        let receivedValue = parseRST(received)

        switch (sentValue, receivedValue) {
        case let (sent?, received?):
            return (sent + received) / 2
        case (let sent?, nil):
            return sent
        case (nil, let received?):
            return received
        case (nil, nil):
            return 55 // Default to middle (green) if no RST data
        }
    }
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
