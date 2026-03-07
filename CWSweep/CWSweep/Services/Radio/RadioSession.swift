import CarrierWaveCore
import CarrierWaveData
import Foundation
import os

private let logger = Logger(subsystem: "com.jsvana.CWSweep", category: "RadioSession")

// MARK: - RadioSession

/// Transport-agnostic radio session that polls frequency/mode and publishes state.
actor RadioSession {
    // MARK: Lifecycle

    init(transport: any RadioTransport, protocolHandler: any RadioProtocolHandler) {
        self.transport = transport
        self.protocolHandler = protocolHandler
    }

    // MARK: Internal

    struct RadioState: Sendable {
        var frequency: Double = 0 // MHz
        var mode: String = ""
        var isTransmitting: Bool = false
        var signalStrength: Int? // S-meter
        var isConnected: Bool = false
        var xitEnabled: Bool = false
        var ritEnabled: Bool = false
        var ritXitOffset: Int = 0 // Hz
    }

    private(set) var state = RadioState()

    func start() async throws {
        try await transport.connect()
        state.isConnected = true

        let frameType: FrameAssembler.FrameType =
            protocolHandler is CIVProtocolHandler ? .civ : .kenwood
        frameAssembler = FrameAssembler(frameType: frameType)

        // Start receive loop
        pollTask = Task { [weak self] in
            guard let self else {
                return
            }
            await receiveLoop()
        }

        // Start polling frequency/mode
        Task { [weak self] in
            guard let self else {
                return
            }
            await pollLoop()
        }
    }

    func stop() async {
        pollTask?.cancel()
        pollTask = nil
        await transport.disconnect()
        state.isConnected = false
    }

    func tuneToFrequency(_ freqMHz: Double) async throws {
        let data = protocolHandler.encodeSetFrequency(freqMHz)
        try await transport.send(data)
    }

    func setMode(_ mode: String) async throws {
        let data = protocolHandler.encodeSetMode(mode)
        try await transport.send(data)
    }

    func setPTT(_ on: Bool) async throws {
        let data = protocolHandler.encodeSetPTT(on)
        try await transport.send(data)
        state.isTransmitting = on
    }

    func setXIT(_ on: Bool) async throws {
        guard let data = protocolHandler.encodeSetXIT(on) else {
            return
        }
        try await transport.send(data)
    }

    func setXITOffset(_ hz: Int) async throws {
        guard let data = protocolHandler.encodeSetXITOffset(hz) else {
            return
        }
        try await transport.send(data)
    }

    func clearRITXIT() async throws {
        guard let data = protocolHandler.encodeClearRITXIT() else {
            return
        }
        try await transport.send(data)
    }

    // MARK: Private

    private let transport: any RadioTransport
    private let protocolHandler: any RadioProtocolHandler
    private var pollTask: Task<Void, Never>?
    private var frameAssembler: FrameAssembler?

    private func receiveLoop() async {
        for await data in transport.receivedData {
            guard let assembler = frameAssembler else {
                continue
            }
            let frames = await assembler.feed(data)
            for frame in frames {
                processFrame(frame)
            }
        }
        logger.info("Receive loop ended")
    }

    private func processFrame(_ frame: Data) {
        if let freq = protocolHandler.decodeFrequency(from: frame) {
            state.frequency = freq
        }
        if let mode = protocolHandler.decodeMode(from: frame) {
            state.mode = mode
        }
        if let tx = protocolHandler.decodePTTState(from: frame) {
            state.isTransmitting = tx
        }
        if let xit = protocolHandler.decodeXITState(from: frame) {
            state.xitEnabled = xit
        }
        if let rit = protocolHandler.decodeRITState(from: frame) {
            state.ritEnabled = rit
        }
        if let offset = protocolHandler.decodeRITXITOffset(from: frame) {
            state.ritXitOffset = offset
        }
    }

    private func pollLoop() async {
        logger.info("Poll loop started")
        while !Task.isCancelled, state.isConnected {
            // Request frequency
            if let cmd = protocolHandler.encodeReadFrequency() {
                do {
                    try await transport.send(cmd)
                } catch {
                    logger.error("Failed to send freq poll: \(error)")
                }
            }

            // Request mode
            if let cmd = protocolHandler.encodeReadMode() {
                do {
                    try await transport.send(cmd)
                } catch {
                    logger.error("Failed to send mode poll: \(error)")
                }
            }

            // Request XIT state
            if let cmd = protocolHandler.encodeReadXIT() {
                do {
                    try await transport.send(cmd)
                } catch {
                    logger.error("Failed to send XIT poll: \(error)")
                }
            }

            // Request RIT state
            if let cmd = protocolHandler.encodeReadRIT() {
                do {
                    try await transport.send(cmd)
                } catch {
                    logger.error("Failed to send RIT poll: \(error)")
                }
            }

            // Request RIT/XIT offset
            if let cmd = protocolHandler.encodeReadRITXITOffset() {
                do {
                    try await transport.send(cmd)
                } catch {
                    logger.error("Failed to send RIT/XIT offset poll: \(error)")
                }
            }

            try? await Task.sleep(for: .milliseconds(200))
        }
        logger.info("Poll loop ended")
    }
}
