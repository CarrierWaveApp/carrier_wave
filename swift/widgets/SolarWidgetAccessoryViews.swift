import SwiftUI
import WidgetKit

// MARK: - SolarWidgetAccessoryCircularView

struct SolarWidgetAccessoryCircularView: View {
    // MARK: Internal

    let solar: SolarData?
    let metric: SolarMetric

    var body: some View {
        if let solar {
            switch metric {
            case .kIndex:
                accessoryGauge(
                    label: "K",
                    value: min(solar.kIndex, 9), range: 0 ... 9,
                    displayValue: String(format: "%.0f", solar.kIndex)
                )
            case .aIndex:
                if let aIdx = solar.aIndex {
                    accessoryGauge(
                        label: "A",
                        value: min(Double(aIdx), 50), range: 0 ... 50,
                        displayValue: "\(aIdx)"
                    )
                } else {
                    noValueView(label: "A")
                }
            case .sfi:
                if let sfi = solar.solarFlux {
                    accessoryGauge(
                        label: "SFI",
                        value: min(sfi, 300), range: 0 ... 300,
                        displayValue: "\(Int(sfi))"
                    )
                } else {
                    noValueView(label: "SFI")
                }
            }
        } else {
            Image(systemName: "sun.max.fill")
                .font(.title3)
        }
    }

    // MARK: Private

    private func accessoryGauge(
        label: String, value: Double, range: ClosedRange<Double>,
        displayValue: String
    ) -> some View {
        Gauge(value: value, in: range) {
            Text(label)
        } currentValueLabel: {
            Text(displayValue)
                .font(.system(.title3, design: .rounded, weight: .heavy))
        }
        .gaugeStyle(.accessoryCircular)
    }

    private func noValueView(label: String) -> some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Text("--")
                    .font(.system(.title3, design: .rounded, weight: .heavy))
                Text(label)
                    .font(.caption2)
            }
        }
    }
}

// MARK: - SolarWidgetAccessoryRectangularView

struct SolarWidgetAccessoryRectangularView: View {
    // MARK: Internal

    let solar: SolarData?
    let spaceWeather: WidgetSpaceWeatherSnapshot?
    let band: SolarBand

    var body: some View {
        if let solar {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    accessoryGauge(
                        label: "K", value: min(solar.kIndex, 9), range: 0 ... 9,
                        displayValue: String(format: "%.0f", solar.kIndex)
                    )
                    if let aIdx = solar.aIndex {
                        accessoryGauge(
                            label: "A", value: min(Double(aIdx), 50), range: 0 ... 50,
                            displayValue: "\(aIdx)"
                        )
                    }
                    if let sfi = solar.solarFlux {
                        accessoryGauge(
                            label: "SFI", value: min(sfi, 300), range: 0 ... 300,
                            displayValue: "\(Int(sfi))"
                        )
                    }
                }
                if let spaceWeather {
                    Text(spaceWeather.headline)
                        .font(.caption2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
        } else {
            Text("Solar: --")
                .font(.caption.weight(.semibold))
        }
    }

    // MARK: Private

    private func accessoryGauge(
        label: String, value: Double, range: ClosedRange<Double>, displayValue: String
    ) -> some View {
        Gauge(value: value, in: range) {
            Text(label)
        } currentValueLabel: {
            Text(displayValue).font(.system(.caption, design: .rounded, weight: .heavy))
        }
        .gaugeStyle(.accessoryCircular)
    }
}

// MARK: - SolarWidgetAccessoryInlineView

struct SolarWidgetAccessoryInlineView: View {
    let solar: SolarData?
    let spaceWeather: WidgetSpaceWeatherSnapshot?
    let band: SolarBand

    var body: some View {
        if let solar {
            let k = String(format: "%.0f", solar.kIndex)
            if let weather = spaceWeather, weather.worstImpactRaw >= 2 {
                Text("\u{26A1} K \(k) \u{00B7} \(weather.headline)")
            } else if let cond = solar.bandConditions[band.rawValue] {
                Text("\u{2600} K \(k) \u{00B7} \(band.displayLabel) \(cond.day)")
            } else if let sfi = solar.solarFlux {
                Text("\u{2600} K \(k) \u{00B7} SFI \(Int(sfi))")
            } else {
                Text("\u{2600} K \(k) \u{00B7} \(solar.propagationRating)")
            }
        } else {
            Text("\u{2600} Solar: --")
        }
    }
}
