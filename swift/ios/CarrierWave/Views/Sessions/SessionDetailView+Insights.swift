// Session Detail View - Insights Carousel
//
// Tier 3 swipeable card carousel: Map thumbnail, States mosaic,
// Park boundaries, and SDR recording. Tap to expand into full views.

import CarrierWaveCore
import CarrierWaveData
import MapKit
import SwiftUI

// MARK: - Insights Carousel

extension SessionDetailView {
    @ViewBuilder
    var insightsCarousel: some View {
        let cards = buildInsightCards()
        if !cards.isEmpty {
            Section("Insights") {
                TabView {
                    ForEach(cards) { card in
                        card.content
                            .padding(.horizontal, 4)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .automatic))
                .frame(height: 200)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))

                if let session {
                    NavigationLink {
                        TimelineMapView(session: session)
                    } label: {
                        Label("Session Replay", systemImage: "play.circle")
                    }

                    VideoExportButton(
                        session: session,
                        hasQSOsWithCoordinates: qsos.contains { $0.theirGrid != nil },
                        hasRecording: recording != nil
                    )
                }

                if let recording {
                    recordingRow(recording)
                }
            }
        }
    }

    private func buildInsightCards() -> [InsightCard] {
        var cards: [InsightCard] = []

        let mappable = mappableQSOs
        if !mappable.isEmpty {
            cards.append(InsightCard(id: "map") {
                AnyView(mapInsightCard(qsos: mappable))
            })
        }

        let stateCounts = insightStateCounts
        if !stateCounts.isEmpty {
            cards.append(InsightCard(id: "states") {
                AnyView(statesInsightCard(worked: stateCounts.count))
            })
        }

        for card in parkCards {
            cards.append(InsightCard(id: "park-\(card.id)") {
                AnyView(parkInsightCard(card))
            })
        }

        return cards
    }

    // MARK: - Mappable QSOs (shared computation)

    var mappableQSOs: [QSO] {
        displayQSOs.filter { qso in
            guard let grid = qso.theirGrid, grid.count >= 4 else {
                return false
            }
            return maidenheadCoordinate(grid: grid) != nil
        }
    }

    /// State counts for insight card — lightweight check
    private var insightStateCounts: [String: Int] {
        stateQSOCounts
    }
}

// MARK: - Map Insight Card

extension SessionDetailView {
    private func mapInsightCard(qsos mappable: [QSO]) -> some View {
        let myCoord: CLLocationCoordinate2D? = {
            let grid = session?.myGrid ?? mappable.first?.myGrid
            guard let grid, let coord = maidenheadCoordinate(grid: grid) else {
                return nil
            }
            return CLLocationCoordinate2D(latitude: coord.latitude, longitude: coord.longitude)
        }()

        return NavigationLink {
            mapDestinationView
        } label: {
            mapPreviewContent(mappable: mappable, myCoord: myCoord)
                .frame(height: 180)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .allowsHitTesting(false)
        }
        .buttonStyle(.plain)
    }

    /// The pushed `activation` is a snapshot frozen at navigation time;
    /// regroup from the live QSO state so the full map reflects merges
    /// and imports that happened while this detail view was alive.
    private var liveActivation: POTAActivation? {
        guard let activation else {
            return nil
        }
        return POTAActivation.groupQSOs(qsos)
            .first { $0.id == activation.id } ?? activation
    }

    @ViewBuilder
    private var mapDestinationView: some View {
        if let activation = liveActivation {
            ActivationMapView(
                activation: activation,
                parkName: parkName,
                metadata: activationMetadata,
                roveStops: session?.isRove == true
                    ? (session?.mergedRoveStops ?? []) : []
            )
        } else {
            SidebarMapView(
                sessionQSOs: qsos,
                myGrid: session?.myGrid,
                roveStops: session?.isRove == true
                    ? (session?.mergedRoveStops ?? []) : []
            )
            .navigationTitle("Session Map")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - States Insight Card

extension SessionDetailView {
    private func statesInsightCard(worked: Int) -> some View {
        NavigationLink {
            statesDetailView(worked: worked)
        } label: {
            ZStack(alignment: .bottomLeading) {
                StatesWorkedMosaic(
                    stateCounts: stateQSOCounts,
                    stateCallsigns: stateCallsignMap
                )
                .frame(height: 180)
                .allowsHitTesting(false)

                Text("\(worked) / 50 States")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .padding(8)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private func statesDetailView(worked: Int) -> some View {
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
    }
}

// MARK: - Park Insight Card (individual)

extension SessionDetailView {
    private func parkInsightCard(_ card: ParkCardItem) -> some View {
        NavigationLink {
            parksDetailView
        } label: {
            ParkCardView(card: card)
                .frame(height: 200)
                .allowsHitTesting(false)
        }
        .buttonStyle(.plain)
    }

    private var parksDetailView: some View {
        List {
            Section {
                ParkCardCarouselView(cards: parkCards)
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        }
        .navigationTitle("Park Boundaries")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Recording Row

extension SessionDetailView {
    func recordingRow(_ recording: WebSDRRecording) -> some View {
        NavigationLink {
            RecordingPlayerView(
                recording: recording,
                initialQSOs: activation?.qsos ?? qsos,
                engine: engine
            )
        } label: {
            CompactRecordingPlayer(
                recording: recording,
                qsos: activation?.qsos ?? qsos,
                engine: engine
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - InsightCard

private struct InsightCard: Identifiable {
    // MARK: Lifecycle

    init(id: String, @ViewBuilder content: () -> AnyView) {
        self.id = id
        self.content = content()
    }

    // MARK: Internal

    let id: String
    let content: AnyView
}
