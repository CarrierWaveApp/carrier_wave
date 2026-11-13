import CarrierWaveCore
import CarrierWaveData
import SwiftUI

// MARK: - SatelliteInfoCard

/// Compact detail card for the selected satellite, including its amateur
/// transmitters (mode + up/downlink frequencies).
struct SatelliteInfoCard: View {
    // MARK: Internal

    let position: SatellitePosition
    let transmitters: [SatNOGSTransmitter]
    let look: SatelliteLook?
    let amsatStatus: AmsatSatelliteStatus?
    /// The bird's recent community reports (previous-orbit line).
    var reports: CommunityReports?
    /// This week's community activity grid and the bird's rows in it.
    var communityActivity: CommunityActivity?
    var communityRows: [CommunityActivityRow] = []
    /// Opens the community sheet on a capability row's hour-by-hour page.
    var onOpenCommunity: (String) -> Void = { _ in }
    /// Opens the AMSAT report sheet for this bird.
    var onReportCommunity: () -> Void = {}
    /// Curated downlink polarization from the engine's table, if known.
    let polarization: FfiSatPolarization?
    /// Fetches the bird's next pass (48 h window) for the summary line.
    let nextPassProvider: () async -> SatellitePass?
    let onShowPasses: () -> Void
    let onPoint: () -> Void
    let onLog: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            HStack(spacing: 12) {
                detail(label: "Alt", value: "\(Int(position.altitudeKm)) km")
                if let look {
                    detail(label: "Az", value: String(format: "%.0f°", look.azimuthDeg))
                    detail(label: "El", value: String(format: "%.0f°", look.elevationDeg))
                } else {
                    detail(label: "Lat", value: String(format: "%.2f°", position.latitude))
                    detail(label: "Lon", value: String(format: "%.2f°", position.longitude))
                }
                Spacer()
            }
            if let pass = nextPass, pass.los > Date() {
                nextPassLine(pass)
            }
            // Actions on their own row — sharing the stats row squeezed the
            // labels into mid-word wraps ("Pas ses") once Log joined.
            HStack(spacing: 16) {
                actionButton("Passes", icon: "calendar.badge.clock",
                             accessibility: "Show upcoming passes", action: onShowPasses)
                actionButton("Point", icon: "scope",
                             accessibility: "Antenna pointing mode", action: onPoint)
                actionButton("Log", icon: "square.and.pencil",
                             accessibility: "Log QSOs on this satellite", action: onLog)
                Spacer()
            }
            SatelliteCommunitySection(
                amsatStatus: amsatStatus,
                activity: communityActivity,
                rows: communityRows,
                reports: reports,
                onOpen: onOpenCommunity,
                onReport: onReportCommunity
            )
            if look?.isAboveHorizon == true {
                Label("Overhead now — tilt the phone up for the sky view", systemImage: "sparkles")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            // A caption, not a badge — the header chip row is already full.
            if rotatorService.isFollowing {
                Label(rotatorService.statusLine, systemImage: "dial.medium")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.orange)
                    .lineLimit(1)
            }
            if !visibleTransmitters.isEmpty {
                Divider()
                ForEach(Array(visibleTransmitters.enumerated()), id: \.offset) { _, transmitter in
                    transmitterRow(transmitter)
                }
                if hiddenTransmitterCount > 0 {
                    Text("+ \(hiddenTransmitterCount) more transmitters")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .task(id: position.noradID) {
            nextPass = nil
            nextPass = await nextPassProvider()
        }
    }

    // MARK: Private

    private static let maxTransmitterRows = 4

    @State private var nextPass: SatellitePass?

    private var favorites: FavoriteSatellitesStore {
        .shared
    }

    private var rotatorService: SatelliteRotatorService {
        .shared
    }

    private var visibleTransmitters: [SatNOGSTransmitter] {
        Array(transmitters.prefix(Self.maxTransmitterRows))
    }

    private var hiddenTransmitterCount: Int {
        max(0, transmitters.count - Self.maxTransmitterRows)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    CommunityDot(status: amsatStatus, size: 9)
                    Text(position.name)
                        .font(.headline.monospaced())
                        .lineLimit(1)
                }
                if let detail = position.detailName {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                HStack(spacing: 6) {
                    Text("NORAD \(String(position.noradID))")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    if let polarization {
                        SatellitePolarizationBadge(polarization: polarization)
                    }
                    if let amsatStatus {
                        AmsatStatusBadge(status: amsatStatus)
                    }
                }
            }
            Spacer()
            Button {
                favorites.toggle(position.noradID)
            } label: {
                Image(systemName: favorites.isFavorite(position.noradID) ? "star.fill" : "star")
                    .foregroundStyle(favorites.isFavorite(position.noradID) ? .yellow : .secondary)
            }
            .accessibilityLabel(
                favorites.isFavorite(position.noradID) ? "Remove from favorites" : "Add to favorites"
            )
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("Deselect satellite")
        }
    }

    /// "Next pass in 25m · peaks 34°" (or the in-progress countdown to
    /// LOS), with the peak graded like the pass lists.
    private func nextPassLine(_ pass: SatellitePass) -> some View {
        let now = Date()
        let peak = String(format: "peaks %.0f°", pass.peakElevationDeg)
        let timing = if pass.isInProgress(at: now) {
            "Up now · sets in \(Self.countdown(to: pass.los, from: now))"
        } else {
            "Next pass in \(Self.countdown(to: pass.aos, from: now))"
        }
        return HStack(spacing: 4) {
            Image(systemName: "clock")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("\(timing) ·")
                .foregroundStyle(.secondary)
            Text(peak)
                .foregroundStyle(peakStyle(pass.peakElevationDeg))
            if SatelliteWorkability.isMarginal(peakElevationDeg: pass.peakElevationDeg) {
                Text("· marginal")
                    .foregroundStyle(.orange)
            }
        }
        .font(.caption.monospacedDigit())
        .lineLimit(1)
    }

    private func transmitterRow(_ transmitter: SatNOGSTransmitter) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            TransmitterHeardDot(transmitter: transmitter)
            SatelliteModeBadge(mode: transmitter.mode)
            if let downlink = transmitter.downlinkLow {
                Text("↓ \(Self.formatMHz(downlink))")
                    .font(.caption.monospaced())
            }
            if let uplink = transmitter.uplinkLow {
                Text("↑ \(Self.formatMHz(uplink))")
                    .font(.caption.monospaced())
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

    private func actionButton(
        _ title: String,
        icon: String,
        accessibility: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.semibold))
                .fixedSize()
        }
        .accessibilityLabel(accessibility)
    }

    private func detail(label: String, value: String) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
                .monospacedDigit()
        }
        .font(.caption)
    }

    private static func countdown(to date: Date, from now: Date) -> String {
        let minutes = max(Int(date.timeIntervalSince(now) / 60), 0)
        if minutes < 1 {
            return "under a minute"
        }
        if minutes < 60 {
            return "\(minutes)m"
        }
        return "\(minutes / 60)h \(String(format: "%02d", minutes % 60))m"
    }

    private static func formatMHz(_ hertz: Int64) -> String {
        String(format: "%.3f", Double(hertz) / 1_000_000)
    }

    private func peakStyle(_ peakElevationDeg: Double) -> Color {
        if peakElevationDeg >= 45 {
            return .green
        }
        if peakElevationDeg >= SatelliteWorkability.recommendedPassElevationDeg {
            return .primary
        }
        return .secondary
    }
}

