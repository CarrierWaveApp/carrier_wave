import Foundation

//
// Wire types for forwarding spectrum waterfall lines from CW Sweep to a
// paired iOS Remote client. The iOS side renders the lines exactly the
// same way Sweep does — a vertical scrolling band of color per FFT bin.
//
// Bandwidth budget: a 1024-bin line quantized to UInt8 is ~1.4 KB before
// JSON / base64 overhead, ~1.9 KB on the wire. At 10 fps that's 19 KB/s,
// well within a LAN's comfort zone. The publisher throttles to 10 fps
// regardless of the producer's native rate.

// MARK: - WaterfallLineEvent

/// One spectrum line published by Sweep to remote subscribers.
public struct WaterfallLineEvent: Codable, Sendable, Equatable {
    // MARK: Lifecycle

    public init(
        radioID: String,
        source: String,
        centerHz: UInt64,
        spanHz: UInt64,
        binCount: UInt16,
        bins: Data,
        sequence: UInt64,
        timestamp: Date
    ) {
        self.radioID = radioID
        self.source = source
        self.centerHz = centerHz
        self.spanHz = spanHz
        self.binCount = binCount
        self.bins = bins
        self.sequence = sequence
        self.timestamp = timestamp
    }

    // MARK: Public

    /// Identifies which radio produced the line. Mirrors `radioID` on
    /// `RadioStateEvent`.
    public let radioID: String
    /// Friendly source label (e.g. "SCU-LAN10", "SmartSDR") so iOS can show
    /// the producer in the panel header without a separate lookup.
    public let source: String
    /// Center frequency of the spectrum window in Hz.
    public let centerHz: UInt64
    /// Total span of the spectrum window in Hz.
    public let spanHz: UInt64
    /// Number of bins in this line.
    public let binCount: UInt16
    /// 8-bit quantized magnitudes (0=floor, 255=peak). Encoded as base64
    /// inside the JSON envelope.
    public let bins: Data
    /// Monotonic sequence number from `WaterfallStore.lineSequence`. iOS
    /// uses it to drop frames that arrive out of order.
    public let sequence: UInt64
    /// Timestamp of the line as observed by Sweep.
    public let timestamp: Date

    // MARK: - Quantization

    /// Convert a normalized 0..1 line to 8-bit quantized bytes.
    public static func quantize(_ line: [Float]) -> Data {
        var output = Data(count: line.count)
        output.withUnsafeMutableBytes { dest in
            guard let base = dest.bindMemory(to: UInt8.self).baseAddress else {
                return
            }
            for idx in 0 ..< line.count {
                let clamped = max(0, min(1, line[idx]))
                base[idx] = UInt8(clamped * 255)
            }
        }
        return output
    }

    /// Convert quantized bytes back to a normalized 0..1 line.
    public static func dequantize(_ data: Data) -> [Float] {
        var line = [Float](repeating: 0, count: data.count)
        for idx in 0 ..< data.count {
            line[idx] = Float(data[idx]) / 255
        }
        return line
    }
}

// MARK: - WaterfallClearedEvent

/// Fired when the active producer changes (radio disconnects, swaps from
/// SCU-LAN10 to SmartSDR, etc.). iOS clears its accumulated buffer.
public struct WaterfallClearedEvent: Codable, Sendable, Equatable {
    // MARK: Lifecycle

    public init(radioID: String, timestamp: Date) {
        self.radioID = radioID
        self.timestamp = timestamp
    }

    // MARK: Public

    public let radioID: String
    public let timestamp: Date
}

// MARK: - SetWaterfallViewCommand

/// Client → server. Ask the waterfall producer to re-span its stream,
/// centered on the VFO. `spanHz == nil` restores the producer's full span.
/// Producers that mirror a fixed radio scope (classic Sweep) ack failure;
/// k3fall re-slices its full-resolution FFT server-side.
public struct SetWaterfallViewCommand: Codable, Sendable, Equatable {
    // MARK: Lifecycle

    public init(requestID: UUID = UUID(), spanHz: UInt64?) {
        self.requestID = requestID
        self.spanHz = spanHz
    }

    // MARK: Public

    public let requestID: UUID
    public let spanHz: UInt64?
}
