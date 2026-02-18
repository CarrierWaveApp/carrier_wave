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

    /// Shorter label for constrained widget display
    var displayLabel: String {
        switch self {
        case .band80m40m: "80-40m"
        case .band30m20m: "30-20m"
        case .band17m15m: "17-15m"
        case .band12m10m: "12-10m"
        }
    }
}

// MARK: - SolarMetric

enum SolarMetric: String, CaseIterable, AppEnum {
    case kIndex
    case aIndex
    case sfi

    // MARK: Internal

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Metric")

    static var caseDisplayRepresentations: [SolarMetric: DisplayRepresentation] {
        [
            .kIndex: "K-Index",
            .aIndex: "A-Index",
            .sfi: "SFI",
        ]
    }
}

// MARK: - SolarWidgetIntent

struct SolarWidgetIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Solar Conditions"
    static let description: IntentDescription = "Solar conditions with band propagation."

    @Parameter(title: "Band", default: .band30m20m)
    var band: SolarBand

    @Parameter(title: "Lock Screen Metric", default: .kIndex)
    var metric: SolarMetric
}

// MARK: - BandCondition

struct BandCondition: Sendable {
    let day: String
    let night: String
}

// MARK: - CircularMetricGauge

/// Circular arc gauge with value inside — more filled = better propagation.
/// Fills counterclockwise from the top.
struct CircularMetricGauge: View {
    // MARK: Internal

    let label: String
    let value: String
    let level: Int // 1-5, where 5 = best
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.15), lineWidth: 3.5)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(color, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .scaleEffect(x: -1, y: 1)
                Text(value)
                    .font(.system(.caption2, design: .rounded, weight: .bold))
                    .monospacedDigit()
            }
            .frame(width: 40, height: 40)

            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Private

    private var fraction: Double {
        Double(level) / 5.0
    }
}

// MARK: - PropagationLevel

/// Maps solar metric values to propagation quality (level 1-5 + color)
enum PropagationLevel {
    static func kIndex(_ k: Double) -> (level: Int, color: Color) {
        switch k {
        case ..<2: (5, .green)
        case ..<3: (4, .green)
        case ..<4: (3, .yellow)
        case ..<5: (2, .orange)
        default: (1, .red)
        }
    }

    static func aIndex(_ aIdx: Int) -> (level: Int, color: Color) {
        switch aIdx {
        case ..<7: (5, .green)
        case ..<15: (4, .green)
        case ..<30: (3, .yellow)
        case ..<50: (2, .orange)
        default: (1, .red)
        }
    }

    static func sfi(_ sfi: Double) -> (level: Int, color: Color) {
        switch sfi {
        case ..<70: (1, .red)
        case ..<90: (2, .orange)
        case ..<120: (3, .yellow)
        case ..<200: (4, .green)
        default: (5, .green)
        }
    }

    static func condition(_ cond: String) -> Color {
        switch cond.lowercased() {
        case "good",
             "excellent": .green
        case "fair": .yellow
        default: .red
        }
    }

    static func rating(_ rating: String) -> Color {
        switch rating {
        case "Excellent": .green
        case "Good": .green
        case "Fair": .yellow
        case "Poor": .orange
        default: .red
        }
    }
}
