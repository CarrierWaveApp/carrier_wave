import SwiftUI

// MARK: - SatellitePassListSheet

/// Upcoming passes of the selected satellite over the observer's QTH.
/// Each pass carries its full geometry (rise/set times and azimuths, peak
/// elevation, azimuth, and range), and the header surfaces the satellite
/// metadata we hold: polarization and amateur transmitters.
struct SatellitePassListSheet: View {
    // MARK: Internal

    let model: SatelliteTrackerModel
    let position: SatellitePosition
    let transmitters: [SatNOGSTransmitter]

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(position.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            workableOnly.toggle()
                        } label: {
                            Image(systemName: workableOnly
                                ? "line.3.horizontal.decrease.circle.fill"
                                : "line.3.horizontal.decrease.circle")
                        }
                        .accessibilityLabel(workableOnly
                            ? "Showing workable passes only — tap to show all"
                            : "Showing all passes — tap to show workable only")
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            favorites.toggle(position.noradID)
                        } label: {
                            Image(systemName: favorites.isFavorite(position.noradID)
                                ? "star.fill" : "star")
                                .foregroundStyle(favorites.isFavorite(position.noradID)
                                    ? .yellow : .secondary)
                        }
                        .accessibilityLabel(favorites.isFavorite(position.noradID)
                            ? "Remove from favorites" : "Add to favorites")
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") {
                            dismiss()
                        }
                    }
                }
        }
        .task {
            forecast = await model.passForecast(for: position.noradID)
            isLoading = false
        }
    }

    // MARK: Private

    private static let maxTransmitterRows = 3

    @Environment(\.dismiss) private var dismiss
    @State private var forecast = SatellitePassForecast.empty
    @State private var isLoading = true

    /// Same persisted workable-pass filter as every other pass list, plus
    /// the shared elevation threshold + horizon mask (the per-bird
    /// schedule is exactly where "deaf below 30° to the north" matters).
    @AppStorage(SatelliteWorkability.workablePassFilterKey) private var workableOnly = true
    @AppStorage(SatelliteModeFilter.minPeakElevationKey) private var minPeakElevation = 0
    @AppStorage(SatelliteModeFilter.horizonMaskKey) private var horizonMaskRaw = ""

    private var favorites: FavoriteSatellitesStore {
        .shared
    }

    private var visibleTransmitters: [SatNOGSTransmitter] {
        Array(transmitters.prefix(Self.maxTransmitterRows))
    }

    private var visiblePasses: [SatellitePass] {
        let mask = SatelliteModeFilter.horizonMask(from: horizonMaskRaw)
        return forecast.passes.filter { pass in
            pass.peakElevationDeg >= Double(minPeakElevation)
                && SatelliteModeFilter.horizonAllows(
                    peakAzimuthDeg: pass.peakAzimuthDeg,
                    peakElevationDeg: pass.peakElevationDeg,
                    mask: mask
                )
                && (!workableOnly
                    || pass.peakElevationDeg
                    >= SatelliteWorkability.minWorkablePassElevationDeg)
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView("Computing passes…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.observerCoordinate == nil {
            ContentUnavailableView(
                "QTH Not Set",
                systemImage: "location.slash",
                description: Text("Set your grid square or allow location access to predict passes.")
            )
        } else if forecast.isAlwaysVisible {
            ContentUnavailableView(
                "Always in View",
                systemImage: "eye",
                description: Text("\(position.name) stays above your horizon continuously — no discrete passes.")
            )
        } else if visiblePasses.isEmpty {
            ContentUnavailableView {
                Label("No Upcoming Passes", systemImage: "moon.zzz")
            } description: {
                Text(forecast.passes.isEmpty
                    ? "No passes rise above your horizon in the next 48 hours."
                    : "No workable passes (peak ≥ "
                    + "\(Int(SatelliteWorkability.minWorkablePassElevationDeg))°) in the next 48 hours.")
            } actions: {
                if !forecast.passes.isEmpty {
                    Button("Show All Passes") {
                        workableOnly = false
                    }
                }
            }
        } else {
            passList
        }
    }

    private var passList: some View {
        TimelineView(.periodic(from: .now, by: 30)) { timeline in
            let now = timeline.date.addingTimeInterval(model.timeOffset)
            List {
                Section {
                    ForEach(visiblePasses) { pass in
                        SatellitePassRow(pass: pass, now: now)
                    }
                } header: {
                    header
                } footer: {
                    Text("Next 48 hours · times are local · azimuths are true north"
                        + (workableOnly
                            ? " · peak ≥ \(Int(SatelliteWorkability.minWorkablePassElevationDeg))° only"
                            : ""))
                }
            }
        }
    }

    /// Satellite metadata we can enrich the list with: NORAD ID, curated
    /// downlink polarization, and its amateur transmitters.
    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let detail = position.detailName {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 6) {
                Text("NORAD \(String(position.noradID))")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                if let polarization = model.polarization(for: position.noradID) {
                    SatellitePolarizationBadge(polarization: polarization)
                }
            }
            ForEach(Array(visibleTransmitters.enumerated()), id: \.offset) { _, transmitter in
                transmitterLine(transmitter)
            }
            if transmitters.count > Self.maxTransmitterRows {
                Text("+ \(transmitters.count - Self.maxTransmitterRows) more transmitters")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .textCase(nil)
        .padding(.bottom, 4)
    }

    private func transmitterLine(_ transmitter: SatNOGSTransmitter) -> some View {
        HStack(spacing: 6) {
            TransmitterHeardDot(transmitter: transmitter)
            SatelliteModeBadge(mode: transmitter.mode)
            if let downlink = transmitter.downlinkLow {
                Text(String(format: "↓ %.3f", Double(downlink) / 1_000_000))
                    .font(.caption2.monospaced())
            }
            if let uplink = transmitter.uplinkLow {
                Text(String(format: "↑ %.3f", Double(uplink) / 1_000_000))
                    .font(.caption2.monospaced())
            }
            Text(transmitter.description)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if !transmitter.isActive {
                Text("inactive")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

// MARK: - SatellitePassRow

/// One pass: rise–set window with countdown and duration, peak elevation
/// and range, and the azimuth path across the sky.
struct SatellitePassRow: View {
    // MARK: Internal

    let pass: SatellitePass
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(timeRange)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                Spacer()
                if SatelliteWorkability.isMarginal(peakElevationDeg: pass.peakElevationDeg) {
                    MarginalPassTag()
                }
                Text(String(format: "%.0f° max", pass.peakElevationDeg))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(peakStyle)
            }
            HStack(spacing: 6) {
                if pass.isInProgress(at: now) {
                    Label("In progress", systemImage: "dot.radiowaves.left.and.right")
                        .foregroundStyle(.green)
                } else {
                    Text(countdown)
                }
                Text("·")
                Text(durationLabel)
                Spacer()
                Text(String(format: "%.0f km at peak", pass.peakRangeKm))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            Text(azimuthPath)
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    /// Shared 8-point compass + degrees label (also used by the antenna
    /// pointing screen).
    static func compassLabel(_ degrees: Double) -> String {
        let points = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let index = Int(((degrees + 22.5) / 45).rounded(.down)) % points.count
        return String(format: "%@ %.0f°", points[index], degrees)
    }

    // MARK: Private

    private var timeRange: String {
        let aos = pass.aos.formatted(.dateTime.weekday(.abbreviated).hour().minute())
        let los = pass.los.formatted(date: .omitted, time: .shortened)
        return "\(aos) – \(los)"
    }

    private var countdown: String {
        let interval = pass.aos.timeIntervalSince(now)
        guard interval > 0 else {
            return "now"
        }
        let minutes = Int(interval / 60)
        if minutes < 60 {
            return "in \(max(minutes, 1))m"
        }
        return "in \(minutes / 60)h \(String(format: "%02d", minutes % 60))m"
    }

    private var durationLabel: String {
        "\(max(Int((pass.duration / 60).rounded()), 1)) min"
    }

    private var azimuthPath: String {
        let rise = Self.compassLabel(pass.aosAzimuthDeg)
        let peak = Self.compassLabel(pass.peakAzimuthDeg)
        let set = Self.compassLabel(pass.losAzimuthDeg)
        return "\(rise) → peak \(peak) → \(set)"
    }

    /// Color-grade the peak elevation: workable, marginal, or scraping the
    /// horizon.
    private var peakStyle: Color {
        if pass.peakElevationDeg >= 45 {
            return .green
        }
        if pass.peakElevationDeg >= SatelliteWorkability.recommendedPassElevationDeg {
            return .primary
        }
        return .secondary
    }
}

// MARK: - MarginalPassTag

/// "marginal" capsule for 10–20° passes — above the 10° floor but below the
/// ≥20° handheld recommendation. Shared by the pass list, the all-sky
/// schedule, and the mutual planner.
struct MarginalPassTag: View {
    var body: some View {
        Text("marginal")
            .font(.caption2.weight(.medium))
            // Chips never wrap — a squeezed row truncates its texts instead.
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(.orange)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.orange.opacity(0.12))
            .clipShape(Capsule())
    }
}
