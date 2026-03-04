// Band Chart Data Model
//
// Precomputed chart data for visual band plan display,
// derived from BandPlan.segments and BandPlan.usageZones.

import CarrierWaveData
import Foundation

// MARK: - ClassAllocationBar

/// A per-license-class privilege bar within a band
struct ClassAllocationBar: Identifiable, Sendable {
    let id = UUID()
    let licenseClass: LicenseClass
    let startMHz: Double
    let endMHz: Double
    let modes: Set<String>
}

// MARK: - ModeZoneBar

/// A per-mode usage zone bar within a band
struct ModeZoneBar: Identifiable, Sendable {
    let id = UUID()
    let usage: UsageZone.Usage
    let startMHz: Double
    let endMHz: Double
}

// MARK: - BandChartData

/// Precomputed chart data for one band
struct BandChartData: Sendable {
    // MARK: Internal

    let band: String
    let bandStartMHz: Double
    let bandEndMHz: Double
    let isChannelized: Bool
    let classBars: [ClassAllocationBar]
    let modeZones: [ModeZoneBar]

    /// Channel frequencies for channelized bands (60m)
    let channelFrequencies: [Double]

    /// Unique frequency boundaries from all segments and usage zones
    let segmentEdges: [Double]

    /// Build chart data for a specific band
    static func build(for band: String) -> BandChartData {
        let segments = BandPlan.segments.filter { $0.band == band }
        let zones = BandPlan.usageZones.filter { $0.band == band }

        let isChannelized = band == "60m"

        let bandStart = segments.map(\.startMHz).min() ?? 0
        let bandEnd = segments.map(\.endMHz).max() ?? 0

        let classBars = buildClassBars(from: segments)
        let modeZones = zones.map { ModeZoneBar(usage: $0.usage, startMHz: $0.startMHz, endMHz: $0.endMHz) }

        let channels: [Double] = isChannelized
            ? segments.filter { $0.startMHz == $0.endMHz }.map(\.startMHz)
            : []

        // Collect unique segment edges for tick marks
        var edges: Set<Double> = [bandStart, bandEnd]
        for seg in segments {
            edges.insert(seg.startMHz)
            edges.insert(seg.endMHz)
        }
        for zone in zones {
            edges.insert(zone.startMHz)
            edges.insert(zone.endMHz)
        }

        return BandChartData(
            band: band,
            bandStartMHz: bandStart,
            bandEndMHz: bandEnd,
            isChannelized: isChannelized,
            classBars: classBars,
            modeZones: modeZones,
            channelFrequencies: channels,
            segmentEdges: edges.sorted()
        )
    }

    // MARK: Private

    /// Build merged bars for each license class.
    /// Extra sees all, General sees General+Tech, etc.
    /// Contiguous/overlapping segments are merged into single bars.
    private static func buildClassBars(from segments: [BandSegment]) -> [ClassAllocationBar] {
        let privilegeOrder: [LicenseClass] = [.technician, .general, .extra]
        var bars: [ClassAllocationBar] = []

        for licenseClass in LicenseClass.allCases {
            let classIdx = privilegeOrder.firstIndex(of: licenseClass) ?? 0
            let accessible = segments.filter { segment in
                let reqIdx = privilegeOrder.firstIndex(of: segment.minimumLicense) ?? 0
                return classIdx >= reqIdx
            }
            bars.append(contentsOf: mergeRanges(accessible, licenseClass: licenseClass))
        }

        return bars
    }

    /// Merge overlapping/contiguous frequency ranges into single bars
    private static func mergeRanges(
        _ segments: [BandSegment], licenseClass: LicenseClass
    ) -> [ClassAllocationBar] {
        var ranges: [(start: Double, end: Double)] = []
        var seen: Set<String> = []
        for seg in segments.sorted(by: { $0.startMHz < $1.startMHz }) {
            let key = "\(seg.startMHz)-\(seg.endMHz)"
            guard !seen.contains(key) else {
                continue
            }
            seen.insert(key)
            ranges.append((seg.startMHz, seg.endMHz))
        }

        guard !ranges.isEmpty else {
            return []
        }

        var merged: [(start: Double, end: Double)] = [ranges[0]]
        for range in ranges.dropFirst() {
            if range.start <= merged[merged.count - 1].end {
                merged[merged.count - 1].end = max(merged[merged.count - 1].end, range.end)
            } else {
                merged.append(range)
            }
        }

        return merged.map {
            ClassAllocationBar(
                licenseClass: licenseClass,
                startMHz: $0.start, endMHz: $0.end, modes: []
            )
        }
    }
}
