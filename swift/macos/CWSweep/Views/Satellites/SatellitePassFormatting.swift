import CoreGraphics
import Foundation

// MARK: - SatellitePassFormat

/// Pure formatting + projection helpers for the Satellites workspace. Kept
/// free of SwiftUI so they are unit-testable and so the Canvas renderers
/// stay allocation-light.
enum SatellitePassFormat {
    /// Typographic minus so negative shifts read like the rest of the panel.
    static let minusSign = "\u{2212}"

    static let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }()

    // MARK: Time

    /// "14:32:07 UTC"
    static func utcClock(_ date: Date) -> String {
        let parts = utcCalendar.dateComponents([.hour, .minute, .second], from: date)
        return String(format: "%02d:%02d:%02d UTC", parts.hour ?? 0, parts.minute ?? 0, parts.second ?? 0)
    }

    /// "14:32"
    static func utcHHmm(_ date: Date) -> String {
        let parts = utcCalendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    /// "m:ss" countdown (clamped at 0:00).
    static func countdown(_ seconds: TimeInterval) -> String {
        SweepPass.countdown(seconds)
    }

    /// "11 min" / "1 h 02 min"
    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded())
        if minutes >= 60 {
            return "\(minutes / 60) h \(String(format: "%02d", minutes % 60)) min"
        }
        return "\(minutes) min"
    }

    /// Sidebar / stats countdown for a pass: "LOS in 4:32" while active,
    /// "AOS in 12:05" before AOS, "Ended" after LOS.
    static func passCountdown(for pass: SweepPass?, at now: Date) -> String {
        guard let pass else {
            return "—"
        }
        if pass.isActive(at: now) {
            return "LOS in \(countdown(pass.secondsToLOS(at: now)))"
        }
        if pass.isUpcoming(at: now) {
            return "AOS in \(countdown(pass.aos.timeIntervalSince(now)))"
        }
        return "Ended"
    }

    /// Sidebar rows only show a countdown when it is imminent.
    static func sidebarCountdown(for pass: SweepPass, at now: Date, within window: TimeInterval = 3_600) -> String? {
        if pass.isActive(at: now) {
            return "LOS in \(countdown(pass.secondsToLOS(at: now)))"
        }
        let toAOS = pass.aos.timeIntervalSince(now)
        if toAOS > 0, toAOS < window {
            return "AOS in \(countdown(toAOS))"
        }
        return nil
    }

    // MARK: Frequency

    /// "437.8000 MHz"; "—" when nil.
    static func mhz(_ hertz: Double?) -> String {
        guard let hertz else {
            return "—"
        }
        return String(format: "%.4f MHz", hertz / 1_000_000)
    }

    /// Scale-tick flavour: "437.800"
    static func mhzTick(_ hertz: Double) -> String {
        String(format: "%.3f", hertz / 1_000_000)
    }

    /// Signed kHz shift: "−9.84 kHz" / "+9.84 kHz"; "—" when nil.
    static func shiftKHz(_ hertz: Double?) -> String {
        guard let hertz else {
            return "—"
        }
        return "\(signed(hertz / 1_000, decimals: 2)) kHz"
    }

    // MARK: Geometry / numbers

    /// "214.3°"
    static func degrees(_ value: Double?, decimals: Int = 1) -> String {
        guard let value else {
            return "—"
        }
        return String(format: "%.\(decimals)f°", value)
    }

    /// "1 234 km"
    static func kilometers(_ value: Double?) -> String {
        guard let value else {
            return "—"
        }
        return "\(groupedInteger(Int(value.rounded()))) km"
    }

    /// "+3.21 km/s" (positive = receding)
    static func kmPerSecond(_ value: Double?) -> String {
        guard let value else {
            return "—"
        }
        return "\(signed(value, decimals: 2)) km/s"
    }

    /// Fixed-decimal number with an explicit sign (typographic minus).
    static func signed(_ value: Double, decimals: Int) -> String {
        let magnitude = String(format: "%.\(decimals)f", abs(value))
        // Avoid "−0.00".
        let isZero = Double(magnitude) == 0
        if isZero || value > 0 {
            return "+\(magnitude)"
        }
        return "\(minusSign)\(magnitude)"
    }

    /// Thin-space thousands grouping ("1 234").
    static func groupedInteger(_ value: Int) -> String {
        let digits = String(abs(value))
        var grouped = ""
        for (index, character) in digits.enumerated() {
            if index > 0, (digits.count - index).isMultiple(of: 3) {
                grouped.append("\u{2009}")
            }
            grouped.append(character)
        }
        return value < 0 ? "\(minusSign)\(grouped)" : grouped
    }

    // MARK: Polar projection

    /// Unit-circle position for (az, el): radius (90−el)/90, azimuth
    /// clockwise from north (north = up). Elevation is clamped to 0…90.
    static func unitPolarPoint(azimuthDeg: Double, elevationDeg: Double) -> CGPoint {
        let radius = (90 - min(max(elevationDeg, 0), 90)) / 90
        let theta = azimuthDeg * .pi / 180
        return CGPoint(x: radius * sin(theta), y: -radius * cos(theta))
    }

    /// Screen position for (az, el) in a plot of `radius` around `center`.
    static func polarPoint(azimuthDeg: Double, elevationDeg: Double, center: CGPoint, radius: CGFloat) -> CGPoint {
        let unit = unitPolarPoint(azimuthDeg: azimuthDeg, elevationDeg: elevationDeg)
        return CGPoint(x: center.x + unit.x * radius, y: center.y + unit.y * radius)
    }

    /// Unit-space polyline for a sky track; apply a translate/scale
    /// transform at draw time so the path is built once per track change.
    static func unitTrackPath(_ track: [SkyTrackPoint]) -> CGPath {
        let path = CGMutablePath()
        for (index, point) in track.enumerated() {
            let unit = unitPolarPoint(azimuthDeg: point.azimuthDeg, elevationDeg: point.elevationDeg)
            if index == 0 {
                path.move(to: unit)
            } else {
                path.addLine(to: unit)
            }
        }
        return path
    }

    /// 0…1 position of `date` across a pass (nil when outside it).
    static func passFraction(of date: Date, in pass: SweepPass) -> Double? {
        guard pass.duration > 0, pass.isActive(at: date) else {
            return nil
        }
        return date.timeIntervalSince(pass.aos) / pass.duration
    }
}
