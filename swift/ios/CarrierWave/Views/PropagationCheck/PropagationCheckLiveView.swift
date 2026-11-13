import CarrierWaveCore
import CarrierWaveData
import Combine
import CoreLocation
import MapKit
import SwiftUI

// MARK: - PropagationCheckLiveView

/// Live "watching" screen: world map of incoming spots, header strip, pull-up
/// feed. Driven by an `@Observable` `PropagationCheckSession`.
struct PropagationCheckLiveView: View {
    // MARK: Lifecycle

    init(
        session: PropagationCheckSession,
        onStop: @escaping (PropagationCheckSession.Snapshot) -> Void
    ) {
        self.session = session
        self.onStop = onStop
    }

    // MARK: Internal

    @Bindable var session: PropagationCheckSession

    let onStop: (PropagationCheckSession.Snapshot) -> Void

    var body: some View {
        ZStack(alignment: .top) {
            mapLayer
                .ignoresSafeArea(edges: .bottom)

            VStack(spacing: 0) {
                headerStrip
                autoCQBanner
                Spacer()
            }
        }
        .sheet(isPresented: .constant(true)) {
            spotsFeedSheet
                .presentationDetents([.height(120), .medium, .large], selection: $detent)
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                .interactiveDismissDisabled()
        }
        .onReceive(timer) { _ in
            elapsed = elapsedSeconds()
            checkDurationCap()
        }
        .onAppear {
            elapsed = elapsedSeconds()
        }
    }

    // MARK: Private

