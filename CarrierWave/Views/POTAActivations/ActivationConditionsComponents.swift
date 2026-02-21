// Compact condition gauge components for activation and session rows
//
// SolarConditionGauge: 3-segment gauge bar (Poor/Fair/Good)
// WeatherConditionBadge: Weather icon + temperature badge
//
// These views accept any type conforming to ConditionsData,
// which both ActivationMetadata and LoggingSession conform to.

import SwiftUI

// MARK: - ConditionsData

/// Protocol for types that provide solar/weather condition data for display.
/// Both ActivationMetadata and LoggingSession conform to this.
protocol ConditionsData {
    var solarKIndex: Double? { get }
    var solarPropagationRating: String? { get }
    var solarFlux: Double? { get }
    var solarSunspots: Int? { get }
    var solarTimestamp: Date? { get }
    var weatherTemperatureF: Double? { get }
    var weatherTemperatureC: Double? { get }
    var weatherHumidity: Int? { get }
    var weatherWindSpeed: Double? { get }
    var weatherWindDirection: String? { get }
    var weatherDescription: String? { get }
    var weatherTimestamp: Date? { get }
    var hasSolarData: Bool { get }
    var hasWeatherData: Bool { get }
    // Text fallback fields
    var weather: String? { get }
    var solarConditions: String? { get }
}

// MARK: - ActivationMetadata + ConditionsData

extension ActivationMetadata: ConditionsData {}

// MARK: - LoggingSession + ConditionsData

extension LoggingSession: ConditionsData {}

// MARK: - SolarConditionGauge

private let solarGaugeSegmentColors: [Color] = [
    Color(red: 0.8, green: 0.0, blue: 0.0), // Poor - red
    .yellow, // Fair - yellow
    .green, // Good - green
]

// MARK: - SolarConditionGauge

/// Compact 3-segment gauge showing propagation quality.
/// Inspired by propagation_estimator's BandConditionGauge.
struct SolarConditionGauge<C: ConditionsData>: View {
    // MARK: Internal

    let metadata: C

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "sun.max.fill")
                .font(.system(size: 9))
                .foregroundStyle(.orange)

            gaugeBar
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Solar: \(metadata.solarPropagationRating ?? "Unknown") propagation")
    }

    // MARK: Private

    private var activeSegmentIndex: Int {
        switch metadata.solarPropagationRating {
        case "Excellent",
             "Good": 2
        case "Fair": 1
        default: 0 // Poor, Very Poor, nil
        }
    }

    private var gaugeBar: some View {
        HStack(spacing: 1) {
            ForEach(0 ..< 3, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(solarGaugeSegmentColors[index].opacity(index == activeSegmentIndex ? 1.0 : 0.3))
                    .frame(width: 8, height: 6)
            }
        }
    }
}

// MARK: - WeatherConditionBadge

/// Compact badge showing weather icon and temperature.
struct WeatherConditionBadge<C: ConditionsData>: View {
    // MARK: Internal

    let metadata: C

