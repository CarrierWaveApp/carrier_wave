// Video Export Actor — Pipeline
//
// Frame loop: iterates timeline, renders frames, writes to video file.

import AVFoundation
import CoreGraphics
import CoreMedia
import Foundation
import MapKit

// MARK: - Pipeline

extension VideoExportActor {
    func runPipeline(
        timeline: VideoTimeline,
        config: VideoExportConfig,
        recording: VideoRecordingSnapshot?,
        continuation: AsyncStream<VideoExportProgress>.Continuation
    ) async -> VideoExportResult {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("video-export-\(UUID().uuidString).mp4")

        let setup = await setupPipeline(
            outputURL: outputURL,
            config: config,
            recording: recording
        )
        guard let setup else {
            return .failed("Failed to set up video pipeline")
        }

        // Set up audio reader if we have a recording and audio is enabled
        let audioState = await setupAudioState(config: config, recording: recording, timeline: timeline)

        let frameResult = await runFrameLoop(
            timeline: timeline,
            setup: setup,
            audioState: audioState,
            outputURL: outputURL,
            continuation: continuation
        )

        guard case .success = frameResult else {
            return frameResult
        }

        let success = await setup.writer.finish()
        if !success {
            await logWriterFailure(frameIndex: -1, desc: setup.writer.statusDescription)
        }
        return success ? .success(outputURL) :
            .failed("Video writer failed to finish: \(setup.writer.statusDescription)")
    }
}

// MARK: - Audio State

extension VideoExportActor {
    /// Tracks state for interleaved audio writing during the frame loop.
    struct AudioState {
        let reader: AVAssetReader
        let output: AVAssetReaderOutput
        let sampleRate: Double
        /// Offset in seconds from video start to recording start.
        /// Positive means recording starts after video start.
        let recordingOffsetSeconds: Double
        let recordingDurationSeconds: Double
        /// Pre-built segment plan for highlight mode (nil = use interleaved mode).
        let segmentPlan: [AudioSegment]?
        let sourceURL: URL
    }

    func setupAudioState(
        config: VideoExportConfig,
        recording: VideoRecordingSnapshot?,
        timeline: VideoTimeline
    ) async -> AudioState? {
        guard config.includeAudio,
              let rec = recording,
              let (reader, sampleRate) = try? await VideoAudioMixer.makeReader(for: rec.fileURL),
              let output = reader.outputs.first
        else {
            return nil
        }

        reader.startReading()

        let sessionStart = timeline.metadata.startedAt
        let recOffset = rec.startedAt.timeIntervalSince(sessionStart)

        // Build segment plan for highlight mode so audio aligns with compressed video time
        let segmentPlan: [AudioSegment]? = if config.mode == .highlightReel {
            VideoAudioMixer.buildAudioSegmentPlan(timeline: timeline, recordingStart: rec.startedAt)
        } else {
            nil
        }

        if let plan = segmentPlan {
            logSegmentPlan(plan, sampleRate: sampleRate, recDuration: rec.durationSeconds)
        }

        return AudioState(
            reader: reader,
            output: output,
            sampleRate: sampleRate,
            recordingOffsetSeconds: recOffset,
            recordingDurationSeconds: rec.durationSeconds,
            segmentPlan: segmentPlan,
            sourceURL: rec.fileURL
        )
    }
}

// MARK: - Pipeline Setup

extension VideoExportActor {
    struct PipelineSetup {
        let writer: VideoWriter
        let pool: CVPixelBufferPool
        let comp: VideoFrameCompositor
        let includeAudio: Bool
        let audioSampleRate: Double
        let startTime: CFAbsoluteTime
    }

