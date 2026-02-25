//
//  FT8AudioEngine.swift
//  CarrierWave
//

import AVFoundation
import CarrierWaveCore

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
            options: [.allowBluetoothHFP, .defaultToSpeaker]
        )

        try session.setPreferredSampleRate(48_000) // Prefer 48kHz for clean 4:1 decimation
        try session.setPreferredIOBufferDuration(0.02) // 20ms buffers
        try session.setActive(true)

        setupPlayerNode()
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
        player.play()
    }

    // MARK: - Audio Level

    func setAudioLevelCallback(_ callback: @escaping @Sendable (Float) -> Void) {
        onAudioLevel = callback
    }

    // MARK: Private

    private let engine = AVAudioEngine()
    private var playerNode: AVAudioPlayerNode?
    private var isRunning = false
    private var inputBuffer: [Float] = []
    private let targetSampleRate = Double(FT8Constants.sampleRate)

    // Callbacks
    private var onSlotReady: (@Sendable ([Float]) -> Void)?
    private var onAudioLevel: (@Sendable (Float) -> Void)?

    private static func extractSamples(from buffer: AVAudioPCMBuffer) -> [Float] {
        guard let channelData = buffer.floatChannelData else {
            return []
        }
        let count = Int(buffer.frameLength)
        return Array(UnsafeBufferPointer(start: channelData[0], count: count))
    }

    /// Decimate audio from device sample rate to target rate.
    /// For 48kHz → 12kHz, this is a simple 4:1 decimation.
    nonisolated private static func decimate(
        _ samples: [Float],
        fromRate: Double,
        toRate: Double
    ) -> [Float] {
        let ratio = Int(fromRate / toRate)
        guard ratio > 1 else {
            return samples
        }

        // Simple decimation — take every Nth sample.
        // A proper anti-aliasing filter should be added for production use.
        var result = [Float]()
        result.reserveCapacity(samples.count / ratio)
        for i in stride(from: 0, to: samples.count, by: ratio) {
            result.append(samples[i])
        }
        return result
    }

    private func setupInputTap() {
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        let deviceSampleRate = inputFormat.sampleRate
        let targetRate = targetSampleRate

        inputNode.installTap(onBus: 0, bufferSize: 4_096, format: inputFormat) {
            [weak self] buffer, _ in
            guard let self else {
                return
            }
            let samples = Self.extractSamples(from: buffer)
            let resampled = Self.decimate(
                samples,
                fromRate: deviceSampleRate,
                toRate: targetRate
            )
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
            return
        }

        engine.connect(player, to: engine.mainMixerNode, format: outputFormat)
        playerNode = player
    }

    private func appendSamples(_ samples: [Float]) {
        inputBuffer.append(contentsOf: samples)

        // Report audio level
        if let levelCallback = onAudioLevel, !samples.isEmpty {
            let rms = sqrt(samples.map { $0 * $0 }.reduce(0, +) / Float(samples.count))
            levelCallback(rms)
        }

        // When we have a full 15-second slot, deliver it
        if inputBuffer.count >= FT8Constants.samplesPerSlot {
            let slot = Array(inputBuffer.prefix(FT8Constants.samplesPerSlot))
            inputBuffer.removeFirst(FT8Constants.samplesPerSlot)
            onSlotReady?(slot)
        }
    }
}
