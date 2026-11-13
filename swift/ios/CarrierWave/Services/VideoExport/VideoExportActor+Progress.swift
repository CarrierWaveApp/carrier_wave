// Video Export Actor — Progress
//
// Progress reporting helpers and thermal monitoring.

import CoreGraphics
import CoreVideo
import Foundation

extension VideoExportActor {
    // MARK: - Progress

    /// Create a progress update, optionally with a thumbnail.
    func makeProgress(
        framesCompleted: Int,
        totalFrames: Int,
        startTime: CFAbsoluteTime,
        thumbnail: CGImage? = nil
    ) -> VideoExportProgress {
        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        let rate = Double(framesCompleted) / max(elapsed, 0.001)
        let remaining = Double(totalFrames - framesCompleted) / max(rate, 0.001)

        return VideoExportProgress(
            framesCompleted: framesCompleted,
            totalFrames: totalFrames,
            estimatedSecondsRemaining: remaining,
            latestThumbnail: thumbnail
        )
    }

    // MARK: - Thumbnail

    /// Extract a CGImage thumbnail by copying pixel data out of the buffer.
    /// Does NOT retain the CVPixelBuffer — safe to call before buffer reuse.
    func thumbnailFromBuffer(_ buffer: CVPixelBuffer) -> CGImage? {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }

        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else {
            return nil
        }

        // Copy the pixel data so the CGImage owns it independently
        let dataSize = bytesPerRow * height
        guard let dataCopy = CFDataCreate(nil, baseAddress.assumingMemoryBound(to: UInt8.self), dataSize),
              let provider = CGDataProvider(data: dataCopy)
        else {
            return nil
        }

        return CGImage(
            width: width, height: height,
            bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue
                | CGBitmapInfo.byteOrder32Little.rawValue),
            provider: provider,
            decode: nil, shouldInterpolate: false,
            intent: .defaultIntent
        )
    }

    // MARK: - Thermal

    /// Check thermal state and yield if needed.
    /// Returns true if export should continue, false if cancelled during cooldown.
    func checkThermalState() async -> Bool {
        let state = ProcessInfo.processInfo.thermalState
        if state == .critical || state == .serious {
            while ProcessInfo.processInfo.thermalState == .critical
                || ProcessInfo.processInfo.thermalState == .serious
            {
                try? await Task.sleep(for: .seconds(2))
                if isCancelled {
                    return false
                }
            }
        }
        return !isCancelled
    }
}
