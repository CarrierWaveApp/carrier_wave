import SwiftUI

// MARK: - SolarIndexGaugeBar

/// Compact stoplight-style gauge bar for solar/geomagnetic indices.
/// Shows a segmented bar with the active segment highlighted,
/// adapted from the PropagationEstimator reference implementation.
struct SolarIndexGaugeBar: View {
    // MARK: Internal

    let label: String
    let value: String
    let description: String
    let segments: [Segment]
    let activeIndex: Int
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            headerRow
            gaugeBar
            scaleLabels
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) \(value), \(description)")
    }

    // MARK: Private

    @ScaledMetric(relativeTo: .caption) private var barHeight: CGFloat = 10

    private var activeColor: Color {
        let clamped = min(max(activeIndex, 0), segments.count - 1)
        return segments[clamped].color
    }

    private var headerRow: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(activeColor)
                .accessibilityHidden(true)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold))
            Text(description)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var gaugeBar: some View {
        GeometryReader { geometry in
            let segmentCount = segments.count
            let totalGaps = CGFloat(segmentCount - 1)
            let segmentWidth = (geometry.size.width - totalGaps) /
                CGFloat(segmentCount)

            ZStack(alignment: .leading) {
                // Background segments (dimmed)
                HStack(spacing: 1) {
                    ForEach(0 ..< segmentCount, id: \.self) { idx in
                        Rectangle()
                            .fill(segments[idx].color.opacity(0.25))
                    }
                }

                // Active segment (full color)
                let clamped = min(max(activeIndex, 0), segmentCount - 1)
                Rectangle()
                    .fill(segments[clamped].color)
                    .frame(width: segmentWidth)
                    .offset(x: CGFloat(clamped) * (segmentWidth + 1))
            }
            .clipShape(RoundedRectangle(cornerRadius: 3))
        }
        .frame(height: barHeight)
    }

    private var scaleLabels: some View {
        HStack {
            if let first = segments.first {
                Text(first.scaleLabel)
            }
            Spacer()
            if let last = segments.last {
                Text(last.scaleLabel)
            }
        }
        .font(.system(size: 8))
        .foregroundStyle(.tertiary)
    }
}

// MARK: SolarIndexGaugeBar.Segment

extension SolarIndexGaugeBar {
    struct Segment {
        let color: Color
        let scaleLabel: String
    }
}

// MARK: - BandQualityGaugeRow

/// Compact stoplight gauge for a single band's propagation quality.
/// 5-segment bar mapping to PropagationQuality: Closed/Poor/Fair/Good/Excellent.
struct BandQualityGaugeRow: View {
    // MARK: Internal

    let bandName: String
    let qualityIndex: Int
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Text(bandName)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .frame(width: 36, alignment: .trailing)

                gaugeBar
            }
            .padding(.vertical, 3)
            .padding(.horizontal, 6)
            .background(
                isSelected
                    ? Color.blue.opacity(0.1)
                    : Color.clear
            )
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "\(bandName), \(Self.qualityLabels[min(qualityIndex, 4)])"
        )
        .accessibilityHint("Tap for details")
    }

    // MARK: Private

    /// 3-segment stoplight: Poor (red), Fair (yellow), Good (green).
    /// Maps 5-level PropagationQuality into 3 segments:
    ///   closed/poor → 0, fair → 1, good/excellent → 2
    private static let segmentColors: [Color] = [
        Color(red: 1.0, green: 0.2, blue: 0.2),
        .yellow,
        .green,
    ]

    private static let qualityLabels = [
        "Closed", "Poor", "Fair", "Good", "Excellent",
    ]

    @ScaledMetric(relativeTo: .caption) private var barHeight: CGFloat = 8

    /// Map 5-level quality (0-4) to 3-segment index (0-2).
    private var segmentIndex: Int {
        switch qualityIndex {
        case 0,
             1: 0 // closed, poor → red
        case 2: 1 // fair → yellow
        default: 2 // good, excellent → green
        }
    }

    private var gaugeBar: some View {
        GeometryReader { geometry in
            let count = Self.segmentColors.count
            let totalGaps = CGFloat(count - 1)
            let segWidth = (geometry.size.width - totalGaps) / CGFloat(count)
            let active = segmentIndex

            ZStack(alignment: .leading) {
                HStack(spacing: 1) {
                    ForEach(0 ..< count, id: \.self) { idx in
                        Rectangle()
                            .fill(Self.segmentColors[idx].opacity(0.25))
                    }
                }

                Rectangle()
                    .fill(Self.segmentColors[active])
                    .frame(width: segWidth)
                    .offset(x: CGFloat(active) * (segWidth + 1))
            }
            .clipShape(RoundedRectangle(cornerRadius: 3))
        }
        .frame(height: barHeight)
    }
}

// MARK: - KIndexGaugeBar

/// K-index gauge: 0-9 scale, green (quiet) to red (severe storm).
/// Segments based on NOAA geomagnetic storm scale.
struct KIndexGaugeBar: View {
    // MARK: Internal

    let kIndex: Double

    var body: some View {
        SolarIndexGaugeBar(
            label: "K",
            value: "\(Int(kIndex))",
            description: kDescription,
            segments: Self.segments,
            activeIndex: min(Int(kIndex), Self.segments.count - 1),
            icon: "waveform"
        )
    }

    // MARK: Private

