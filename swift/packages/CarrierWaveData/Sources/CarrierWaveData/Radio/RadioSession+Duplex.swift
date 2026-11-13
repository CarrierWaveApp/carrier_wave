import CarrierWaveCore
import Foundation

// MARK: - RadioSession.duplex

/// IC-9700 Main/Sub control for full-duplex satellite work. The radio has
/// no band-addressed frequency command, so every Sub write is a sequence
/// (`07 D1` → `05` → [`06`] → `07 D0`) that must not interleave with the
/// poll loop's `03` read — a reply would belong to whichever band happened
/// to be selected. These helpers pause polling for the whole sequence and
/// leave Main selected so the regular state (frequency, mode) keeps
/// describing the downlink.
public extension RadioSession {
    /// Read `16 5A`. Nil on timeout / NG (e.g. a radio without satellite mode).
    func readSatelliteMode(address: UInt8) async -> Bool? {
        let frame = Data(CIVProtocol.buildFrame(
            to: address, command: CIVDuplex.functionCommand, data: CIVDuplex.readSatelliteMode
        ))
        let reply = await sendCIVQuery(frame) {
            CIVDuplex.parseSatelliteModeReply($0, radio: address) != nil || CIVDuplex.isNak($0, radio: address)
        }
        return reply.flatMap { CIVDuplex.parseSatelliteModeReply($0, radio: address) }
    }

    /// Set `16 5A`. True when the radio acknowledges.
    func setSatelliteMode(_ on: Bool, address: UInt8) async -> Bool {
        let frame = Data(CIVProtocol.buildFrame(
            to: address, command: CIVDuplex.functionCommand, data: CIVDuplex.satelliteMode(on: on)
        ))
        return await sendAwaitingAck(frame, address: address)
    }

    /// Read `07 D2`. Nil on timeout.
    func readSelectedBand(address: UInt8) async -> CIVBand? {
        let frame = Data(CIVProtocol.buildFrame(
            to: address, command: CIVDuplex.selectCommand, data: CIVDuplex.readSelectedBand
        ))
        let reply = await sendCIVQuery(frame) {
            CIVDuplex.parseSelectedBandReply($0, radio: address) != nil
        }
        return reply.flatMap { CIVDuplex.parseSelectedBandReply($0, radio: address) }
    }

    /// Tune the Sub band (and optionally set its mode) in one polling-free
    /// sequence, then reselect Main. Returns false if any step is refused
    /// or times out; Main is reselected regardless so a failure never leaves
    /// the operator's dial on the uplink.
    func tuneSubBand(frequencyHz: UInt64, mode: String?, address: UInt8) async -> Bool {
        let wasPolling = pollTask != nil
        pollTask?.cancel()
        pollTask = nil
        defer {
            if wasPolling, !skipPolling {
                pollTask = Task { [weak self] in await self?.pollLoop() }
            }
        }

        let selectSub = Data(CIVProtocol.buildFrame(
            to: address, command: CIVDuplex.selectCommand, data: CIVDuplex.selectBand(.sub)
        ))
        let selectMain = Data(CIVProtocol.buildFrame(
            to: address, command: CIVDuplex.selectCommand, data: CIVDuplex.selectBand(.main)
        ))
        let setFrequency = Data(CIVProtocol.buildFrame(
            to: address, command: CIVProtocol.cmdSetFreq, data: CIVProtocol.encodeBCDFrequency(frequencyHz)
        ))

        var ok = await sendAwaitingAck(selectSub, address: address, pausePolling: false)
        if ok {
            ok = await sendAwaitingAck(setFrequency, address: address, pausePolling: false)
        }
        if ok, let mode, let civMode = CIVMode.from(carrierWaveMode: mode) {
            let setMode = Data(CIVProtocol.buildFrame(
                to: address, command: CIVProtocol.cmdSetMode, data: [civMode.rawValue]
            ))
            ok = await sendAwaitingAck(setMode, address: address, pausePolling: false)
        }
        let restored = await sendAwaitingAck(selectMain, address: address, pausePolling: false)
        return ok && restored
    }

    /// Send a set command and wait for the radio's `FB`/`FA`. Treats a
    /// timeout as failure. `pausePolling: false` is for callers that have
    /// already stopped the poll loop for a longer sequence.
    func sendAwaitingAck(
        _ frame: Data,
        address: UInt8,
        pausePolling: Bool = true,
        timeout: Duration = .milliseconds(600)
    ) async -> Bool {
        let reply: CIVFrame? = if pausePolling {
            await sendCIVQuery(frame, timeout: timeout) {
                CIVDuplex.isAck($0, radio: address) || CIVDuplex.isNak($0, radio: address)
            }
        } else {
            await awaitCIVReply(after: frame, timeout: timeout) {
                CIVDuplex.isAck($0, radio: address) || CIVDuplex.isNak($0, radio: address)
            }
        }
        guard let reply else {
            return false
        }
        return CIVDuplex.isAck(reply, radio: address)
    }
}

// MARK: - Reply wait without touching the poll task

extension RadioSession {
    /// `sendCIVQuery` minus the poll-loop pause, for use inside a sequence
    /// that already paused it. Chains `codecTap` the same way.
    func awaitCIVReply(
        after frame: Data,
        timeout: Duration,
        matches: @escaping @Sendable (CIVFrame) -> Bool
    ) async -> CIVFrame? {
        let savedTap = codecTap
        let (stream, continuation) = AsyncStream<Data>.makeStream()
        codecTap = { raw in
            savedTap?(raw)
            continuation.yield(raw)
        }
        defer { codecTap = savedTap }

        do {
            try await transport.send(frame)
        } catch {
            return nil
        }

        let timeoutTask = Task {
            try? await Task.sleep(for: timeout)
            continuation.finish()
        }
        defer { timeoutTask.cancel() }

        for await raw in stream {
            let parsed = CIVProtocol.extractFrames(from: [UInt8](raw)).frames
            if let hit = parsed.first(where: matches) {
                continuation.finish()
                return hit
            }
        }
        return nil
    }
}
