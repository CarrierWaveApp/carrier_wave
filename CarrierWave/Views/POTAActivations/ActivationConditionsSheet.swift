// Activation Conditions Detail Sheet
//
// Shows full solar and weather conditions for a POTA activation
// using gauge cards matching Propagation Estimator style.

import SwiftUI

// MARK: - ActivationConditionsSheet

struct ActivationConditionsSheet: View {
    // MARK: Internal

    let metadata: ActivationMetadata

    var body: some View {
        // swiftlint:disable:next redundant_discardable_let
        let _ = useMetricUnits // Trigger re-render when unit preference changes
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if metadata.hasSolarData {
                        solarSection
                    }
                    if metadata.hasWeatherData {
                        weatherSection
                    }
                    timestampFooter
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Conditions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: Private

    @AppStorage("useMetricUnits") private var useMetricUnits = false

    @Environment(\.dismiss) private var dismiss

    // MARK: - Solar Section

    private var solarSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Solar Conditions")
                .font(.headline)
                .padding(.leading, 4)

            if let kIndex = metadata.solarKIndex {
                kIndexCard(kIndex)
            }
            if let sfi = metadata.solarFlux {
                sfiCard(sfi)
            }
            if let ssn = metadata.solarSunspots {
                sunspotsCard(ssn)
            }
        }
    }

    // MARK: - Weather Section

    private var weatherSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Weather")
                .font(.headline)
                .padding(.leading, 4)

            if let desc = metadata.weatherDescription {
                weatherBanner(desc)
            }
            if let temp = metadata.weatherTemperatureF {
                temperatureCard(temp)
            }
            if let wind = metadata.weatherWindSpeed {
                windCard(wind)
            }
            if let humidity = metadata.weatherHumidity {
                humidityCard(humidity)
            }
        }
    }

    // MARK: - Footer

    private var timestampFooter: some View {
        Group {
            if let ts = metadata.solarTimestamp ?? metadata.weatherTimestamp {
                Text("Recorded: \(ts.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 4)
            }
        }
    }

    // MARK: - Solar Cards

    private func kIndexCard(_ kIndex: Double) -> some View {
        ConditionGaugeCard(
            icon: "waveform",
            title: "K-Index",
            value: String(format: "%.1f", kIndex),
            rating: Self.kIndexRating(kIndex),
            segmentColors: Self.kIndexColors,
            activeSegment: min(Int(kIndex), 9),
            scaleLabels: ["0", "Quiet", "Storm", "9"]
        )
    }

    private func sfiCard(_ sfi: Double) -> some View {
        ConditionGaugeCard(
            icon: "sun.max.fill",
            title: "Solar Flux (SFI)",
            value: "\(Int(sfi))",
            rating: Self.sfiRating(sfi),
            segmentColors: Self.sfiColors,
            activeSegment: Self.segmentIndex(
                value: sfi, boundaries: Self.sfiBoundaries
            ),
            scaleLabels: ["0", "Poor", "Good", "300"]
        )
    }

    private func sunspotsCard(_ ssn: Int) -> some View {
        ConditionGaugeCard(
            icon: "circle.dotted",
            title: "Sunspot Number",
            value: "\(ssn)",
            rating: Self.sunspotRating(ssn),
            segmentColors: Self.sunspotColors,
            activeSegment: Self.segmentIndex(
                value: Double(ssn), boundaries: Self.sunspotBoundaries
            ),
            scaleLabels: ["0", "Poor", "Ideal", "200+"]
        )
    }

    // MARK: - Weather Cards

    private func weatherBanner(_ description: String) -> some View {
        HStack(spacing: 12) {
            Self.weatherIcon(description)
                .font(.title)
            Text(description)
                .font(.headline)
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
        )
    }

    private func temperatureCard(_ temp: Double) -> some View {
        ConditionGaugeCard(
            icon: "thermometer.medium",
            title: "Temperature",
            value: UnitFormatter.temperature(temp),
            rating: Self.tempRating(temp),
            segmentColors: Self.tempColors,
            activeSegment: Self.segmentIndex(
                value: temp, boundaries: Self.tempBoundaries
            ),
            scaleLabels: Self.tempScaleLabels
        )
    }

    private func windCard(_ wind: Double) -> some View {
        let dir = metadata.weatherWindDirection ?? ""
        return ConditionGaugeCard(
            icon: "wind",
            title: "Wind Speed",
            value: UnitFormatter.windSpeed(wind, direction: dir.isEmpty ? nil : dir),
            rating: Self.windRating(wind),
            segmentColors: Self.windColors,
            activeSegment: Self.segmentIndex(
                value: wind, boundaries: Self.windBoundaries
            ),
            scaleLabels: Self.windScaleLabels
        )
    }

    private func humidityCard(_ humidity: Int) -> some View {
        ConditionGaugeCard(
            icon: "humidity",
            title: "Humidity",
            value: "\(humidity)%",
            rating: Self.humidityRating(humidity),
            segmentColors: Self.humidityColors,
            activeSegment: Self.segmentIndex(
                value: Double(humidity), boundaries: Self.humidityBoundaries
            ),
            scaleLabels: ["0%", "Dry", "Humid", "100%"]
        )
    }
}

// MARK: - Segment Data & Helpers

extension ActivationConditionsSheet {
    // MARK: - Segment Colors

