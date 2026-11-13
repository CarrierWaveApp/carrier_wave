import CarrierWaveCore
import UIKit

// MARK: - RemoteSweepCoordinator+Waterfall

//
// Live waterfall handling — receives `radio.waterfall` events from Sweep,
// accumulates them in the rolling buffer the iOS view renders, and gates
// the subscription on the view being on screen so we don't burn LAN
// bandwidth in the background.
//

extension RemoteSweepCoordinator {
    /// Maximum lines kept on iOS — same default as the macOS store.
    static var waterfallMaxLines: Int {
        200
    }

    func applyWaterfallLine(_ event: WaterfallLineEvent) {
        if event.sequence != 0, event.sequence <= waterfallLastSequence {
            return
        }
        waterfallLastSequence = event.sequence
        waterfallSourceLabel = event.source
        waterfallCenterMHz = Double(event.centerHz) / 1_000_000
        waterfallSpanKHz = Double(event.spanHz) / 1_000
        waterfallActiveBinCount = Int(event.binCount)
        let registered = RegisteredWaterfallLine(
            centerHz: Double(event.centerHz),
            spanHz: Double(event.spanHz),
            image: RegisteredWaterfallLine.renderImage(bins: event.bins)
        )
        waterfallLines.insert(registered, at: 0)
        if waterfallLines.count > Self.waterfallMaxLines {
            waterfallLines.removeLast(waterfallLines.count - Self.waterfallMaxLines)
        }
    }

    /// Ask the server to re-span its waterfall stream (k3fall only — classic
    /// Sweep mirrors a fixed radio scope). Failure is fine: the view keeps
    /// its client-side scaling as fallback.
    func requestWaterfallSpan(hz: UInt64?) async {
        guard let client, serverPlatform == "linux" else {
            return
        }
        _ = try? await client.setWaterfallView(spanHz: hz)
    }

    func applyWaterfallCleared(_: WaterfallClearedEvent) {
        waterfallLines.removeAll(keepingCapacity: true)
        waterfallActiveBinCount = 0
        waterfallSourceLabel = "None"
        waterfallLastSequence = 0
    }

    /// Called from the iOS waterfall view's `task` so we only pay the
    /// bandwidth cost while a user is actually looking.
    func subscribeWaterfall() async {
        guard let client, !waterfallSubscribed else {
            return
        }
        waterfallSubscribed = true
        await client.subscribe(.waterfall)
    }

    func unsubscribeWaterfall() async {
        guard let client, waterfallSubscribed else {
            return
        }
        waterfallSubscribed = false
        await client.unsubscribe(.waterfall)
        applyWaterfallCleared(.init(radioID: "", timestamp: Date()))
    }
}

// MARK: - RegisteredWaterfallLine

/// One waterfall line pinned to the frequencies it was captured at, with a
/// pre-rendered 1px-tall image so the canvas blits instead of filling one
/// rect per bin. Registration is what keeps history stable while tuning:
/// each line renders at its own center/span, so pans and server re-spans
/// slide smoothly instead of lurching.
struct RegisteredWaterfallLine: Identifiable {
    // MARK: Internal

    let id = UUID()
    let centerHz: Double
    let spanHz: Double
    let image: CGImage?

    static func renderImage(bins: Data) -> CGImage? {
        guard !bins.isEmpty else {
            return nil
        }
        var pixels = [UInt8](repeating: 0, count: bins.count * 4)
        for (idx, magnitude) in bins.enumerated() {
            let base = Int(magnitude) * 4
            pixels[idx * 4] = lut[base]
            pixels[idx * 4 + 1] = lut[base + 1]
            pixels[idx * 4 + 2] = lut[base + 2]
            pixels[idx * 4 + 3] = 255
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else {
            return nil
        }
        return CGImage(
            width: bins.count,
            height: 1,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bins.count * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }

    // MARK: Private

    /// Same ramp as `RemoteSweepWaterfallView.color(for:)`, baked to a LUT.
    private static let lut: [UInt8] = {
        var table = [UInt8](repeating: 0, count: 256 * 4)
        for idx in 0 ..< 256 {
            let val = Double(idx) / 255
            let rgb: [Double] = switch val {
            case ..<0.05: [0, 0, 0.08]
            case ..<0.15: [0, 0, 0.08 + (val - 0.05) / 0.1 * 0.25]
            case ..<0.35: [0, (val - 0.15) / 0.2 * 0.4, 0.33 + (val - 0.15) / 0.2 * 0.3]
            case ..<0.55: [0, 0.4 + (val - 0.35) / 0.2 * 0.6, 0.63 - (val - 0.35) / 0.2 * 0.3]
            case ..<0.75: [(val - 0.55) / 0.2 * 0.8, 1.0, 0.33 - (val - 0.55) / 0.2 * 0.33]
            case ..<0.9: [0.8 + (val - 0.75) / 0.15 * 0.2, 1.0 - (val - 0.75) / 0.15 * 0.5, 0]
            default: [1.0, 0.5 - (val - 0.9) / 0.1 * 0.3, (val - 0.9) / 0.1 * 0.5]
            }
            table[idx * 4] = UInt8(rgb[0] * 255)
            table[idx * 4 + 1] = UInt8(rgb[1] * 255)
            table[idx * 4 + 2] = UInt8(rgb[2] * 255)
            table[idx * 4 + 3] = 255
        }
        return table
    }()
}