    @State private var detent: PresentationDetent = .height(120)
    @State private var elapsed: TimeInterval = 0
    @State private var freshnessOnly: Bool = true
    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 30, longitude: -40),
            span: MKCoordinateSpan(latitudeDelta: 160, longitudeDelta: 320)
        )
    )

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var displayedSpots: [PropagationSpotEntry] {
        if freshnessOnly {
            return session.recentSpots(within: 300) // last 5 min
        }
        return session.spots
    }

    private var pinAnnotations: [PinAnnotation] {
        displayedSpots.compactMap(PinAnnotation.from)
    }

    private var mapLayer: some View {
        Map(position: $cameraPosition) {
            ForEach(pinAnnotations) { pin in
                Annotation(pin.label, coordinate: pin.coordinate, anchor: .center) {
                    spotPin(for: pin)
                }
            }
        }
        .mapStyle(.standard(elevation: .flat))
    }

    private var headerStrip: some View {
        HStack(spacing: 14) {
            metric("⏱", formatElapsed(elapsed))
            metric("📡", "\(session.totalSpots)")
            metric("👂", "\(session.uniqueSkimmers)")
            metric("📶", "\(session.bandsWithActivity.count)")
            Spacer()
            Toggle(isOn: $freshnessOnly) {
                Image(systemName: freshnessOnly ? "clock.fill" : "infinity")
                    .imageScale(.large)
            }
            .labelsHidden()
            .toggleStyle(.button)
            stopButton
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    @ViewBuilder
    private var autoCQBanner: some View {
        if let mode = session.config?.transmitMode, mode != .passive {
            HStack(spacing: 8) {
                if mode == .autoCW {
                    if session.autoCQ.isRunning {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .foregroundStyle(.green)
                        Text("Auto-CQ keying every 30s · \(session.autoCQ.transmissionsSent) sent")
                            .font(.caption)
                    } else if session.autoCQ.lastFault == .radioDisconnected {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        Text("Auto-CQ aborted — radio link lost")
                            .font(.caption)
                    } else if let reason = PropagationAutoCQController.unavailableReason(for: .autoCW) {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                        Text(reason)
                            .font(.caption)
                    }
                } else if mode == .autoFT8 {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.blue)
                    Text("FT8 Auto-CQ: trigger CQ from the FT8 panel; this check is watching PSK Reporter.")
                        .font(.caption)
                        .lineLimit(2)
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 12)
            .padding(.top, 4)
        }
    }

    private var stopButton: some View {
        Button {
            stop()
        } label: {
            Label("Stop", systemImage: "stop.fill")
                .labelStyle(.iconOnly)
                .padding(8)
                .background(.red, in: Circle())
                .foregroundStyle(.white)
        }
    }

    private var spotsFeedSheet: some View {
        NavigationStack {
            spotsFeedContent
                .navigationTitle("Spots")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        connectivityIndicator
                    }
                }
        }
    }

    @ViewBuilder
    private var spotsFeedContent: some View {
        if session.spots.isEmpty {
            VStack(spacing: 12) {
                ProgressView()
                Text("Waiting for spots…")
                    .foregroundStyle(.secondary)
                Text("RBN spots within seconds of TX. PSK Reporter polls every 5 min.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(session.spots.reversed(), id: \.self) { spot in
                    spotRow(spot)
                }
            }
            .listStyle(.plain)
        }
    }

    private var connectivityIndicator: some View {
        HStack(spacing: 6) {
            sourceDot(label: "RBN", connected: session.rbnConnected)
            sourceDot(label: "PSKR", connected: session.pskrConnected)
        }
        .font(.caption2)
    }

    @ViewBuilder
    private func spotPin(for pin: PinAnnotation) -> some View {
        let opacity = pin.opacity(now: Date())
        Circle()
            .fill(BandColors.color(for: pin.band).opacity(opacity))
            .frame(width: pin.size, height: pin.size)
            .overlay(
                Circle()
                    .stroke(.white, lineWidth: 1.2)
                    .opacity(opacity * 0.9)
            )
            .shadow(radius: 1.5)
            .accessibilityLabel("\(pin.skimmerCall), \(pin.band), SNR \(Int(pin.snrDB ?? 0))")
    }

    private func metric(_ glyph: String, _ value: String) -> some View {
        VStack(spacing: 0) {
            Text(glyph)
                .font(.caption)
            Text(value)
                .font(.subheadline.bold().monospacedDigit())
        }
    }

    private func spotRow(_ spot: PropagationSpotEntry) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(BandColors.color(for: spot.band ?? ""))
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(spot.skimmerCall)
                        .font(.body.monospaced())
                    Text(spot.band ?? "")
                        .font(.caption2.bold())
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(BandColors.color(for: spot.band ?? "").opacity(0.2), in: Capsule())
                }
                HStack(spacing: 8) {
                    Text(spot.mode)
                    if let snr = spot.snrDB {
                        Text("\(Int(snr)) dB")
                    }
                    Text(spot.source.displayName)
                        .foregroundStyle(.tertiary)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Text(relativeTime(spot.timestamp))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private func sourceDot(label: String, connected: Bool) -> some View {
        HStack(spacing: 3) {
            Circle()
                .fill(connected ? Color.green : Color.red)
                .frame(width: 6, height: 6)
            Text(label)
        }
    }

    // MARK: - Helpers

    private func elapsedSeconds() -> TimeInterval {
        guard let start = session.config?.startedAt else {
            return 0
        }
        return Date().timeIntervalSince(start)
    }

    private func checkDurationCap() {
        guard let cap = session.config?.durationCap else {
            return
        }
        if elapsed >= cap, session.isRunning {
            stop(reason: .duration)
        }
    }

    private func stop(reason: PropagationStopReason = .user) {
        let snapshot = session.stop(reason: reason)
        onStop(snapshot)
    }

    private func formatElapsed(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", mins, secs)
    }

    private func relativeTime(_ date: Date) -> String {
        let delta = max(0, Date().timeIntervalSince(date))
        if delta < 60 {
            return "\(Int(delta))s"
        }
        if delta < 3_600 {
            return "\(Int(delta / 60))m"
        }
        return "\(Int(delta / 3_600))h"
    }
}

// MARK: - PinAnnotation

private struct PinAnnotation: Identifiable {
    let id: String
    let coordinate: CLLocationCoordinate2D
    let band: String
    let snrDB: Double?
    let skimmerCall: String
    let timestamp: Date

    var label: String {
        skimmerCall
    }

    var size: CGFloat {
        guard let snr = snrDB else {
            return 8
        }
        // RBN SNR roughly 0–35; FT8 SNR -25 to +10. Normalize.
        let normalized = max(0, min(40, snr + 25)) / 40
        return 8 + CGFloat(normalized) * 16
    }

    static func from(_ entry: PropagationSpotEntry) -> PinAnnotation? {
        guard let grid = entry.skimmerGrid,
              let coord = MaidenheadConverter.coordinate(from: grid)
        else {
            return nil
        }
        return PinAnnotation(
            id: PropagationCheck.dedupKey(for: entry),
            coordinate: coord,
            band: entry.band ?? "",
            snrDB: entry.snrDB,
            skimmerCall: entry.skimmerCall,
            timestamp: entry.timestamp
        )
    }

    func opacity(now: Date) -> Double {
        let age = max(0, now.timeIntervalSince(timestamp))
        if age < 60 {
            return 1.0
        }
        return max(0.3, 1 - (age - 60) / 240) // fades to 30% over 4 min after the freshness window
    }
}
