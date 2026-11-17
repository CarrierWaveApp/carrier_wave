import Foundation

// MARK: - WaterfallRGB

/// One color of the waterfall ramp, each component 0...1.
struct WaterfallRGB {
    let red: Double
    let green: Double
    let blue: Double
}

// MARK: - WaterfallView + Palette

extension WaterfallView {
    /// Magnitude (0...1) -> RGB, the waterfall's color ramp.
    static func waterfallRGB(for magnitude: Double) -> WaterfallRGB {
        let val = min(1.0, max(0.0, magnitude))
        if val < 0.05 {
            return WaterfallRGB(red: 0, green: 0, blue: 0.08)
        } else if val < 0.15 {
            let frac = (val - 0.05) / 0.1
            return WaterfallRGB(red: 0, green: 0, blue: 0.08 + frac * 0.25)
        } else if val < 0.35 {
            let frac = (val - 0.15) / 0.2
            return WaterfallRGB(red: 0, green: frac * 0.4, blue: 0.33 + frac * 0.3)
        } else if val < 0.55 {
            let frac = (val - 0.35) / 0.2
            return WaterfallRGB(red: 0, green: 0.4 + frac * 0.6, blue: 0.63 - frac * 0.3)
        } else if val < 0.75 {
            let frac = (val - 0.55) / 0.2
            return WaterfallRGB(red: frac * 0.8, green: 1.0, blue: 0.33 - frac * 0.33)
        } else if val < 0.9 {
            let frac = (val - 0.75) / 0.15
            return WaterfallRGB(red: 0.8 + frac * 0.2, green: 1.0 - frac * 0.5, blue: 0)
        } else {
            let frac = (val - 0.9) / 0.1
            return WaterfallRGB(red: 1.0, green: 0.5 - frac * 0.3, blue: frac * 0.5)
        }
    }

    /// 256-step lookup of the ramp as big-endian RGBX pixels.
    static let waterfallPalette: [UInt32] = (0 ... 255).map { step in
        let color = waterfallRGB(for: Double(step) / 255)
        let byte = { (component: Double) in UInt32((component * 255).rounded()) }
        return (byte(color.red) << 24 | byte(color.green) << 16 | byte(color.blue) << 8 | 0xFF).bigEndian
    }
}
