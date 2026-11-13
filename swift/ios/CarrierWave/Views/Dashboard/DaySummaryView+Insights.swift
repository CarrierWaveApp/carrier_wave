import CarrierWaveCore
import CarrierWaveData
import CoreLocation
import MapKit
import SwiftUI
import UIKit

// MARK: - DaySummaryView + Insights

/// Swipeable insights carousel — mirrors `SessionDetailView+Insights`.
/// Renders a map of QSOs with valid grids and (when any are US-domestic)
/// a US states mosaic. Cards push to full-screen detail on tap.
extension DaySummaryView {
    @ViewBuilder
    var insightsSection: some View {
        let cards = buildInsightCards()
        if !cards.isEmpty {
            Section("Insights") {
                TabView {
                    ForEach(0 ..< cards.count, id: \.self) { index in
                        cards[index]
                            .padding(.horizontal, 4)
                    }
                }
                // Hide page dots when only one card is visible — the
                // floating dot under a single card reads as a glitch.
                .tabViewStyle(.page(indexDisplayMode: cards.count > 1 ? .automatic : .never))
                .frame(height: 200)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                .listRowSeparator(.hidden)
            }
        }
    }

    private func buildInsightCards() -> [AnyView] {
        var cards: [AnyView] = []

        // Map card always present so the day always opens with a
        // geographic anchor; falls back to operator-only when no QSOs
        // carry a grid.
        cards.append(AnyView(mapInsightCard(qsos: mappableQSOs)))

        let stateCounts = stateQSOCounts
        if !stateCounts.isEmpty {
            cards.append(AnyView(statesInsightCard(worked: stateCounts.count)))
        }

        return cards
    }

    // MARK: - Mapping helpers

    var mappableQSOs: [QSO] {
        bridgedDayQSOs.filter { qso in
            guard let grid = qso.theirGrid, grid.count >= 4 else {
                return false
            }
            return MaidenheadConverter.coordinate(from: grid) != nil
        }
    }

    /// Best-effort operator grid for the day. The activity log manager isn't
    /// in scope on this view, so we fall back to the first QSO's recorded
    /// `myGrid`.
    var resolvedMyGrid: String? {
        bridgedDayQSOs.first(where: { $0.myGrid?.isEmpty == false })?.myGrid
    }

    // MARK: - Map Card

    private func mapInsightCard(qsos mappable: [QSO]) -> some View {
        NavigationLink {
            SidebarMapView(
                sessionQSOs: mappable,
                myGrid: resolvedMyGrid,
                roveStops: []
            )
            .navigationTitle("Daily Map")
            .navigationBarTitleDisplayMode(.inline)
        } label: {
            ZStack(alignment: .bottomTrailing) {
                mapBody(qsos: mappable)
                    .frame(height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .allowsHitTesting(false)

                Text(mapBadgeText(mappable: mappable))
                    .font(.caption2.weight(.medium).monospacedDigit())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .padding(8)
            }
        }
        .buttonStyle(.plain)
    }

    /// The custom styles render via the Rust `renderShareMap` FFI (through
    /// `ThemedMapImage`, same path as the activation share card, session
    /// detail, propagation check card, and club map). Adaptive / flat /
    /// globe styles use the interactive `SessionQSOMap`.
    @ViewBuilder
    private func mapBody(qsos mappable: [QSO]) -> some View {
        let style = ShareMapStyle(rawValue: shareMapStyleRaw) ?? .adaptive
        if style.usesCustomRenderer {
            let markers = themedMarkers(from: mappable)
            ThemedMapImage(
                coordinates: markers.map(\.coordinate),
                myCoordinate: themedMyCoordinate,
                style: style,
                pinColors: markers.map(\.color)
            )
        } else {
            SessionQSOMap(sessionQSOs: mappable, myGrid: resolvedMyGrid)
        }
    }

    private func themedMarkers(
        from qsos: [QSO]
    ) -> [(coordinate: CLLocationCoordinate2D, color: UIColor)] {
        qsos.compactMap { qso in
            guard let grid = qso.theirGrid,
                  let coord = MaidenheadConverter.coordinate(from: grid)
            else {
                return nil
            }
            return (
                CLLocationCoordinate2D(
                    latitude: coord.latitude,
                    longitude: coord.longitude
                ),
                UIColor(BandColors.color(for: qso.band))
            )
        }
    }

    private var themedMyCoordinate: CLLocationCoordinate2D? {
        guard let grid = resolvedMyGrid,
              let coord = MaidenheadConverter.coordinate(from: grid)
        else {
            return nil
        }
        return CLLocationCoordinate2D(latitude: coord.latitude, longitude: coord.longitude)
    }

    private func mapBadgeText(mappable: [QSO]) -> String {
        if bridgedDayQSOs.isEmpty {
            return "No QSOs"
        }
        if mappable.isEmpty {
            return "No grids"
        }
        return "\(mappable.count) of \(bridgedDayQSOs.count)"
    }

    // MARK: - States Mosaic Card

    private func statesInsightCard(worked: Int) -> some View {
        NavigationLink {
            List {
                Section {
                    StatesWorkedMosaic(
                        stateCounts: stateQSOCounts,
                        stateCallsigns: stateCallsignMap
                    )
                }
            }
            .navigationTitle("States Worked (\(worked)/50)")
            .navigationBarTitleDisplayMode(.inline)
        } label: {
            // The mosaic carries its own "N / 50" header and legend, so no
            // overlay is added here — an extra badge collides with the
            // legend at the bottom of the cell.
            StatesWorkedMosaic(
                stateCounts: stateQSOCounts,
                stateCallsigns: stateCallsignMap
            )
            .frame(height: 180)
            .allowsHitTesting(false)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Per-state counts

    var stateQSOCounts: [String: Int] {
        var counts: [String: Int] = [:]
        for qso in bridgedDayQSOs {
            guard let raw = qso.state else {
                continue
            }
            let state = USStates.normalizeAbbreviation(raw)
            guard USStates.abbreviations.contains(state) else {
                continue
            }
            counts[state, default: 0] += 1
        }
        return counts
    }

    var stateCallsignMap: [String: [String]] {
        var map: [String: [String]] = [:]
        for qso in bridgedDayQSOs {
            guard let raw = qso.state else {
                continue
            }
            let state = USStates.normalizeAbbreviation(raw)
            guard USStates.abbreviations.contains(state) else {
                continue
            }
            map[state, default: []].append(qso.callsign)
        }
        return map
    }
}