    var body: some View {
        let _ = useMetricUnits // Trigger re-render when unit preference changes
        HStack(spacing: 3) {
            weatherIcon
                .font(.system(size: 9))

            if let tempF = metadata.weatherTemperatureF {
                Text(UnitFormatter.temperatureCompact(tempF))
                    .font(.caption)
            }
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(Color.cyan.opacity(0.1))
        .cornerRadius(4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
    }

    // MARK: Private

    @AppStorage("useMetricUnits") private var useMetricUnits = false

    private var accessibilityDescription: String {
        var parts: [String] = []
        if let desc = metadata.weatherDescription {
            parts.append(desc)
        }
        if let tempF = metadata.weatherTemperatureF {
            parts.append(UnitFormatter.temperature(tempF))
        }
        return parts.isEmpty ? "Weather" : parts.joined(separator: ", ")
    }

    @ViewBuilder
    private var weatherIcon: some View {
        let desc = (metadata.weatherDescription ?? "").lowercased()

        if desc.contains("sunny") || desc.contains("clear") {
            Image(systemName: "sun.max.fill")
                .foregroundStyle(.yellow)
        } else if desc.contains("partly") && desc.contains("cloud") {
            Image(systemName: "cloud.sun.fill")
                .foregroundStyle(.cyan)
        } else if desc.contains("cloud") {
            Image(systemName: "cloud.fill")
                .foregroundStyle(.gray)
        } else if desc.contains("rain") || desc.contains("shower") {
            Image(systemName: "cloud.rain.fill")
                .foregroundStyle(.blue)
        } else if desc.contains("thunder") || desc.contains("storm") {
            Image(systemName: "cloud.bolt.fill")
                .foregroundStyle(.purple)
        } else if desc.contains("snow") {
            Image(systemName: "snowflake")
                .foregroundStyle(.cyan)
        } else if desc.contains("fog") || desc.contains("mist") {
            Image(systemName: "cloud.fog.fill")
                .foregroundStyle(.gray)
        } else if desc.contains("wind") {
            Image(systemName: "wind")
                .foregroundStyle(.teal)
        } else {
            Image(systemName: "cloud.fill")
                .foregroundStyle(.gray)
        }
    }
}

// MARK: - ConditionGaugeCard

/// Reusable gauge card matching Propagation Estimator style.
/// Shows icon + title, large value + rating, multi-segment gauge bar, and scale labels.
struct ConditionGaugeCard: View {
    // MARK: Internal

    let icon: String
    let title: String
    let value: String
    let rating: String
    let segmentColors: [Color]
    let activeSegment: Int
    let scaleLabels: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(activeColor)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.title)
                    .fontWeight(.bold)
                Text(rating)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            gaugeBar

            HStack {
                ForEach(scaleLabels.indices, id: \.self) { i in
                    if i > 0 {
                        Spacer()
                    }
                    Text(scaleLabels[i])
                }
            }
            .font(.system(size: 8))
            .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
        )
    }

    // MARK: Private

    private var activeColor: Color {
        let clamped = max(0, min(activeSegment, segmentColors.count - 1))
        return segmentColors[clamped]
    }

    private var gaugeBar: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                HStack(spacing: 1) {
                    ForEach(0 ..< segmentColors.count, id: \.self) { index in
                        Rectangle()
                            .fill(segmentColors[index].opacity(0.3))
                    }
                }

                let count = CGFloat(segmentColors.count)
                let segmentWidth = (geometry.size.width - (count - 1)) / count
                let clamped = max(0, min(activeSegment, segmentColors.count - 1))
                Rectangle()
                    .fill(segmentColors[clamped])
                    .frame(width: segmentWidth)
                    .offset(x: CGFloat(clamped) * (segmentWidth + 1))
            }
            .clipShape(RoundedRectangle(cornerRadius: 3))
        }
        .frame(height: 12)
    }
}

// MARK: - ConditionsGaugeRow

/// Wraps solar and weather gauges as tappable buttons that open a conditions sheet.
struct ConditionsGaugeRow<C: ConditionsData>: View {
    // MARK: Internal

    let metadata: C

    @Binding var showingSheet: Bool

    var body: some View {
        if metadata.hasSolarData || metadata.hasWeatherData {
            Button {
                showingSheet = true
            } label: {
                HStack(spacing: 4) {
                    if metadata.hasSolarData {
                        SolarConditionGauge(metadata: metadata)
                    }
                    if metadata.hasWeatherData {
                        WeatherConditionBadge(metadata: metadata)
                    }
                }
            }
            .buttonStyle(.plain)
        } else {
            // Fallback to text display for un-backfilled data
            textFallback
        }
    }

    // MARK: Private

    @ViewBuilder
    private var textFallback: some View {
        if let weather = metadata.weather, !weather.isEmpty {
            Label(weather, systemImage: "cloud")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        if let solar = metadata.solarConditions, !solar.isEmpty {
            Label(solar, systemImage: "sun.max")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}
