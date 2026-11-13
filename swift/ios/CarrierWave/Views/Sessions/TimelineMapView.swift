// Timeline Map View
//
// Session replay view combining a map with a time slider and playback controls.
// Shows QSOs and RBN spots appearing chronologically as the timeline advances.
// QSOs persist on the map; RBN spots appear as circles sized by SNR (10–36pt)
// that shrink over time and fade out between 5–10 minutes.
//
// Data comes from the shared Rust `MapApi.sessionTimeline`, which merges QSOs
// and RBN spots into time-sorted events and resolves spotter grids from the
// `callbook_location` cache. Unresolved spotters are refined via a
// store-backed `QrzApi.locate` pass, then the timeline is re-fetched once to
// pick up the newly cached locations.

import CarrierWaveCore
import CarrierWaveData
import CoreLocation
import MapKit
import SwiftData
import SwiftUI

// MARK: - TimelineMapEvent

/// Unified event type combining QSOs and SessionSpots for timeline replay,
/// built from the shared Rust `FfiTimelineEvent`.
struct TimelineMapEvent: Identifiable {
    // MARK: Lifecycle

    init(ffi: FfiTimelineEvent) {
        id = ffi.id
        timestamp = Date(timeIntervalSince1970: TimeInterval(ffi.timestamp))
        kind = ffi.isQso ? .qso : .rbnSpot
        callsign = ffi.callsign
        // Parity with the pre-Rust-port Swift loader: a missing spot band
        // displayed as "Unknown" rather than an empty string.
        band = ffi.band ?? "Unknown"
        mode = ffi.mode ?? ""
        let coord: CLLocationCoordinate2D? = if let lat = ffi.latitude, let lon = ffi.longitude {
            CLLocationCoordinate2D(latitude: lat, longitude: lon)
        } else {
            nil
        }
        coordinate = coord
        snr = ffi.snr.map { Int($0) }
        spotter = ffi.spotter
        spotterCoordinate = coord
    }

    // MARK: Internal

    enum Kind {
        case qso
        case rbnSpot
    }

    let id: String
    let timestamp: Date
    let kind: Kind
    let callsign: String
    let band: String
    let mode: String
    let coordinate: CLLocationCoordinate2D?
    let snr: Int?
    let spotter: String?
    let spotterCoordinate: CLLocationCoordinate2D?
}

// MARK: - TimelineMapView

struct TimelineMapView: View {
    // MARK: Internal

    let session: LoggingSession

    @Environment(\.modelContext) var modelContext