    func setupPipeline(
        outputURL: URL,
        config: VideoExportConfig,
        recording: VideoRecordingSnapshot?
    ) async -> PipelineSetup? {
        var audioSampleRate: Double = 44_100
        let includeAudio = config.includeAudio && recording != nil
        if includeAudio, let rec = recording {
            if let (reader, rate) = try? await VideoAudioMixer.makeReader(for: rec.fileURL) {
                audioSampleRate = rate
                reader.cancelReading()
            }
        }

        guard let writer = try? VideoWriter(
            outputURL: outputURL,
            includeAudio: includeAudio,
            sampleRate: audioSampleRate
        ) else {
            return nil
        }

        guard let pool = writer.pixelBufferPool else {
            return nil
        }

        let comp = VideoFrameCompositor(config: config)
        compositor = comp

        return PipelineSetup(
            writer: writer,
            pool: pool,
            comp: comp,
            includeAudio: includeAudio,
            audioSampleRate: audioSampleRate,
            startTime: CFAbsoluteTimeGetCurrent()
        )
    }
}

// MARK: - Frame Loop

extension VideoExportActor {
    private func runFrameLoop(
        timeline: VideoTimeline,
        setup: PipelineSetup,
        audioState: AudioState?,
        outputURL: URL,
        continuation: AsyncStream<VideoExportProgress>.Continuation
    ) async -> VideoExportResult {
        var state = FrameLoopState()

        for frameIndex in 0 ..< timeline.totalFrames {
            if isCancelled {
                return cancelExport(writer: setup.writer, outputURL: outputURL)
            }

            let videoTime = Double(frameIndex) / VideoEventSequencer.framesPerSecond

            let writeResult = await writeFrame(
                frameIndex: frameIndex, videoTime: videoTime,
                timeline: timeline, setup: setup, state: &state
            )
            if let failure = writeResult {
                return failure
            }

            if let audio = audioState {
                await writeAudioUpTo(videoTime: videoTime, audio: audio, setup: setup, state: &state)
            }

            reportProgress(
                frameIndex: frameIndex, timeline: timeline,
                setup: setup, continuation: continuation
            )

            if frameIndex.isMultiple(of: 100), frameIndex > 0 {
                let comp = setup.comp
                let elapsed = CFAbsoluteTimeGetCurrent() - setup.startTime
                let fps = Double(frameIndex) / max(elapsed, 0.001)
                let line = "VE f=\(frameIndex) fps=\(String(format: "%.0f", fps)) " +
                    "base=\(String(format: "%.1f", comp.lastBaseMs))ms " +
                    "dyn=\(String(format: "%.1f", comp.lastDynMs))ms " +
                    "snap=\(String(format: "%.0f", comp.lastSnapshotMs))ms " +
                    "cache=\(comp.lastUsedCache ? "Y" : "N")"
                Task { @MainActor in SyncDebugLog.shared.log(line, level: .info) }
                let shouldContinue = await checkThermalState()
                if !shouldContinue {
                    return cancelExport(writer: setup.writer, outputURL: outputURL)
                }
            }
        }
        return .success(outputURL)
    }

    /// Writes audio up to the given video time using either segment plan or linear interleaving.
    private func writeAudioUpTo(
        videoTime: Double, audio: AudioState, setup: PipelineSetup, state: inout FrameLoopState
    ) async {
        if audio.segmentPlan != nil {
            await writeSegmentAudioInterleaved(
                writer: setup.writer, audio: audio,
                upToVideoTime: videoTime, state: &state
            )
        } else {
            state.audioTimeWritten = writeInterleavedAudio(
                writer: setup.writer, audio: audio,
                upToVideoTime: videoTime, audioTimeWritten: state.audioTimeWritten
            )
        }
    }

    private func cancelExport(writer: VideoWriter, outputURL: URL) -> VideoExportResult {
        writer.cancel()
        try? FileManager.default.removeItem(at: outputURL)
        return .cancelled
    }

    private func reportProgress(
        frameIndex: Int, timeline: VideoTimeline,
        setup: PipelineSetup, continuation: AsyncStream<VideoExportProgress>.Continuation
    ) {
        guard frameIndex.isMultiple(of: 100) else {
            return
        }
        let prog = makeProgress(
            framesCompleted: frameIndex, totalFrames: timeline.totalFrames,
            startTime: setup.startTime, thumbnail: nil
        )
        continuation.yield(prog)
    }

