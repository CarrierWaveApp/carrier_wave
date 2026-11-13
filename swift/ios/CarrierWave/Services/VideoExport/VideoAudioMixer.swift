// Video Audio Mixer
//
// Reads WebSDR audio and produces sample buffers aligned to the video timeline.

import AVFoundation
import Foundation

// MARK: - AudioSegment

nonisolated enum AudioSegment {
    case source(sourceOffset: TimeInterval, duration: TimeInterval, videoTime: TimeInterval)
    case silence(duration: TimeInterval, videoTime: TimeInterval)
}

// MARK: - VideoAudioMixerError

nonisolated enum VideoAudioMixerError: Error {
    case noAudioTrack
    case readerFailed(String)
}

// MARK: - VideoAudioMixer

/// Nonisolated: called from VideoExportActor.
nonisolated enum VideoAudioMixer {
    // MARK: Internal

    // MARK: - Reader

    /// Creates an AVAssetReader for the source CAF file.
    /// Returns a tuple of (reader, sampleRate).
    static func makeReader(for url: URL) async throws -> (reader: AVAssetReader, sampleRate: Double) {
        let asset = AVURLAsset(url: url)
        guard let audioTrack = try await asset.loadTracks(withMediaType: .audio).first else {
            throw VideoAudioMixerError.noAudioTrack
        }

        let sampleRate = try await Double(audioTrack.load(.naturalTimeScale))

        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVSampleRateKey: sampleRate,
        ]

        let output = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: outputSettings)

        let reader: AVAssetReader
        do {
            reader = try AVAssetReader(asset: asset)
        } catch {
            throw VideoAudioMixerError.readerFailed(error.localizedDescription)
        }

        reader.add(output)
        return (reader, sampleRate)
    }

    /// Generates a silent CMSampleBuffer for the given duration.
    static func silenceBuffer(
        duration: TimeInterval,
        sampleRate: Double,
        presentationTime: CMTime
    ) -> CMSampleBuffer? {
        let sampleCount = Int(duration * sampleRate)
        guard sampleCount > 0 else {
            return nil
        }

        let byteCount = sampleCount * MemoryLayout<Int16>.size
        guard let block = makeZeroedBlockBuffer(byteCount: byteCount) else {
            return nil
        }
        guard let format = makeMonoPCMFormat(sampleRate: sampleRate) else {
            return nil
        }

        var sampleBuffer: CMSampleBuffer?
        let status = CMAudioSampleBufferCreateReadyWithPacketDescriptions(
            allocator: kCFAllocatorDefault,
            dataBuffer: block,
            formatDescription: format,
            sampleCount: sampleCount,
            presentationTimeStamp: presentationTime,
            packetDescriptions: nil,
            sampleBufferOut: &sampleBuffer
        )
        guard status == noErr else {
            return nil
        }
        return sampleBuffer
    }

    // MARK: - Crossfade

    /// Applies a linear fade-in and fade-out to a PCM Int16 buffer.
    static func applyCrossfade(
        to buffer: UnsafeMutablePointer<Int16>,
        sampleCount: Int,
        fadeInSamples: Int,
        fadeOutSamples: Int
    ) {
        for idx in 0 ..< min(fadeInSamples, sampleCount) {
            let scale = Float(idx) / Float(fadeInSamples)
            buffer[idx] = Int16(Float(buffer[idx]) * scale)
        }

        let fadeOutStart = sampleCount - fadeOutSamples
        for idx in max(0, fadeOutStart) ..< sampleCount {
            let remaining = sampleCount - idx
            let scale = Float(remaining) / Float(fadeOutSamples)
            buffer[idx] = Int16(Float(buffer[idx]) * scale)
        }
    }

    // MARK: - Segment Plan

    /// For highlight mode: computes which source time ranges to read and
    /// where to insert silence. Each moment gets source audio for the real-time
    /// gap to the next moment (capped at the uncompressed gap), with silence
    /// filling any remaining compressed-gap time.
    static func buildAudioSegmentPlan(
        timeline: VideoTimeline,
        recordingStart: Date
    ) -> [AudioSegment] {
        var segments: [AudioSegment] = []
        let moments = timeline.moments
        var cursor: TimeInterval = 0

        for (idx, moment) in moments.enumerated() {
            // Silence from cursor to this moment's video time (if gap exists)
            let preSilence = moment.videoTime - cursor
            if preSilence > 0.001 {
                segments.append(.silence(duration: preSilence, videoTime: cursor))
                cursor += preSilence
            }

            guard let sourceOffset = moment.audioSourceOffset else {
                continue
            }

            let realGapToNext = realGapToNextMoment(idx: idx, moments: moments)
            let videoGapToNext = videoGapToNextMoment(
                idx: idx, moments: moments, totalDuration: timeline.totalDuration
            )

            // Source audio: play the real audio for however long until the next moment
            // (or until the compressed gap begins, whichever is shorter)
            let sourceDuration = min(realGapToNext, videoGapToNext)
            if sourceDuration > 0 {
                segments.append(.source(
                    sourceOffset: sourceOffset, duration: sourceDuration, videoTime: cursor
                ))
                cursor += sourceDuration
            }

            // If the video gap is longer than source duration, fill remainder with silence
            let silenceRemainder = videoGapToNext - sourceDuration
            if silenceRemainder > 0.001 {
                segments.append(.silence(duration: silenceRemainder, videoTime: cursor))
                cursor += silenceRemainder
            }
        }

        // Trailing silence to fill to end of video
        let trailing = timeline.totalDuration - cursor
        if trailing > 0.001 {
            segments.append(.silence(duration: trailing, videoTime: cursor))
        }

        return segments
    }

    // MARK: Private

    private static func realGapToNextMoment(idx: Int, moments: [VideoMoment]) -> TimeInterval {
        guard idx + 1 < moments.count else {
            return 4.0 // trailing buffer
        }
        return moments[idx + 1].realTime.timeIntervalSince(moments[idx].realTime)
    }

    private static func videoGapToNextMoment(
        idx: Int, moments: [VideoMoment], totalDuration: TimeInterval
    ) -> TimeInterval {
        let nextVideoTime = idx + 1 < moments.count ? moments[idx + 1].videoTime : totalDuration
        return nextVideoTime - moments[idx].videoTime
    }

    // MARK: - Silence Buffer

    /// Creates a zeroed CMBlockBuffer with the given byte count.
    private static func makeZeroedBlockBuffer(byteCount: Int) -> CMBlockBuffer? {
        var blockBuffer: CMBlockBuffer?
        let status = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: byteCount,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: byteCount,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        guard status == kCMBlockBufferNoErr, let block = blockBuffer else {
            return nil
        }
        CMBlockBufferFillDataBytes(with: 0, blockBuffer: block, offsetIntoDestination: 0, dataLength: byteCount)
        return block
    }

    /// Creates a mono 16-bit PCM CMAudioFormatDescription at the given sample rate.
    private static func makeMonoPCMFormat(sampleRate: Double) -> CMAudioFormatDescription? {
        var asbd = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,
            mBytesPerPacket: 2,
            mFramesPerPacket: 1,
            mBytesPerFrame: 2,
            mChannelsPerFrame: 1,
            mBitsPerChannel: 16,
            mReserved: 0
        )
        var formatDescription: CMAudioFormatDescription?
        let status = CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: &asbd,
            layoutSize: 0,
            layout: nil,
            magicCookieSize: 0,
            magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &formatDescription
        )
        guard status == noErr else {
            return nil
        }
        return formatDescription
    }
}