    var body: some View {
        VStack(spacing: 0) {
            if isLoaded {
                mapContent
                Divider()
                controlsPanel
            } else {
                ProgressView("Loading timeline…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Session Replay")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadData() }
        .onDisappear { stopPlayback() }
    }

    // MARK: Private

    @State private var events: [TimelineMapEvent] = []
    @State private var myCoordinate: CLLocationCoordinate2D?
    @State private var sessionStartedAt: Date = .init()
    @State private var sessionEndedAt: Date = .init()
    @State private var currentTime: TimeInterval = 0
    @State private var isPlaying = false
    @State private var playbackSpeed: Double = 1.0
    @State private var mapCamera: MapCameraPosition = .automatic
    @State private var isLoaded = false
}

// MARK: - Map Content

extension TimelineMapView {
    private var mapContent: some View {
        Map(position: $mapCamera) {
            if let myCoordinate {
                MapContentBuilders.myLocationMarker(at: myCoordinate)
            }
            ForEach(visibleQSOs) { event in
                if let coord = event.coordinate {
                    Annotation(event.callsign, coordinate: coord, anchor: .bottom) {
                        qsoMarker
                    }
                    if let myCoordinate {
                        MapContentBuilders.geodesicArc(
                            from: myCoordinate, to: coord,
                            color: .blue.opacity(0.5), lineWidth: 2
                        )
                    }
                }
            }
            ForEach(visibleSpots) { event in
                if let coord = event.coordinate {
                    let opacity = spotOpacity(for: event)
                    let decay = spotDecayFraction(for: event)
                    Annotation(
                        spotLabel(for: event),
                        coordinate: coord,
                        anchor: .center
                    ) {
                        spotMarker(snr: event.snr, opacity: opacity, decayFraction: decay)
                    }
                    if let myCoordinate, opacity > 0.1 {
                        MapContentBuilders.geodesicArc(
                            from: myCoordinate, to: coord,
                            color: spotColor(snr: event.snr).opacity(0.3 * opacity), lineWidth: 1
                        )
                    }
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic))
    }

    private var qsoMarker: some View {
        Circle()
            .fill(.blue)
            .frame(width: 10, height: 10)
            .overlay(Circle().stroke(.white, lineWidth: 1.5))
    }

    private func spotMarker(snr: Int?, opacity: Double, decayFraction: Double) -> some View {
        let baseSize = snrCircleSize(snr: snr)
        let size = baseSize * decayFraction
        let color = spotColor(snr: snr)
        return Circle()
            .fill(color.opacity(opacity * 0.35))
            .frame(width: size, height: size)
            .overlay(Circle().stroke(color.opacity(opacity * 0.8), lineWidth: 1.5))
    }

    /// Maps SNR to the same band colors as `SpotsMiniMapView.snrColor` for
    /// cross-platform parity (band 3→green, 2→blue, 1→orange, else red).
    /// A missing SNR uses blue, matching the mini-map's no-SNR case.
    private func spotColor(snr: Int?) -> Color {
        guard let snr else {
            return .blue
        }
        switch timelineSnrColorBand(snr: Int64(snr)) {
        case 3: return .green
        case 2: return .blue
        case 1: return .orange
        default: return .red
        }
    }
}

// MARK: - Controls Panel

extension TimelineMapView {
    private var controlsPanel: some View {
        VStack(spacing: 8) {
            TimelineSliderView(
                currentTime: $currentTime,
                duration: sessionDuration,
                events: events,
                startDate: sessionStartedAt
            )

            HStack(spacing: 20) {
                playPauseButton
                speedButton
                Spacer()
                eventCountLabel
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .padding(.top, 8)
        .background(.ultraThinMaterial)
    }

    private var playPauseButton: some View {
        Button {
            togglePlayback()
        } label: {
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.title2)
        }
    }

    private var speedButton: some View {
        Button {
            cycleSpeed()
        } label: {
            Text("\(formattedSpeed)x")
                .font(.caption)
                .fontWeight(.medium)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.quaternary, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var eventCountLabel: some View {
        let qsoCount = visibleQSOs.count
        let spotCount = visibleSpots.count
        return HStack(spacing: 8) {
            Label("\(qsoCount)", systemImage: "antenna.radiowaves.left.and.right")
                .foregroundStyle(.blue)
            Label("\(spotCount)", systemImage: "dot.radiowaves.right")
                .foregroundStyle(.green)
        }
        .font(.caption)
    }
}

// MARK: - Computed Properties

extension TimelineMapView {
    private var sessionDuration: TimeInterval {
        sessionEndedAt.timeIntervalSince(sessionStartedAt)
    }

    private var currentDate: Date {
        sessionStartedAt.addingTimeInterval(currentTime)
    }

    private var visibleQSOs: [TimelineMapEvent] {
        let cutoff = currentDate
        return events.filter { $0.kind == .qso && $0.timestamp <= cutoff }
    }

    /// All RBN spots in the current time window (for counting)
    private var visibleSpots: [TimelineMapEvent] {
        let cutoff = currentDate
        let decayLimit: TimeInterval = 600
        return events.filter { event in
            guard event.kind == .rbnSpot, event.timestamp <= cutoff else {
                return false
            }
            let age = cutoff.timeIntervalSince(event.timestamp)
            return age < decayLimit
        }
    }

    private var formattedSpeed: String {
        playbackSpeed == 1.0 ? "1" : String(format: "%.0f", playbackSpeed)
    }
}

// MARK: - Playback Logic

extension TimelineMapView {
    private func spotOpacity(for event: TimelineMapEvent) -> Double {
        let age = currentDate.timeIntervalSince(event.timestamp)
        return timelineSpotOpacity(ageSecs: age)
    }

    /// Returns 1.0 at birth, decaying to 0.3 at the 10-minute limit.
    private func spotDecayFraction(for event: TimelineMapEvent) -> Double {
        let age = currentDate.timeIntervalSince(event.timestamp)
        return timelineSpotDecay(ageSecs: age)
    }

    /// Maps SNR (typically 0–40 dB) to a circle diameter (10–36 pt).
    private func snrCircleSize(snr: Int?) -> Double {
        timelineSnrMarkerSize(snr: snr.map { Int64($0) })
    }

    private func spotLabel(for event: TimelineMapEvent) -> String {
        if let snr = event.snr {
            return "\(event.spotter ?? "RBN") \(snr)dB"
        }
        return event.spotter ?? "RBN"
    }

    private func togglePlayback() {
        if isPlaying {
            stopPlayback()
        } else {
            startPlayback()
        }
    }

    private func startPlayback() {
        if currentTime >= sessionDuration {
            currentTime = 0
        }
        isPlaying = true
        schedulePlaybackTick()
    }

    private func stopPlayback() {
        isPlaying = false
    }

    private func schedulePlaybackTick() {
        guard isPlaying else {
            return
        }
        let tickInterval: TimeInterval = 1.0 / 30.0
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(tickInterval))
            guard isPlaying else {
                return
            }
            currentTime += tickInterval * playbackSpeed
            if currentTime >= sessionDuration {
                currentTime = sessionDuration
                isPlaying = false
            } else {
                schedulePlaybackTick()
            }
        }
    }

    private func cycleSpeed() {
        let speeds: [Double] = [1, 2, 4, 8]
        let currentIdx = speeds.firstIndex(of: playbackSpeed) ?? 0
        let nextIdx = (currentIdx + 1) % speeds.count
        playbackSpeed = speeds[nextIdx]
    }
}

// MARK: - Data Loading

extension TimelineMapView {
    private func loadData() async {
        let sessionId = session.id.uuidString.lowercased()

        guard var data = await fetchTimeline(sessionId: sessionId) else {
            return
        }

        if !data.unresolvedSpotters.isEmpty {
            await refineUnresolvedSpotters(data.unresolvedSpotters)
            if let refined = await fetchTimeline(sessionId: sessionId) {
                data = refined
            }
        }

        applyTimeline(data)
        isLoaded = true
    }