    /// Mutable state carried across frames in the loop.
    struct FrameLoopState {
        var cachedMap: UIImage?
        var lastCameraCenter: CLLocationCoordinate2D?
        var lastCameraSpan: MKCoordinateSpan?
        var lastLoggerRegion: Int?
        var audioTimeWritten: Double = 0
        var lastThumbnail: CGImage?
        var droppedFrames: Int = 0
        /// Index into segment plan; reader kept alive across frames for current source segment.
        var segmentIndex: Int = 0
        var segmentReader: AVAssetReader?
        var segmentOutput: AVAssetReaderOutput?
        /// Leftover PCM samples from a split buffer, with sample offset into the data.
        var pendingAudioBuffer: CMSampleBuffer?
        var pendingAudioOffset: Int = 0
    }

    /// Write a single video frame. Returns a failure result if writer errors, nil on success.
    private func writeFrame(
        frameIndex: Int,
        videoTime: Double,
        timeline: VideoTimeline,
        setup: PipelineSetup,
        state: inout FrameLoopState
    ) async -> VideoExportResult? {
        let frameState = buildFrameRenderState(FrameRenderInputs(
            videoTime: videoTime,
            timeline: timeline,
            cachedMapImage: state.cachedMap,
            previousCameraCenter: state.lastCameraCenter,
            previousCameraSpan: state.lastCameraSpan,
            previousLoggerRegion: state.lastLoggerRegion,
            loggerOverlayEnabled: setup.comp.layers.showLoggerOverlay
        ))

        if let result = await setup.comp.renderFrame(
            frameState: frameState,
            pixelBufferPool: setup.pool
        ) {
            let time = CMTime(seconds: videoTime, preferredTimescale: 600)
            let appended = setup.writer.appendVideoFrame(result.buffer, at: time)
            if !appended {
                if !setup.writer.isWriting {
                    await logExportDiag(
                        frameIndex: frameIndex, videoTime: videoTime, state: state,
                        msg: "writer stopped: \(setup.writer.statusDescription)"
                    )
                    return .failed("Writer error at frame \(frameIndex)")
                }
                state.droppedFrames += 1
                if state.droppedFrames == 1 || state.droppedFrames == 50 || state.droppedFrames >= 100 {
                    await logExportDiag(
                        frameIndex: frameIndex, videoTime: videoTime, state: state,
                        msg: "dropped \(state.droppedFrames) consecutive"
                    )
                }
                if state.droppedFrames >= 100 {
                    return .failed("Writer rejecting frames at \(frameIndex)")
                }
            } else {
                state.droppedFrames = 0
            }
            state.cachedMap = result.mapImage
        }

        state.lastCameraCenter = frameState.cameraCenter
        state.lastCameraSpan = frameState.cameraSpan
        state.lastLoggerRegion = frameState.loggerOverlay?.panelRegionIndex
        return nil
    }
}

// MARK: - Interleaved Audio

extension VideoExportActor {
    /// Write audio samples interleaved with video, up to the given video timestamp.
    /// Returns the new audio time cursor.
    private func writeInterleavedAudio(
        writer: VideoWriter,
        audio: AudioState,
        upToVideoTime: Double,
        audioTimeWritten: Double
    ) -> Double {
        var cursor = audioTimeWritten
        let frameDuration = 1.0 / VideoEventSequencer.framesPerSecond

        // Is current video time within the recording's range?
        let recStart = audio.recordingOffsetSeconds
        let recEnd = recStart + audio.recordingDurationSeconds

        if upToVideoTime < recStart || upToVideoTime > recEnd {
            // Outside recording range — write silence for this frame
            let silenceTime = CMTime(seconds: cursor, preferredTimescale: 600)
            if let silence = VideoAudioMixer.silenceBuffer(
                duration: frameDuration,
                sampleRate: audio.sampleRate,
                presentationTime: silenceTime
            ) {
                _ = writer.appendAudioSamples(silence)
            }
            return cursor + frameDuration
        }

        // Within recording range — copy samples from reader
        while cursor < upToVideoTime + frameDuration {
            guard audio.reader.status == .reading,
                  let sampleBuffer = audio.output.copyNextSampleBuffer()
            else {
                // Reader exhausted or error — fill remainder with silence
                let remaining = (upToVideoTime + frameDuration) - cursor
                if remaining > 0 {
                    let silenceTime = CMTime(seconds: cursor, preferredTimescale: 600)
                    if let silence = VideoAudioMixer.silenceBuffer(
                        duration: remaining,
                        sampleRate: audio.sampleRate,
                        presentationTime: silenceTime
                    ) {
                        _ = writer.appendAudioSamples(silence)
                    }
                }
                return upToVideoTime + frameDuration
            }

            // Retime the audio sample to match video timeline position
            let sampleDuration = CMSampleBufferGetDuration(sampleBuffer)
            let outputTime = CMTime(seconds: cursor, preferredTimescale: 600)

            if let retimed = retimeSampleBuffer(sampleBuffer, to: outputTime) {
                _ = writer.appendAudioSamples(retimed)
            }

            cursor += CMTimeGetSeconds(sampleDuration)
        }

        return cursor
    }

