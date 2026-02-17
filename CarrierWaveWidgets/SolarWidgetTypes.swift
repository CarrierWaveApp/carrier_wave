import AppIntents
import SwiftUI
import WidgetKit

// MARK: - SolarBand

enum SolarBand: String, CaseIterable, AppEnum {
    case band80m40m = "80m-40m"
    case band30m20m = "30m-20m"
    case band17m15m = "17m-15m"
    case band12m10m = "12m-10m"

    // MARK: Internal

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Band")

    static var caseDisplayRepresentations: [SolarBand: DisplayRepresentation] {
        [
            .band80m40m: "80m-40m",
            .band30m20m: "30m-20m",
            .band17m15m: "17m-15m",
            .band12m10m: "12m-10m",
        ]
    }
}

// MARK: - SolarWidgetIntent

struct SolarWidgetIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Solar Conditions"
    static let description: IntentDescription = "Solar conditions with band propagation."

    @Parameter(title: "Band", default: .band30m20m)
    var band: SolarBand
}

// MARK: - BandCondition

struct BandCondition: Sendable {
    let day: String
    let night: String
}

// MARK: - WidgetSegmentGauge

/// 10-segment horizontal gauge bar with per-metric color gradients
struct WidgetSegmentGauge: View {
    // MARK: Internal

    enum Metric {
        case kIndex(Double)
        case sfi(Double)
        case aIndex(Int)
    }

    let metric: Metric

    var body: some View {
        HStack(spacing: 1) {
            ForEach(0 ..< 10, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(colorForSegment(index))
                    .opacity(index == activeSegment ? 1.0 : 0.3)
            }
        }
        .frame(height: 6)
    }

    // MARK: Private

    private var activeSegment: Int {
        switch metric {
        case let .kIndex(k):
            min(max(Int(k), 0), 9)
        case let .sfi(sfi):
            segmentIndex(sfi, thresholds: [35, 70, 80, 90, 100, 120, 150, 200, 250, 300])
        case let .aIndex(aIdx):
            segmentIndex(Double(aIdx), thresholds: [7, 15, 20, 30, 40, 50, 70, 100, 200, 400])
        }
    }

    private func segmentIndex(_ value: Double, thresholds: [Double]) -> Int {
        for (index, threshold) in thresholds.enumerated() where value < threshold {
            return index
        }
        return 9
    }

    private func colorForSegment(_ index: Int) -> Color {
        switch metric {
        case .kIndex,
             .aIndex:
            // Green (segment 0) -> Red (segment 9)
            Color(hue: 0.333 * (1.0 - Double(index) / 9.0), saturation: 0.85, brightness: 0.85)
        case .sfi:
            // Red (segment 0) -> Green (segment 9)
            Color(hue: 0.333 * Double(index) / 9.0, saturation: 0.85, brightness: 0.85)
        }
    }
}

// MARK: - BandStoplightGauge

/// 3-segment stoplight gauge for band conditions (Good/Fair/Poor)
struct BandStoplightGauge: View {
    // MARK: Internal

    let condition: String

    var body: some View {
        HStack(spacing: 1) {
            ForEach(0 ..< 3, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(colors[index])
                    .opacity(index == activeIndex ? 1.0 : 0.3)
            }
        }
        .frame(height: 6)
    }

    // MARK: Private

    private var activeIndex: Int {
        switch condition.lowercased() {
        case "good",
             "excellent": 0
        case "fair": 1
        default: 2
        }
    }

    private var colors: [Color] {
        [
            Color(hue: 0.333, saturation: 0.85, brightness: 0.85),
            Color(hue: 0.167, saturation: 0.85, brightness: 0.85),
            Color(hue: 0.0, saturation: 0.85, brightness: 0.85),
        ]
    }
}