    // K-Index: 10 segments (0-9), green→yellow→orange→red (lower is better)
    static let kIndexColors: [Color] = [
        .green, .green,
        .yellow, .yellow,
        .orange,
        Color(red: 1.0, green: 0.4, blue: 0.4),
        Color(red: 1.0, green: 0.2, blue: 0.2),
        Color(red: 0.8, green: 0.0, blue: 0.0),
        Color(red: 0.6, green: 0.0, blue: 0.0),
        Color(red: 0.4, green: 0.0, blue: 0.2),
    ]

    // SFI: 10 segments (0-300), red→green (higher is better)
    static let sfiColors: [Color] = [
        Color(red: 0.6, green: 0.0, blue: 0.0),
        Color(red: 1.0, green: 0.2, blue: 0.2),
        .orange, .yellow,
        Color(red: 0.7, green: 0.8, blue: 0.3),
        Color(red: 0.5, green: 0.8, blue: 0.3),
        .green,
        Color(red: 0.0, green: 0.7, blue: 0.3),
        Color(red: 0.0, green: 0.6, blue: 0.4),
        Color(red: 0.0, green: 0.5, blue: 0.5),
    ]

    // Sunspots: 10 segments (0-200+), red→green (higher is better)
    static let sunspotColors: [Color] = sfiColors

    // Temperature: 10 segments (0-110°F), blue→green→red (comfort curve)
    static let tempColors: [Color] = [
        Color(red: 0.2, green: 0.0, blue: 0.6),
        Color(red: 0.3, green: 0.2, blue: 0.8),
        .blue, .cyan, .teal, .green, .yellow, .orange,
        Color(red: 1.0, green: 0.2, blue: 0.2),
        Color(red: 0.8, green: 0.0, blue: 0.0),
    ]

    static var tempScaleLabels: [String] {
        if UnitFormatter.useMetric {
            return ["-18\u{00B0}C", "Cold", "Hot", "43\u{00B0}C"]
        }
        return ["0\u{00B0}F", "Cold", "Hot", "110\u{00B0}F"]
    }

    // Wind: 8 segments (0-40+ mph), green→red (calmer is better)
    static let windColors: [Color] = [
        .green, .green,
        Color(red: 0.5, green: 0.8, blue: 0.3),
        .yellow, .orange,
        Color(red: 1.0, green: 0.4, blue: 0.4),
        Color(red: 1.0, green: 0.2, blue: 0.2),
        Color(red: 0.8, green: 0.0, blue: 0.0),
    ]

    static var windScaleLabels: [String] {
        if UnitFormatter.useMetric {
            return ["0", "Calm", "Strong", "80+"]
        }
        return ["0", "Calm", "Strong", "50+"]
    }

    // Humidity: 10 segments (0-100%), orange→green→red (mid-range is best)
    static let humidityColors: [Color] = [
        .orange, .yellow,
        Color(red: 0.7, green: 0.8, blue: 0.3),
        .green, .green,
        Color(red: 0.5, green: 0.8, blue: 0.3),
        .yellow, .orange,
        Color(red: 1.0, green: 0.2, blue: 0.2),
        Color(red: 0.8, green: 0.0, blue: 0.0),
    ]

    // MARK: - Segment Boundaries

    static let sfiBoundaries: [Double] = [36, 71, 81, 91, 101, 121, 151, 201, 251]
    static let sunspotBoundaries: [Double] = [26, 51, 76, 101, 126, 151, 176, 201, 251]
    static let tempBoundaries: [Double] = [11, 21, 33, 46, 56, 71, 81, 91, 101]
    static let windBoundaries: [Double] = [6, 11, 16, 21, 26, 31, 36]
    static let humidityBoundaries: [Double] = [11, 21, 31, 41, 51, 61, 71, 81, 91]

    /// Map a value to a segment index using boundary thresholds.
    static func segmentIndex(value: Double, boundaries: [Double]) -> Int {
        for (i, boundary) in boundaries.enumerated() where value < boundary {
            return i
        }
        return boundaries.count
    }

    // MARK: - Rating Helpers

    static func kIndexRating(_ k: Double) -> String {
        switch k {
        case ..<2: "Quiet"
        case ..<4: "Unsettled"
        case ..<5: "Active"
        default: "Storm"
        }
    }

    static func sfiRating(_ sfi: Double) -> String {
        switch sfi {
        case ..<71: "Poor"
        case ..<101: "Fair"
        case ..<151: "Good"
        default: "Excellent"
        }
    }

    static func sunspotRating(_ ssn: Int) -> String {
        switch ssn {
        case ..<51: "Poor"
        case ..<101: "Fair"
        case ..<151: "Good"
        default: "Ideal"
        }
    }

    static func tempRating(_ temp: Double) -> String {
        switch temp {
        case ..<33: "Cold"
        case ..<56: "Cool"
        case ..<76: "Comfortable"
        case ..<91: "Warm"
        default: "Hot"
        }
    }

    static func windRating(_ wind: Double) -> String {
        switch wind {
        case ..<11: "Calm"
        case ..<21: "Moderate"
        case ..<31: "Strong"
        default: "Dangerous"
        }
    }

    static func humidityRating(_ humidity: Int) -> String {
        switch humidity {
        case ..<31: "Dry"
        case ..<61: "Comfortable"
        case ..<81: "Humid"
        default: "Oppressive"
        }
    }

    // MARK: - Weather Icon

    @ViewBuilder
    static func weatherIcon(_ description: String) -> some View {
        let desc = description.lowercased()

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
