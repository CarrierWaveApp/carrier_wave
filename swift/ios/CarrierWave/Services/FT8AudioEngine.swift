//
//  FT8AudioEngine.swift
//  CarrierWave
//

import Accelerate
import AVFoundation
import CarrierWaveData
import OSLog

// MARK: - FT8AudioEngine

/// Manages AVAudioEngine for FT8 audio capture and playback.
/// Handles resampling from device sample rate to 12 kHz for the FT8 codec.
actor FT8AudioEngine {
    // MARK: Internal

    // Accessed by FT8AudioEngine+RouteChange — kept at default `internal`
    // (rather than `private`) so the same-actor extension in a different
    // file can drive interrupt/route recovery.
    let engine = AVAudioEngine()
    var isRunning = false
    var onSlotReady: (@Sendable ([Float]) -> Void)?
    var savedSlotCallback: (@Sendable ([Float]) -> Void)?
    var routeChangeObserver: (any NSObjectProtocol)?
    /// Fired after a route change has been handled. Wired by the session
    /// manager to reset overload tracking so the previous device's history
    /// doesn't latch the banner against the new device.
    var onRouteChange: (@Sendable () -> Void)?

    /// Interruption observer — accessed by FT8AudioEngine+Interruption.
    var interruptionObserver: (any NSObjectProtocol)?

    // MARK: - Configuration

    func configure() throws {
        let session = AVAudioSession.sharedInstance()

        try session.setCategory(
            .playAndRecord,
            mode: .measurement, // Disables voice processing — critical for data modes
            options: []
        )

        try session.setPreferredSampleRate(48_000) // Prefer 48kHz for clean 4:1 decimation
        try session.setPreferredIOBufferDuration(0.02) // 20ms buffers
        try session.setActive(true)

        // Validate we got the sample rate we need for integer-ratio decimation
        let actualRate = session.sampleRate
        let ratio = actualRate / targetSampleRate
        guard ratio == ratio.rounded(), ratio >= 1 else {
            throw FT8AudioEngineError.unsupportedSampleRate(actualRate)
        }

        // Only set up player and observer once — avoid leaking on repeated configure calls
        if playerNode == nil {
            setupPlayerNode()
        }
        if interruptionObserver == nil {
            observeInterruptions()
        }
        if routeChangeObserver == nil {
            observeRouteChanges()
        }
    }

    // MARK: - Start/Stop

    func start(onSlotReady: @escaping @Sendable ([Float]) -> Void) throws {
        // Remove any stale tap before installing a new one — installTap throws
        // an unrecoverable NSException if a tap is already installed.
        engine.inputNode.removeTap(onBus: 0)

        self.onSlotReady = onSlotReady
        inputBuffer.removeAll()
        resetLevelMetering()
        do {
            try setupInputTap()
            try engine.start()
        } catch {
            // Clean up partial state so the next attempt starts from a
            // known-good baseline. Without this, a failed start could leave
            // a tap installed (next removeTap is fine) or — worse — leave the
            // engine half-started and the input format stuck in a bad shape.
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            self.onSlotReady = nil
            throw error
        }
        isRunning = true
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        playerNode?.stop()
        engine.stop()
        isRunning = false
        onSlotReady = nil
        onWaterfallChunk = nil
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
            self.interruptionObserver = nil
        }
        if let routeChangeObserver {
            NotificationCenter.default.removeObserver(routeChangeObserver)
            self.routeChangeObserver = nil
        }
        // Intentionally NOT calling setActive(false). A user toggling Logger
        // mode off FT8 then back on quickly fires a fire-and-forget stop(),
        // and the new session manager calls setActive(true) before the old
        // stop runs. setActive(false) here would race in and kill the new
        // session, leaving the next FT8 attempt silently broken until the
        // app is force-quit. The audio session is process-scoped — let the
        // OS reclaim it when the app backgrounds or terminates.
    }

    // MARK: - Transmit

    func playTones(_ samples: [Float]) {
        guard let player = playerNode else {
            Self.log.error("playTones: no player node")
            return
        }
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            Self.log.error("playTones: failed to create audio format")
            return
        }
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(samples.count)
        ) else {
            Self.log.error("playTones: failed to create PCM buffer")
            return
        }

        buffer.frameLength = AVAudioFrameCount(samples.count)
        if let channelData = buffer.floatChannelData {
            samples.withUnsafeBufferPointer { src in
                guard let srcBase = src.baseAddress else {
                    return
                }
                channelData[0].update(from: srcBase, count: samples.count)
            }
        }

        let wasPlaying = player.isPlaying
        player.scheduleBuffer(buffer)
        if !wasPlaying {
            player.play()
        }

        let duration = Double(samples.count) / targetSampleRate
        let playing = player.isPlaying
        let running = engine.isRunning
        Self.log.info(
            "playTones: \(samples.count) samples \(duration)s was=\(wasPlaying) now=\(playing) run=\(running)"
        )
    }

    // MARK: - Slot Collection

    /// Collect the most recent slot-worth of audio aligned to a UTC boundary.
    /// Called by the session manager at each 15-second slot boundary.
    /// Returns nil if insufficient audio has accumulated.
    func collectSlot() -> [Float]? {
        let needed = FT8Constants.samplesPerSlot
        guard inputBuffer.count >= needed else {
            print("[FT8Engine] collectSlot: only \(inputBuffer.count)/\(needed) samples, skipping")
            return nil
        }
        // Take the most recent full slot (discard older excess)
        let excess = inputBuffer.count - needed
        if excess > 0 {
            inputBuffer.removeFirst(excess)
        }
        let slot = Array(inputBuffer)
        inputBuffer.removeAll()
        print("[FT8Engine] collectSlot: \(slot.count) samples delivered (discarded \(excess) excess)")
        return slot
    }

    // MARK: - Audio Level

    func setAudioLevelCallback(_ callback: @escaping @Sendable (FT8AudioLevel) -> Void) {
        onAudioLevel = callback
    }

    /// Wires a callback fired after the engine recovers from a route change.
    /// The session manager uses this to clear `audioOverload` history so the
    /// previous input device's clipped peaks don't latch the banner on a
    /// quieter new device.
    func setOnRouteChange(_ callback: @escaping @Sendable () -> Void) {
        onRouteChange = callback
    }

    /// Clears band-pass filter delay lines and rate-limit timestamp. Called
    /// on route change and interruption resume so transient state from the
    /// previous capture session doesn't bleed into the next.
    func resetLevelMetering() {
        bandpassFilter.reset()
        lastLevelEmit = .distantPast
    }

    // MARK: - Waterfall

    func setWaterfallCallback(_ callback: @escaping @Sendable ([Float]) -> Void) {
        onWaterfallChunk = callback
    }

    func setupInputTap() throws {
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        // Validate format before installTap — an invalid format (0 channels, 0 Hz)
        // causes an unrecoverable NSException that Swift try/catch cannot intercept.
        guard inputFormat.channelCount > 0, inputFormat.sampleRate > 0 else {
            throw FT8AudioEngineError.noAudioInput
        }

        let deviceSampleRate = inputFormat.sampleRate
        let decimationRatio = Int(deviceSampleRate / targetSampleRate)

        guard decimationRatio >= 1 else {
            throw FT8AudioEngineError.unsupportedSampleRate(deviceSampleRate)
        }

        inputNode.installTap(onBus: 0, bufferSize: 4_096, format: inputFormat) {
            [weak self] buffer, _ in
            guard let self else {
                return
            }
            let samples = Self.extractSamples(from: buffer)
            let resampled = Self.decimate(samples, ratio: decimationRatio)
            Task { await self.appendSamples(resampled) }
        }
    }

    // MARK: Private

    private static let log = Logger(
        subsystem: "com.jsvana.CarrierWave",
        category: "FT8AudioEngine"
    )

    /// 15-tap low-pass FIR filter for 4:1 decimation (cutoff ~0.4 Nyquist).
    /// Coefficients designed with a Hamming window.
    nonisolated private static let antiAliasFilter: [Float] = [
        0.0025, 0.0072, 0.0210, 0.0445, 0.0748,
        0.1050, 0.1250, 0.1300, 0.1250, 0.1050,
        0.0748, 0.0445, 0.0210, 0.0072, 0.0025,
    ]

    private static let levelEmitInterval: TimeInterval = 0.1

    private var playerNode: AVAudioPlayerNode?
    private var inputBuffer: [Float] = []
    private let targetSampleRate = Double(FT8Constants.sampleRate)

    /// Maximum buffer size: 2 full slots. Drop old audio if falling behind.
    private let maxBufferSamples = FT8Constants.samplesPerSlot * 2

    private var onAudioLevel: (@Sendable (FT8AudioLevel) -> Void)?
    private var onWaterfallChunk: (@Sendable ([Float]) -> Void)?

    /// Band-limited (200–2900 Hz) measurement filter for the level callback.
    /// Wide-band peak detection mis-fires on out-of-passband signals; this
    /// constrains the level metric to the FT8 audio sub-band.
    private lazy var bandpassFilter = FT8AudioBandpassFilter(sampleRate: targetSampleRate)

    /// Wall-clock time of the most recent level callback. Used to throttle
    /// the callback to ~10 Hz so a 50 Hz tap can't backlog the main actor
    /// with level-update tasks during heavy SwiftUI redraws.
    private var lastLevelEmit: Date = .distantPast

    private static func extractSamples(from buffer: AVAudioPCMBuffer) -> [Float] {
        guard let channelData = buffer.floatChannelData else {
            return []
        }
        let count = Int(buffer.frameLength)
        return Array(UnsafeBufferPointer(start: channelData[0], count: count))
    }

    /// Low-pass filter + decimate from device sample rate to target rate.
    /// Uses vDSP_desamp for anti-aliased decimation.
    nonisolated private static func decimate(
        _ samples: [Float],
        ratio: Int
    ) -> [Float] {
        guard ratio > 1 else {
            return samples
        }

        // vDSP_desamp reads `outputCount * ratio + filterLength - 1` input
        // samples per call. The old formula `samples.count / ratio` read
        // `filterLength - 1` floats past the end of the AVAudioPCMBuffer's
        // channel data — uninitialized heap memory occasionally near ±1.0,
        // producing phantom near-full-scale peaks at the tail of every
        // buffer and latching the overload tracker into critical state on
        // perfectly clean input. Trim the output count so every read stays
        // in-bounds; the lost samples (≤ filterLength/ratio per buffer)
        // never affect FT8 decoding.
        let safeInputCount = samples.count - antiAliasFilter.count + 1
        let outputCount = max(0, safeInputCount) / ratio
        guard outputCount > 0 else {
            return []
        }

        var result = [Float](repeating: 0, count: outputCount)
        samples.withUnsafeBufferPointer { inputBuf in
            guard let inputPtr = inputBuf.baseAddress else {
                return
            }
            result.withUnsafeMutableBufferPointer { outputBuf in
                guard let outputPtr = outputBuf.baseAddress else {
                    return
                }
                antiAliasFilter.withUnsafeBufferPointer { filterBuf in
                    guard let filterPtr = filterBuf.baseAddress else {
                        return
                    }
                    vDSP_desamp(
                        inputPtr,
                        vDSP_Stride(ratio),
                        filterPtr,
                        outputPtr,
                        vDSP_Length(outputCount),
                        vDSP_Length(antiAliasFilter.count)
                    )
                }
            }
        }
        return result
    }

    private func setupPlayerNode() {
        let player = AVAudioPlayerNode()
        engine.attach(player)

        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            Self.log.error("Failed to create output audio format")
            return
        }

        engine.connect(player, to: engine.mainMixerNode, format: outputFormat)
        playerNode = player
    }

    private func appendSamples(_ samples: [Float]) {
        inputBuffer.append(contentsOf: samples)

        // Cap buffer to prevent unbounded growth if processing falls behind
        if inputBuffer.count > maxBufferSamples {
            inputBuffer.removeFirst(inputBuffer.count - maxBufferSamples)
        }

        emitLevelIfDue(samples: samples)

        // Deliver chunks continuously for waterfall display (~2048 samples = ~170ms)
        onWaterfallChunk?(samples)

        // Slot delivery is now on-demand via collectSlot() called at UTC boundaries
    }

    /// Rate-limit the level callback to ~10 Hz and compute band-limited
    /// stats alongside the wide-band ones. Wide-band peak alone mis-fires
    /// on out-of-passband signals; the band-limited measurement is what
    /// the overload tracker and meter actually need for FT8.
    private func emitLevelIfDue(samples: [Float]) {
        guard let levelCallback = onAudioLevel, !samples.isEmpty else {
            return
        }
        let now = Date()
        guard now.timeIntervalSince(lastLevelEmit) >= Self.levelEmitInterval else {
            return
        }
        lastLevelEmit = now

        var wideRMS: Float = 0
        var widePeak: Float = 0
        samples.withUnsafeBufferPointer { buf in
            guard let ptr = buf.baseAddress else {
                return
            }
            vDSP_rmsqv(ptr, 1, &wideRMS, vDSP_Length(samples.count))
            vDSP_maxmgv(ptr, 1, &widePeak, vDSP_Length(samples.count))
        }
        let band = bandpassFilter.levelOfFiltered(samples)

        levelCallback(FT8AudioLevel(
            rms: wideRMS,
            peak: widePeak,
            bandRMS: band.rms,
            bandPeak: band.peak,
            captureTime: now
        ))
    }
}

// MARK: - FT8AudioEngineError

enum FT8AudioEngineError: Error, LocalizedError {
    case unsupportedSampleRate(Double)
    case noAudioInput

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case let .unsupportedSampleRate(rate):
            "Device sample rate \(rate) Hz does not support integer-ratio decimation to 12 kHz"
        case .noAudioInput:
            "No audio input available. Connect an audio interface or check microphone permissions."
        }
    }
}
