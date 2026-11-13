// Video Audio Mixer — Segment Writing
//
// Private helpers for segment-based audio writing (highlight reel mode).

import AVFoundation
import Foundation

// MARK: - Segment Reading

nonisolated extension VideoAudioMixer {
    static func makeSourceReader(
        asset: AVURLAsset,
        track: AVAssetTrack,
        sourceOffset: TimeInterval,
        duration: TimeInterval,
        sampleRate: Double
    ) -> AVAssetReader? {
        let startTime = CMTime(seconds: sourceOffset, preferredTimescale: 600)
        let endTime = CMTime(seconds: sourceOffset + duration, preferredTimescale: 600)

        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVSampleRateKey: sampleRate,
        ]

        guard let reader = try? AVAssetReader(asset: asset) else {
            return nil
        }
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
        reader.timeRange = CMTimeRange(start: startTime, end: endTime)
        reader.add(output)
        reader.startReading()
        return reader
    }

    /// Apply crossfade in-place to a CMSampleBuffer's PCM data.
    static func applyCrossfadeToBuffer(
        _ buffer: CMSampleBuffer,
        fadeInSamples: Int,
        fadeOutSamples: Int
    ) {
        guard fadeInSamples > 0 || fadeOutSamples > 0,
              let dataBuffer = CMSampleBufferGetDataBuffer(buffer)
        else {
            return
        }

        var length = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        CMBlockBufferGetDataPointer(
            dataBuffer,
            atOffset: 0,
            lengthAtOffsetOut: nil,
            totalLengthOut: &length,
            dataPointerOut: &dataPointer
        )
        guard let ptr = dataPointer else {
            return
        }

        let sampleCount = length / MemoryLayout<Int16>.size
        ptr.withMemoryRebound(to: Int16.self, capacity: sampleCount) { samples in
            applyCrossfade(
                to: samples, sampleCount: sampleCount,
                fadeInSamples: fadeInSamples, fadeOutSamples: fadeOutSamples
            )
        }
    }

    /// Create a copy of a sample buffer with a new presentation timestamp.
    static func retimeSampleBuffer(_ buffer: CMSampleBuffer, to time: CMTime) -> CMSampleBuffer? {
        var timing = CMSampleTimingInfo(
            duration: CMSampleBufferGetDuration(buffer),
            presentationTimeStamp: time,
            decodeTimeStamp: .invalid
        )
        var newBuffer: CMSampleBuffer?
        CMSampleBufferCreateCopyWithNewTiming(
            allocator: nil, sampleBuffer: buffer,
            sampleTimingEntryCount: 1, sampleTimingArray: &timing,
            sampleBufferOut: &newBuffer
        )
        return newBuffer
    }
}
