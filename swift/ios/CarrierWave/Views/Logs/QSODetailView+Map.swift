import CarrierWaveCore
import CarrierWaveData
import CoreLocation
import MapKit
import SwiftUI

// MARK: - QSO Map Section

extension QSODetailView {
    /// Shows a point-to-point map between the operator and contacted station.
    /// Location resolution (grid squares, POTA park fallback for both sides) happens
    /// in Rust via `MapApi.qsoDetailMap`.
    var mapSection: some View {
        QSOMapSectionView(qso: qso)
    }
}

// MARK: - QSOMapSectionView

/// Loads `MapApi.qsoDetailMap` for a QSO and renders the point-to-point map + distance footer.
private struct QSOMapSectionView: View {
    // MARK: Internal

    let qso: QSO

    var body: some View {
        Group {
            if let detail, let myCoord = detail.my, let theirCoord = detail.their {
                Section {
                    VStack(spacing: 0) {
                        qsoMapCallsignHeader(mySubtitle: qso.myGrid ?? qso.parkReference ?? "")
                        qsoMapView(detail: detail, myCoord: myCoord, theirCoord: theirCoord)
                            .frame(height: 200)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        qsoMapDistanceFooter(distanceKm: detail.distanceKm)
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }
            }
        }
        .task(id: qso.id) {
            await loadDetail()
        }
    }

    // MARK: Private

    @State private var detail: FfiQsoDetailMap?

    private var theirSubtitle: String {
        switch detail?.theirSource {
        case "grid":
            qso.theirGrid ?? ""
        case "park":
            qso.theirParkReference ?? ""
        default:
            ""
        }
    }

    // MARK: - Map View

    @ViewBuilder
    private func qsoMapView(
        detail: FfiQsoDetailMap,
        myCoord: FfiCoordinate,
        theirCoord: FfiCoordinate
    ) -> some View {
        let myCoordinate = CLLocationCoordinate2D(latitude: myCoord.latitude, longitude: myCoord.longitude)
        let theirCoordinate = CLLocationCoordinate2D(latitude: theirCoord.latitude, longitude: theirCoord.longitude)
        let isWideSpan = ActivationMapHelpers.requiresGlobeView(
            qsoCoordinates: [theirCoordinate],
            myCoordinate: myCoordinate
        )

        Map(position: mapCameraBinding(myCoord: myCoordinate, theirCoord: theirCoordinate)) {
            ForEach(Array(detail.arc.enumerated()), id: \.offset) { _, polyline in
                MapPolyline(coordinates: polyline.points.map {
                    CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
                })
                .stroke(.white.opacity(0.5), lineWidth: 2.5)
            }

            Annotation(qso.myCallsign, coordinate: myCoordinate, anchor: .bottom) {
                MapPinMarker(color: .blue, size: 12)
            }

            Annotation(qso.callsign, coordinate: theirCoordinate, anchor: .bottom) {
                MapPinMarker(
                    color: bandColor(qso.band),
                    size: 12
                )
            }
        }
        .standardMapStyle(isWideSpan: isWideSpan)
        .allowsHitTesting(false)
    }

    // MARK: - Callsign Header

    private func qsoMapCallsignHeader(mySubtitle: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(qso.myCallsign)
                    .font(.caption.monospaced().weight(.semibold))
                Text(mySubtitle)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "arrow.right")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(qso.callsign)
                    .font(.caption.monospaced().weight(.semibold))
                Text(theirSubtitle)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.bottom, 6)
    }

    // MARK: - Distance Footer

    private func qsoMapDistanceFooter(distanceKm: Double?) -> some View {
        HStack {
            Spacer()
            if let distanceKm {
                Text(UnitFormatter.distance(distanceKm))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.top, 6)
    }

    private func loadDetail() async {
        do {
            let store = try await CwStoreProvider.shared.store()
            let api = MapApi(store: store)
            let qsoId = qso.id.uuidString.lowercased()
            detail = try await Task.detached { try api.qsoDetailMap(qsoId: qsoId) }.value
        } catch {
            RadioService.shared.addLog(.error, "QSO detail map load failed: \(error)")
        }
    }

    private func mapCameraBinding(
        myCoord: CLLocationCoordinate2D,
        theirCoord: CLLocationCoordinate2D
    ) -> Binding<MapCameraPosition> {
        .constant(
            ActivationMapHelpers.mapCameraPosition(
                qsoCoordinates: [theirCoord],
                myCoordinate: myCoord
            )
        )
    }

    // MARK: - Band Color

    private func bandColor(_ band: String) -> Color {
        switch band.lowercased() {
        case "160m": .indigo
        case "80m": .purple
        case "60m": .cyan
        case "40m": .green
        case "30m": .teal
        case "20m": .blue
        case "17m": .mint
        case "15m": .orange
        case "12m": .pink
        case "10m": .red
        case "6m": .yellow
        case "2m": .brown
        default: .gray
        }
    }
}
