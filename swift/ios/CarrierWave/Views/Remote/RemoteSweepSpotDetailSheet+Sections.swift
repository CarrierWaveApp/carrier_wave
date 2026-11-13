import CarrierWaveCore
import SwiftUI

// MARK: - Helpers + small types

//
// Source classification, the per-tile `Fact` model, badge helpers, and the
// number / age formatters. Split from the main file so the struct body
// stays under SwiftLint's `type_body_length` cap.

extension RemoteSweepSpotDetailSheet {
    struct Fact: Identifiable {
        let id = UUID()
        let icon: String
        let label: String
        let value: String
        let tint: Color
    }

    /// Source-themed accent. Restricted to the design-language palette:
    /// `.blue` / `.green` / `.orange` / `.purple` / `.yellow` (no teals,
    /// indigos, mints).
    var sourceColor: Color {
        if spot.needed {
            return .orange
        }
        switch spot.source.lowercased() {
        case "rbn": return .blue
        case "pota",
             "sota",
             "wwff": return .green
        case "cluster": return .yellow
        case "dxsummit",
             "dxheat",
             "dxwatch": return .orange
        default: return .blue
        }
    }

    var sourceIcon: String {
        switch spot.source.lowercased() {
        case "rbn": "dot.radiowaves.right"
        case "pota": "leaf.fill"
        case "sota": "mountain.2.fill"
        case "wwff": "leaf.fill"
        case "cluster": "globe"
        case "dxsummit",
             "dxheat",
             "dxwatch": "globe.americas.fill"
        default: "antenna.radiowaves.left.and.right"
        }
    }

    var heroSubtitle: String? {
        var parts: [String] = []
        if let entity = spot.dxccEntity {
            parts.append(entity)
        }
        if let region = spot.region, !parts.contains(region) {
            parts.append(region)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var factTiles: [Fact] {
        var output: [Fact] = []
        if let distance = spot.distanceMeters {
            output.append(Fact(
                icon: "ruler",
                label: "Distance",
                value: formatDistance(distance),
                tint: .blue
            ))
        }
        if let bearing = spot.bearingDegrees {
            output.append(Fact(
                icon: "location.north.line.fill",
                label: "Azimuth",
                value: formatBearing(bearing),
                tint: .blue
            ))
        }
        if let snr = spot.snr {
            output.append(Fact(
                icon: "waveform.path.ecg",
                label: "SNR",
                value: "\(snr) dB",
                tint: .green
            ))
        }
        if let spotter = spot.spotter {
            output.append(Fact(
                icon: "person.fill.viewfinder",
                label: "Spotter",
                value: spotter,
                tint: .blue
            ))
        }
        if let prefix = spot.dxccPrefix {
            output.append(Fact(
                icon: "globe",
                label: "Prefix",
                value: prefix,
                tint: .blue
            ))
        }
        if let region = spot.region {
            output.append(Fact(
                icon: "map",
                label: "Region",
                value: region,
                tint: .blue
            ))
        }
        if let mode = spot.mode {
            output.append(Fact(
                icon: "waveform",
                label: "Mode",
                value: mode,
                tint: .purple
            ))
        }
        if let band = spot.band {
            output.append(Fact(
                icon: "antenna.radiowaves.left.and.right",
                label: "Band",
                value: band,
                tint: .blue
            ))
        }
        return output
    }

    /// Distance in mi or km depending on user preference; falls back to mi.
    func formatDistance(_ meters: Double) -> String {
        let useMetric = Locale.current.measurementSystem == .metric
        if useMetric {
            let km = meters / 1_000
            return km >= 100 ? String(format: "%.0f km", km) : String(format: "%.1f km", km)
        }
        let miles = meters / 1_609.344
        return miles >= 100 ? String(format: "%.0f mi", miles) : String(format: "%.1f mi", miles)
    }

    func formatBearing(_ degrees: Double) -> String {
        let normalized = ((degrees.truncatingRemainder(dividingBy: 360)) + 360)
            .truncatingRemainder(dividingBy: 360)
        let cardinals = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let idx = Int((normalized + 22.5) / 45) % cardinals.count
        return String(format: "%.0f° %@", normalized, cardinals[idx])
    }

    func capsuleBadge(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tint.opacity(0.2))
            .clipShape(Capsule())
            .foregroundStyle(tint)
    }

    func formatFrequency(_ hz: UInt64) -> String {
        let mhz = Double(hz) / 1_000_000
        return String(format: "%.5f", mhz)
    }

    func ageString(for date: Date) -> String {
        let secs = Int(Date().timeIntervalSince(date))
        if secs < 60 {
            return "\(secs)s ago"
        }
        if secs < 3_600 {
            return "\(secs / 60)m ago"
        }
        return "\(secs / 3_600)h ago"
    }
}
