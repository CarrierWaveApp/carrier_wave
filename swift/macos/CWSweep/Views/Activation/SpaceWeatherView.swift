import CarrierWaveCore
import SwiftUI

// MARK: - SpaceWeatherView

/// Three cards showing DONKI space weather status: geomagnetic, solar flares, CME.
struct SpaceWeatherView: View {
    // MARK: Internal

    let events: [DONKIEvent]

    var body: some View {
        VStack(spacing: 6) {
            spaceWeatherCard(
                title: "Geomagnetic",
                systemImage: "bolt.fill",
                impactLevel: geoImpact,
                statusText: geoStatusText
            )
            spaceWeatherCard(
                title: "Solar Flares",
                systemImage: "sun.max.trianglebadge.exclamationmark",
                impactLevel: flareImpact,
                statusText: flareStatusText
            )
            spaceWeatherCard(
                title: "CME",
                systemImage: "wind",
                impactLevel: cmeImpact,
                statusText: cmeStatusText
            )
        }
    }

    // MARK: Private

    private var storms: [DONKIGeostorm] {
        events.compactMap { event -> DONKIGeostorm? in
            if case let .geostorm(storm) = event {
                return storm
            }
            return nil
        }
    }

    private var flares: [DONKIFlare] {
        events.compactMap { event -> DONKIFlare? in
            if case let .flare(flare) = event {
                return flare
            }
            return nil
        }
    }

    private var cmes: [DONKICME] {
        events.compactMap { event -> DONKICME? in
            if case let .cme(cme) = event {
                return cme
            }
            return nil
        }
    }

    private var geoImpact: RadioImpactLevel {
        storms
            .map { DONKIEvent.geostorm($0).radioImpact }
            .max() ?? .none
    }

    private var flareImpact: RadioImpactLevel {
        flares
            .map { DONKIEvent.flare($0).radioImpact }
            .max() ?? .none
    }

    private var cmeImpact: RadioImpactLevel {
        cmes
            .map { DONKIEvent.cme($0).radioImpact }
            .max() ?? .none
    }

    private var geoStatusText: String {
        guard let latest = storms.first else {
            return "No recent storms"
        }
        return "Kp \(String(format: "%.0f", latest.peakKp)) — \(geoImpact.label)"
    }

    private var flareStatusText: String {
        guard let latest = flares.first else {
            return "No recent flares"
        }
        return "\(latest.classType) — \(flareImpact.label)"
    }

    private var cmeStatusText: String {
        guard let latest = cmes.first else {
            return "No recent CMEs"
        }
        let speed = latest.cmeAnalyses?.compactMap(\.speed).max()
        if let speed {
            return "\(Int(speed)) km/s — \(cmeImpact.label)"
        }
        return "CME detected — \(cmeImpact.label)"
    }

    private func spaceWeatherCard(
        title: String,
        systemImage: String,
        impactLevel: RadioImpactLevel,
        statusText: String
    ) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(impactColor(impactLevel))
                .frame(width: 8, height: 8)

            Image(systemName: systemImage)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 14)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.primary)
                Text(statusText)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func impactColor(_ impact: RadioImpactLevel) -> Color {
        switch impact {
        case .none:
            .green
        case .minor:
            .yellow
        case .moderate:
            .orange
        case .severe:
            .red
        case .extreme:
            .purple
        }
    }
}