    private static let segments: [SolarIndexGaugeBar.Segment] = [
        .init(color: .green, scaleLabel: "0"),
        .init(color: .green, scaleLabel: ""),
        .init(color: .yellow, scaleLabel: ""),
        .init(color: .yellow, scaleLabel: ""),
        .init(color: .orange, scaleLabel: ""),
        .init(color: Color(red: 1.0, green: 0.4, blue: 0.4), scaleLabel: ""),
        .init(color: Color(red: 1.0, green: 0.2, blue: 0.2), scaleLabel: ""),
        .init(color: Color(red: 0.8, green: 0.0, blue: 0.0), scaleLabel: ""),
        .init(color: Color(red: 0.6, green: 0.0, blue: 0.0), scaleLabel: ""),
        .init(color: Color(red: 0.4, green: 0.0, blue: 0.2), scaleLabel: "9"),
    ]

    private var kDescription: String {
        switch kIndex {
        case ..<2: "Quiet"
        case ..<4: "Unsettled"
        case ..<5: "Active"
        case ..<6: "G1 Storm"
        case ..<7: "G2 Storm"
        case ..<8: "G3 Storm"
        case ..<9: "G4 Storm"
        default: "G5 Storm"
        }
    }
}

// MARK: - SFIGaugeBar

/// Solar Flux Index gauge: ~60-300 scale, red (poor) to green (excellent).
struct SFIGaugeBar: View {
    // MARK: Internal

    let sfi: Double

    var body: some View {
        SolarIndexGaugeBar(
            label: "SFI",
            value: "\(Int(sfi))",
            description: sfiDescription,
            segments: Self.segments,
            activeIndex: segmentIndex,
            icon: "sun.max.fill"
        )
    }

    // MARK: Private

    private static let ranges: [ClosedRange<Int>] = [
        0 ... 35, 36 ... 70, 71 ... 80, 81 ... 90, 91 ... 100,
        101 ... 120, 121 ... 150, 151 ... 200, 201 ... 250, 251 ... 300,
    ]

    private static let segments: [SolarIndexGaugeBar.Segment] = [
        .init(color: Color(red: 0.6, green: 0.0, blue: 0.0), scaleLabel: "0"),
        .init(color: Color(red: 1.0, green: 0.2, blue: 0.2), scaleLabel: ""),
        .init(color: .orange, scaleLabel: ""),
        .init(color: .yellow, scaleLabel: ""),
        .init(color: Color(red: 0.7, green: 0.8, blue: 0.3), scaleLabel: ""),
        .init(color: Color(red: 0.5, green: 0.8, blue: 0.3), scaleLabel: ""),
        .init(color: .green, scaleLabel: ""),
        .init(color: Color(red: 0.0, green: 0.7, blue: 0.3), scaleLabel: ""),
        .init(color: Color(red: 0.0, green: 0.6, blue: 0.4), scaleLabel: ""),
        .init(color: Color(red: 0.0, green: 0.5, blue: 0.5), scaleLabel: "300"),
    ]

    private var segmentIndex: Int {
        let val = Int(sfi)
        for (idx, range) in Self.ranges.enumerated() where range.contains(val) {
            return idx
        }
        return Self.segments.count - 1
    }

    private var sfiDescription: String {
        switch sfi {
        case ..<80: "Low"
        case ..<120: "Moderate"
        case ..<180: "High"
        default: "Very High"
        }
    }
}

// MARK: - AIndexGaugeBar

/// A-index gauge: 0-400 scale, green (quiet) to red (extreme storm).
struct AIndexGaugeBar: View {
    // MARK: Internal

    let aIndex: Int

    var body: some View {
        SolarIndexGaugeBar(
            label: "A",
            value: "\(aIndex)",
            description: aDescription,
            segments: Self.segments,
            activeIndex: segmentIndex,
            icon: "waveform.path.ecg"
        )
    }

    // MARK: Private

    private static let ranges: [ClosedRange<Int>] = [
        0 ... 7, 8 ... 15, 16 ... 20, 21 ... 30, 31 ... 40,
        41 ... 50, 51 ... 70, 71 ... 100, 101 ... 200, 201 ... 400,
    ]

    private static let segments: [SolarIndexGaugeBar.Segment] = [
        .init(color: .green, scaleLabel: "0"),
        .init(color: .green, scaleLabel: ""),
        .init(color: .yellow, scaleLabel: ""),
        .init(color: .yellow, scaleLabel: ""),
        .init(color: .orange, scaleLabel: ""),
        .init(color: .orange, scaleLabel: ""),
        .init(color: Color(red: 1.0, green: 0.4, blue: 0.4), scaleLabel: ""),
        .init(color: Color(red: 1.0, green: 0.2, blue: 0.2), scaleLabel: ""),
        .init(color: Color(red: 0.8, green: 0.0, blue: 0.0), scaleLabel: ""),
        .init(color: Color(red: 0.6, green: 0.0, blue: 0.2), scaleLabel: "100+"),
    ]

    private var segmentIndex: Int {
        for (idx, range) in Self.ranges.enumerated() where range.contains(aIndex) {
            return idx
        }
        return Self.segments.count - 1
    }

    private var aDescription: String {
        switch aIndex {
        case ..<16: "Quiet"
        case ..<30: "Unsettled"
        case ..<50: "Active"
        case ..<100: "Minor Storm"
        case ..<200: "Major Storm"
        default: "Severe Storm"
        }
    }
}