    /// Create a copy of a sample buffer with a new presentation timestamp.
    func retimeSampleBuffer(_ buffer: CMSampleBuffer, to time: CMTime) -> CMSampleBuffer? {
        var timing = CMSampleTimingInfo(
            duration: CMSampleBufferGetDuration(buffer),
            presentationTimeStamp: time,
            decodeTimeStamp: .invalid
        )
        var newBuffer: CMSampleBuffer?
        CMSampleBufferCreateCopyWithNewTiming(
            allocator: nil,
            sampleBuffer: buffer,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleBufferOut: &newBuffer
        )
        return newBuffer
    }
}

// MARK: - Diagnostics

extension VideoExportActor {
    /// Rich diagnostic log for export failures — captures audio/video state.
    func logExportDiag(
        frameIndex: Int, videoTime: Double, state: FrameLoopState, msg: String
    ) async {
        let delta = state.audioTimeWritten - videoTime
        let segIdx = state.segmentIndex
        let readerStatus = state.segmentReader?.status.rawValue ?? -1
        let line = """
        VideoExport DIAG frame=\(frameIndex) vTime=\(String(format: "%.3f", videoTime)) \
        aTime=\(String(format: "%.3f", state.audioTimeWritten)) \
        delta=\(String(format: "%.3f", delta)) \
        segIdx=\(segIdx) readerStatus=\(readerStatus) \
        dropped=\(state.droppedFrames): \(msg)
        """
        await MainActor.run {
            SyncDebugLog.shared.log(line, level: .error)
        }
    }

    func logSegmentPlan(_ plan: [AudioSegment], sampleRate: Double, recDuration: Double) {
        var sourceCount = 0
        var silenceCount = 0
        var totalSourceDur: Double = 0
        var totalSilenceDur: Double = 0
        var maxSourceOffset: Double = 0
        for seg in plan {
            switch seg {
            case let .source(sourceOffset, duration, _):
                sourceCount += 1
                totalSourceDur += duration
                maxSourceOffset = max(maxSourceOffset, sourceOffset + duration)
            case let .silence(duration, _):
                silenceCount += 1
                totalSilenceDur += duration
            }
        }
        let line = """
        VideoExport PLAN: \(plan.count) segments (\(sourceCount) source, \(silenceCount) silence) \
        sourceDur=\(String(format: "%.1f", totalSourceDur))s \
        silenceDur=\(String(format: "%.1f", totalSilenceDur))s \
        maxSourceOffset=\(String(format: "%.1f", maxSourceOffset))s \
        recDuration=\(String(format: "%.1f", recDuration))s \
        sampleRate=\(sampleRate)
        """
        Task { @MainActor in
            SyncDebugLog.shared.log(line, level: .info)
        }
    }

    func logWriterFailure(frameIndex: Int, desc: String) async {
        await MainActor.run {
            SyncDebugLog.shared.log(
                "Video writer failed at frame \(frameIndex): \(desc)",
                level: .error
            )
        }
    }
}
