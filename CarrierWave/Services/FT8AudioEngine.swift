//
//  FT8AudioEngine.swift
//  CarrierWave
//

import Accelerate
import AVFoundation
import CarrierWaveCore
import os

// MARK: - FT8AudioEngine

/// Manages AVAudioEngine for FT8 audio capture and playback.
/// Handles resampling from device sample rate to 12 kHz for the FT8 codec.
actor FT8AudioEngine {
    // MARK: Internal

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

        setupPlayerNode()
        observeInterruptions()
    }

    // MARK: - Start/Stop

    func start(onSlotReady: @escaping @Sendable ([Float]) -> Void) throws {
        self.onSlotReady = onSlotReady
        inputBuffer.removeAll()
        setupInputTap()
        try engine.start()
        isRunning = true
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        playerNode?.stop()
        engine.stop()
        isRunning = false
        onSlotReady = nil
        onWaterfallChunk = nil
    }

    // MARK: - Transmit

    func playTones(_ samples: [Float]) {
        guard let player = playerNode,
              let format = AVAudioFormat(
                  commonFormat: .pcmFormatFloat32,
                  sampleRate: targetSampleRate,
                  channels: 1,
                  interleaved: false
              ),
              let buffer = AVAudioPCMBuffer(
                  pcmFormat: format,
                  frameCapacity: AVAudioFrameCount(samples.count)
              )
        else {
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

        player.scheduleBuffer(buffer)
        if !player.isPlaying {
            player.play()
        }
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

    func setAudioLevelCallback(_ callback: @escaping @Sendable (Float) -> Void) {
        onAudioLevel = callback
    }

    // MARK: - Waterfall

    func setWaterfallCallback(_ callback: @escaping @Sendable ([Float]) -> Void) {
        onWaterfallChunk = callback
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

    private let engine = AVAudioEngine()
    private var playerNode: AVAudioPlayerNode?
    private var isRunning = false
    private var inputBuffer: [Float] = []
    private let targetSampleRate = Double(FT8Constants.sampleRate)

    /// Maximum buffer size: 2 full slots. Drop old audio if falling behind.
    private let maxBufferSamples = FT8Constants.samplesPerSlot * 2

    // Callbacks
    private var onSlotReady: (@Sendable ([Float]) -> Void)?
    private var onAudioLevel: (@Sendable (Float) -> Void)?
    private var onWaterfallChunk: (@Sendable ([Float]) -> Void)?

    /// Interruption observer
    private var interruptionObserver: (any NSObjectProtocol)?

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

        let outputCount = samples.count / ratio
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

    private func setupInputTap() {
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        let deviceSampleRate = inputFormat.sampleRate
        let decimationRatio = Int(deviceSampleRate / targetSampleRate)

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

        // Report audio level using vDSP for efficiency
        if let levelCallback = onAudioLevel, !samples.isEmpty {
            var rms: Float = 0
            samples.withUnsafeBufferPointer { buf in
                guard let ptr = buf.baseAddress else {
                    return
                }
                vDSP_rmsqv(ptr, 1, &rms, vDSP_Length(samples.count))
            }
            levelCallback(rms)
        }

        // Deliver chunks continuously for waterfall display (~2048 samples = ~170ms)
        onWaterfallChunk?(samples)

        // Slot delivery is now on-demand via collectSlot() called at UTC boundaries
    }

    // MARK: - Interruption Handling

    private func observeInterruptions() {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            // Extract Sendable values from notification before crossing actor boundary
            guard let userInfo = notification.userInfo,
                  let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt
            else {
                return
            }
            let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt
            Task { await self?.handleInterruption(type: typeValue, options: optionsValue) }
        }
    }

    private func handleInterruption(type typeValue: UInt, options optionsValue: UInt?) {
        guard let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }

        switch type {
        case .began:
            Self.log.info("Audio session interrupted — stopping engine")
            stop()

        case .ended:
            let shouldResume = optionsValue.map {
                AVAudioSession.InterruptionOptions(rawValue: $0).contains(.shouldResume)
            } ?? false

            if shouldResume, let callback = onSlotReady {
                Self.log.info("Audio interruption ended — resuming")
                do {
                    try start(onSlotReady: callback)
                } catch {
                    Self.log.error("Failed to restart after interruption: \(error)")
                }
            }

        @unknown default:
            break
        }
    }
}

// MARK: - FT8AudioEngineError

enum FT8AudioEngineError: Error, LocalizedError {
    case unsupportedSampleRate(Double)

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case let .unsupportedSampleRate(rate):
            "Device sample rate \(rate) Hz does not support integer-ratio decimation to 12 kHz"
        }
    }
}
