// Video Export Actor — Segment Audio
//
// Incremental segment-based audio writing for highlight reel mode.
// Opens one AVAssetReader per source segment, reusing it across frames.

import AVFoundation
import CoreMedia
import Foundation

// MARK: - Segment-Interleaved Audio

extension VideoExportActor {
    /// Incrementally writes audio from the segment plan, keeping timestamps close to video.
    /// Skips writes when audio is already ahead to prevent AVAssetWriter backpressure.
    func writeSegmentAudioInterleaved(
        writer: VideoWriter,
        audio: AudioState,
        upToVideoTime: Double,
        state: inout FrameLoopState
    ) async {
        guard let segments = audio.segmentPlan else {
            return
        }
        // Don't write more audio if we're already ahead of video
        let maxAhead = 0.1
        if state.audioTimeWritten > upToVideoTime + maxAhead {
            return
        }
        let target = upToVideoTime + (1.0 / VideoEventSequencer.framesPerSecond)

        while state.audioTimeWritten < target, state.segmentIndex < segments.count {
            let segment = segments[state.segmentIndex]
            switch segment {
            case let .silence(duration, videoTime):
                writeSilenceChunk(
                    writer: writer, audio: audio,
                    seg: SilenceSeg(videoTime: videoTime, duration: duration),
                    target: target, state: &state
                )
                return

            case let .source(sourceOffset, duration, videoTime):
                let seg = SourceSeg(
                    sourceOffset: sourceOffset, videoTime: videoTime, duration: duration
                )
                if await advanceOrReadSource(
                    writer: writer, audio: audio,
                    seg: seg, target: target, state: &state
                ) {
                    return
                }
            }
        }
    }

    struct SilenceSeg {
        let videoTime: TimeInterval
        let duration: TimeInterval
    }

    struct SourceSeg {
        let sourceOffset: TimeInterval
        let videoTime: TimeInterval
        let duration: TimeInterval
    }

    private func writeSilenceChunk(
        writer: VideoWriter, audio: AudioState,
        seg: SilenceSeg, target: Double, state: inout FrameLoopState
    ) {
        let segEnd = seg.videoTime + seg.duration
        if state.audioTimeWritten >= segEnd {
            state.segmentIndex += 1
            return
        }
        let writeStart = max(state.audioTimeWritten, seg.videoTime)
        let writeEnd = min(segEnd, target)
        let writeDur = writeEnd - writeStart
        if writeDur > 0.001 {
            let time = CMTime(seconds: writeStart, preferredTimescale: 600)
            if let buf = VideoAudioMixer.silenceBuffer(
                duration: writeDur, sampleRate: audio.sampleRate,
                presentationTime: time
            ) {
                _ = writer.appendAudioSamples(buf)
            }
            state.audioTimeWritten = writeEnd
        }
        if state.audioTimeWritten >= segEnd {
            state.segmentIndex += 1
        }
    }

    /// Returns true if this segment was handled (caller should return), false to continue loop.
    private func advanceOrReadSource(
        writer: VideoWriter, audio: AudioState,
        seg: SourceSeg, target: Double, state: inout FrameLoopState
    ) async -> Bool {
        let segEnd = seg.videoTime + seg.duration
        if state.audioTimeWritten >= segEnd {
            closeSegmentReader(state: &state)
            state.segmentIndex += 1
            return false
        }
        if state.segmentReader == nil {
            await openSegmentReader(
                audio: audio, sourceOffset: seg.sourceOffset,
                duration: seg.duration, state: &state
            )
        }
        readSegmentSamples(
            writer: writer, audio: audio, target: target,
            segEnd: segEnd, state: &state
        )
        if state.audioTimeWritten >= segEnd {
            closeSegmentReader(state: &state)
            state.segmentIndex += 1
        }
        return true
    }

    private func openSegmentReader(
        audio: AudioState, sourceOffset: TimeInterval,
        duration: TimeInterval, state: inout FrameLoopState
    ) async {
        let asset = AVURLAsset(url: audio.sourceURL)
        guard let track = try? await asset.loadTracks(withMediaType: .audio).first,
              let reader = VideoAudioMixer.makeSourceReader(
                  asset: asset, track: track,
                  sourceOffset: sourceOffset, duration: duration,
                  sampleRate: audio.sampleRate
              )
        else {
            return
        }
        state.segmentReader = reader
        state.segmentOutput = reader.outputs.first
    }

    private func closeSegmentReader(state: inout FrameLoopState) {
        state.segmentReader?.cancelReading()
        state.segmentReader = nil
        state.segmentOutput = nil
    }