// MARK: - SatelliteModeBadge

/// Mode chip following the app's band/mode badge convention: capsule with
/// the canonical `ModeColors` tint at 0.2 opacity.
struct SatelliteModeBadge: View {
    let mode: String?

    var body: some View {
        Text(mode ?? "—")
            .font(.caption2.weight(.medium))
            // Chips never wrap — a squeezed row truncates its texts instead.
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(ModeColors.color(for: mode ?? "").opacity(0.2))
            .clipShape(Capsule())
    }
}

// MARK: - TransmitterHeardDot

/// Per-capability community signal on a transmitter row: green when the
/// AMSAT community heard this mode in the last 24 h, dim gray when AMSAT
/// tracks the capability but nobody reported it today, nothing when the
/// capability is untracked (benefit of the doubt — no signal either way).
struct TransmitterHeardDot: View {
    let transmitter: SatNOGSTransmitter

    var body: some View {
        if transmitter.amsatTracked {
            Circle()
                .fill(transmitter.amsatHeardToday ? Color.green : Color.secondary.opacity(0.45))
                .frame(width: 6, height: 6)
                .accessibilityLabel(
                    transmitter.amsatHeardToday
                        ? "Heard by the community today"
                        : "Not heard by the community today"
                )
        }
    }
}

// MARK: - AmsatStatusBadge

/// Community-status chip from the server's AMSAT aggregate: green when the
/// bird was heard in the last 24 h, dim "not heard" when reports exist but
/// none were positive. Nothing when there's no data.
struct AmsatStatusBadge: View {
    // MARK: Internal

    let status: AmsatSatelliteStatus

    var body: some View {
        if let heard = status.lastHeardAt, heard > Date(timeIntervalSinceNow: -24 * 3_600) {
            chip(text: "heard \(Self.ago(from: heard))", color: .green)
        } else if status.totalReports24h > 0 {
            chip(text: "not heard", color: .secondary)
        }
    }

    // MARK: Private

    private func chip(text: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Circle()
                .fill(color)
                .frame(width: 5, height: 5)
            Text(text)
        }
        .font(.caption2.weight(.medium))
        // Chips never wrap — a squeezed row truncates its texts instead.
        .lineLimit(1)
        .fixedSize()
        .foregroundStyle(.secondary)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
    }

    private static func ago(from date: Date) -> String {
        let minutes = max(Int(-date.timeIntervalSinceNow / 60), 0)
        if minutes < 60 {
            return "\(minutes)m"
        }
        return "\(minutes / 60)h"
    }
}

// MARK: - SatellitePolarizationBadge

/// Downlink polarization chip (curated table in the shared Rust engine).
struct SatellitePolarizationBadge: View {
    let polarization: FfiSatPolarization

    var body: some View {
        Text(polarization.label)
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.secondary.opacity(0.15))
            .clipShape(Capsule())
    }
}
