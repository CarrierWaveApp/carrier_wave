// swiftlint:disable function_body_length
// Solar Panel View for Logger
//
// Displays current solar conditions including K-index,
// solar flux, and propagation forecast.

import SwiftUI

// MARK: - BandCondition

/// Parsed HF band condition for a band group (e.g. "80m-40m").
private struct BandCondition: Identifiable {
    let name: String
    let day: String
    let night: String

    var id: String {
        name
    }
}

// MARK: - SolarPanelView

struct SolarPanelView: View {
    // MARK: Internal

    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if isLoading {
                loadingView
            } else if let error = errorMessage {
                errorView(error)
            } else if let conditions {
                conditionsView(conditions)
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.1), radius: 8, y: 2)
        .task {
            await loadData()
        }
    }

    // MARK: Private

    @State private var conditions: SolarConditions?
    @State private var isLoading = true
    @State private var errorMessage: String?

    private let noaaClient = NOAAClient()

    // MARK: - Header

    private var header: some View {
        HStack {
            Image(systemName: "sun.max.fill")
                .foregroundStyle(.orange)

            Text("Solar Conditions")
                .font(.headline)

            Spacer()

            Button {
                Task { await loadData() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 14))
            }
            .buttonStyle(.borderless)

            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
        }
        .padding()
    }

    // MARK: - Content Views

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading solar data...")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title2)
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Retry") {
                Task { await loadData() }
            }
            .font(.caption)
            .buttonStyle(.bordered)
        }
        .padding()
        .frame(maxWidth: .infinity, minHeight: 120)
    }

    private func conditionsView(_ conditions: SolarConditions) -> some View {
        VStack(spacing: 16) {
            // Propagation rating
            propagationBadge(conditions)

            // Metrics grid
            LazyVGrid(
                columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                ], spacing: 12
            ) {
                metricCard(
                    title: "K-Index",
                    value: String(format: "%.1f", conditions.kIndex),
                    icon: "gauge",
                    color: kIndexColor(conditions.kIndex)
                )

                if let flux = conditions.solarFlux {
                    metricCard(
                        title: "SFI",
                        value: "\(Int(flux))",
                        icon: "sun.max",
                        color: sfiColor(flux)
                    )
                } else {
                    metricCard(
                        title: "SFI",
                        value: "--",
                        icon: "sun.max",
                        color: .secondary
                    )
                }

                if let spots = conditions.sunspots {
                    metricCard(
                        title: "Sunspots",
                        value: "\(spots)",
                        icon: "circle.dotted",
                        color: .orange
                    )
                } else {
                    metricCard(
                        title: "A-Index",
                        value: conditions.aIndex.map { "\($0)" } ?? "--",
                        icon: "waveform.path",
                        color: .purple
                    )
                }
            }

            // Band conditions summary
            bandConditionsSummary(conditions)

            // Last updated
            Text("Updated: \(conditions.timestamp.formatted(date: .omitted, time: .shortened))")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding()
    }

    private func propagationBadge(_ conditions: SolarConditions) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(propagationColor(conditions.propagationRating))
                .frame(width: 12, height: 12)

            Text(conditions.propagationRating)
                .font(.title3)
                .fontWeight(.semibold)

            Text("Propagation")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(propagationColor(conditions.propagationRating).opacity(0.1))
        .clipShape(Capsule())
    }

    private func metricCard(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(color)

            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(color)

            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(color.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func bandConditionsSummary(_ conditions: SolarConditions) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("HF Band Conditions")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)

            if let parsed = parseBandConditions(conditions.bandConditions) {
                bandConditionsGrid(parsed)
            } else {
                Text("Band conditions unavailable")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    private func bandConditionsGrid(_ bands: [BandCondition]) -> some View {
        VStack(spacing: 4) {
            // Header row
            HStack(spacing: 0) {
                Text("")
                    .frame(width: 60, alignment: .leading)
                Text("Day")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                Text("Night")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }

            ForEach(bands) { band in
                HStack(spacing: 0) {
                    Text(band.name)
                        .font(.system(size: 10, weight: .medium))
                        .frame(width: 60, alignment: .leading)
                    bandRatingDot(band.day)
                        .frame(maxWidth: .infinity)
                    bandRatingDot(band.night)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func bandRatingDot(_ rating: String) -> some View {
        HStack(spacing: 3) {
            Circle()
                .fill(bandRatingColor(rating))
                .frame(width: 6, height: 6)
            Text(rating)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
    }

    private func bandRatingColor(_ rating: String) -> Color {
        switch rating {
        case "Excellent": .green
        case "Good": .blue
        case "Fair": .yellow
        case "Poor": .orange
        default: .red
        }
    }

    /// Parse band conditions JSON string into display-ready models.
    private func parseBandConditions(_ json: String?) -> [BandCondition]? {
        guard let json,
              let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: [String: String]]
        else {
            return nil
        }

        let order = ["80m-40m", "30m-20m", "17m-15m", "12m-10m"]
        var result: [BandCondition] = []
        for key in order {
            guard let times = dict[key] else {
                continue
            }
            result.append(BandCondition(
                name: key,
                day: times["day"] ?? "--",
                night: times["night"] ?? "--"
            ))
        }
        return result.isEmpty ? nil : result
    }

    // MARK: - Helpers

    private func propagationColor(_ rating: String) -> Color {
        switch rating {
        case "Excellent": .green
        case "Good": .blue
        case "Fair": .yellow
        case "Poor": .orange
        default: .red
        }
    }

    private func kIndexColor(_ kIndex: Double) -> Color {
        switch kIndex {
        case 0 ..< 2: .green
        case 2 ..< 3: .blue
        case 3 ..< 4: .yellow
        case 4 ..< 5: .orange
        default: .red
        }
    }

    private func sfiColor(_ sfi: Double) -> Color {
        switch sfi {
        case 150...: .green
        case 100...: .blue
        case 70...: .yellow
        default: .orange
        }
    }

    // MARK: - Data Loading

    private func loadData() async {
        isLoading = true
        errorMessage = nil

        do {
            conditions = try await noaaClient.fetchSolarConditions()
            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }
}

#Preview {
    SolarPanelView {}
        .padding()
}