    /// Fetch the session timeline from `MapApi`, logging and returning `nil` on failure.
    private func fetchTimeline(sessionId: String) async -> FfiTimelineData? {
        do {
            let store = try await CwStoreProvider.shared.store()
            let api = MapApi(store: store)
            return try await Task.detached { try api.sessionTimeline(sessionId: sessionId) }.value
        } catch {
            RadioService.shared.addLog(.error, "Timeline load failed: \(error)")
            return nil
        }
    }

    /// Warm the `callbook_location` cache for spotters the timeline couldn't resolve,
    /// via a store-backed `QrzApi.locate` pass. Best-effort — failures are non-fatal
    /// since the timeline still renders with unresolved spots simply lacking a location.
    private func refineUnresolvedSpotters(_ spotters: [String]) async {
        do {
            let store = try await CwStoreProvider.shared.store()
            let qrzApi = try QrzApi.withStore(secure: KeychainSecureStore(), store: store)
            _ = try? await qrzApi.locate(callsigns: spotters)
        } catch {
            RadioService.shared.addLog(.error, "Timeline spotter refinement failed: \(error)")
        }
    }

    private func applyTimeline(_ data: FfiTimelineData) {
        events = data.events.map(TimelineMapEvent.init(ffi:))
        sessionStartedAt = Date(timeIntervalSince1970: TimeInterval(data.startedAt))
        sessionEndedAt = Date(timeIntervalSince1970: TimeInterval(data.endedAt))

        let myCoord: CLLocationCoordinate2D? = if let lat = data.myLatitude, let lon = data.myLongitude {
            CLLocationCoordinate2D(latitude: lat, longitude: lon)
        } else {
            nil
        }
        myCoordinate = myCoord

        if let myCoord {
            let allCoords = events.compactMap(\.coordinate) + [myCoord]
            mapCamera = ActivationMapHelpers.mapCameraPosition(
                qsoCoordinates: allCoords, myCoordinate: myCoord
            )
        }
    }
}