    /// Reads audio samples up to target, splitting large buffers to avoid overshooting.
    private func readSegmentSamples(
        writer: VideoWriter, audio: AudioState, target: Double,
        segEnd: Double, state: inout FrameLoopState
    ) {
        let effectiveTarget = min(target, segEnd)

        while state.audioTimeWritten < effectiveTarget {
            // Try pending buffer first, then read new one
            let sample: CMSampleBuffer
            let sampleOffset: Int
            if let pending = state.pendingAudioBuffer {
                sample = pending
                sampleOffset = state.pendingAudioOffset
                state.pendingAudioBuffer = nil
                state.pendingAudioOffset = 0
            } else {
                guard let reader = state.segmentReader, reader.status == .reading,
                      let output = state.segmentOutput,
                      let newSample = output.copyNextSampleBuffer()
                else {
                    fillSilenceToTarget(
                        writer: writer, audio: audio,
                        target: effectiveTarget, state: &state
                    )
                    return
                }
                sample = newSample
                sampleOffset = 0
            }

            let totalSamples = CMSampleBufferGetNumSamples(sample) - sampleOffset
            let sampleRate = audio.sampleRate
            let remainingTime = effectiveTarget - state.audioTimeWritten
            let samplesNeeded = Int(remainingTime * sampleRate) + 1

            if samplesNeeded >= totalSamples {
                let chunk = AudioChunk(
                    buffer: sample, offset: sampleOffset,
                    count: totalSamples, sampleRate: sampleRate
                )
                writeAudioChunk(chunk, writer: writer, state: &state)
            } else {
                let chunk = AudioChunk(
                    buffer: sample, offset: sampleOffset,
                    count: samplesNeeded, sampleRate: sampleRate
                )
                writeAudioChunk(chunk, writer: writer, state: &state)
                state.pendingAudioBuffer = sample
                state.pendingAudioOffset = sampleOffset + samplesNeeded
            }
        }
    }

    struct AudioChunk {
        let buffer: CMSampleBuffer
        let offset: Int
        let count: Int
        let sampleRate: Double

        var isEmpty: Bool {
            count < 1
        }
    }

    private func writeAudioChunk(
        _ chunk: AudioChunk, writer: VideoWriter, state: inout FrameLoopState
    ) {
        guard !chunk.isEmpty else {
            return
        }
        let outTime = CMTime(seconds: state.audioTimeWritten, preferredTimescale: 600)
        let duration = Double(chunk.count) / chunk.sampleRate

        if chunk.offset == 0, chunk.count == CMSampleBufferGetNumSamples(chunk.buffer) {
            if let retimed = retimeSampleBuffer(chunk.buffer, to: outTime) {
                _ = writer.appendAudioSamples(retimed)
            }
        } else {
            if let sub = createSubBuffer(
                from: chunk.buffer, sampleOffset: chunk.offset, sampleCount: chunk.count,
                presentationTime: outTime, sampleRate: chunk.sampleRate
            ) {
                _ = writer.appendAudioSamples(sub)
            }
        }
        state.audioTimeWritten += duration
    }

    private func createSubBuffer(
        from buffer: CMSampleBuffer, sampleOffset: Int, sampleCount: Int,
        presentationTime: CMTime, sampleRate: Double
    ) -> CMSampleBuffer? {
        guard let dataBuffer = CMSampleBufferGetDataBuffer(buffer) else {
            return nil
        }

        let bytesPerSample = 2 // 16-bit PCM
        let byteOffset = sampleOffset * bytesPerSample
        let byteLength = sampleCount * bytesPerSample
        let totalLength = CMBlockBufferGetDataLength(dataBuffer)
        guard byteOffset + byteLength <= totalLength else {
            return nil
        }

        var subBlock: CMBlockBuffer?
        CMBlockBufferCreateWithBufferReference(
            allocator: kCFAllocatorDefault,
            referenceBuffer: dataBuffer,
            offsetToData: byteOffset,
            dataLength: byteLength,
            flags: 0,
            blockBufferOut: &subBlock
        )
        guard let block = subBlock else {
            return nil
        }

        guard let format = CMSampleBufferGetFormatDescription(buffer) else {
            return nil
        }
        var newBuffer: CMSampleBuffer?
        CMAudioSampleBufferCreateReadyWithPacketDescriptions(
            allocator: kCFAllocatorDefault,
            dataBuffer: block,
            formatDescription: format,
            sampleCount: sampleCount,
            presentationTimeStamp: presentationTime,
            packetDescriptions: nil,
            sampleBufferOut: &newBuffer
        )
        return newBuffer
    }

    private func fillSilenceToTarget(
        writer: VideoWriter, audio: AudioState,
        target: Double, state: inout FrameLoopState
    ) {
        let remaining = target - state.audioTimeWritten
        if remaining > 0.001 {
            let time = CMTime(seconds: state.audioTimeWritten, preferredTimescale: 600)
            if let buf = VideoAudioMixer.silenceBuffer(
                duration: remaining, sampleRate: audio.sampleRate,
                presentationTime: time
            ) {
                _ = writer.appendAudioSamples(buf)
            }
        }
        state.audioTimeWritten = target
    }
}
