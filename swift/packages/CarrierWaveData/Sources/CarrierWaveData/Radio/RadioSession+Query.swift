import CarrierWaveCore
import Foundation

// MARK: - RadioSession.sendQuery

public extension RadioSession {
    /// One-shot CAT query. Pauses polling for the duration so the response
    /// can't get interleaved with another poll, optionally sends `preamble`
    /// (e.g. `MN128;` for an Elecraft menu read), sends `command`, waits for
    /// a complete framed reply matching `expectedPrefix`, then sends
    /// `postamble` (e.g. `MN255;` to exit menu mode) before resuming the
    /// poll. Returns the matched response as ASCII (trimmed). Returns nil
    /// on timeout. Any pre-existing `codecTap` is preserved by chaining.
    func sendQuery(
        command: String,
        expectedPrefix: String,
        preamble: String? = nil,
        postamble: String? = nil,
        timeout: Duration = .milliseconds(500)
    ) async -> String? {
        let savedTap = codecTap
        let (stream, continuation) = AsyncStream<Data>.makeStream()
        codecTap = { frame in
            savedTap?(frame)
            continuation.yield(frame)
        }

        let wasPolling = pollTask != nil
        pollTask?.cancel()
        pollTask = nil

        do {
            if let preamble {
                try await transport.send(Data(preamble.utf8))
            }
            try await transport.send(Data(command.utf8))
        } catch {
            codecTap = savedTap
            if wasPolling, !skipPolling {
                pollTask = Task { [weak self] in await self?.pollLoop() }
            }
            return nil
        }

        let timeoutTask = Task {
            try? await Task.sleep(for: timeout)
            continuation.finish()
        }

        var matched: String?
        for await frame in stream {
            guard let text = String(data: frame, encoding: .ascii) else {
                continue
            }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix(expectedPrefix), trimmed.hasSuffix(";") {
                matched = trimmed
                continuation.finish()
                break
            }
        }
        timeoutTask.cancel()

        if let postamble {
            try? await transport.send(Data(postamble.utf8))
        }

        codecTap = savedTap
        if wasPolling, !skipPolling {
            pollTask = Task { [weak self] in await self?.pollLoop() }
        }
        return matched
    }

    /// One-shot CI-V query: pauses polling, sends `frame`, and returns the
    /// first received CI-V frame that `matches` accepts. Returns nil on send
    /// failure or timeout. Same `codecTap` chaining as `sendQuery`.
    func sendCIVQuery(
        _ frame: Data,
        timeout: Duration = .milliseconds(500),
        matches: @escaping @Sendable (CIVFrame) -> Bool
    ) async -> CIVFrame? {
        let savedTap = codecTap
        let (stream, continuation) = AsyncStream<Data>.makeStream()
        codecTap = { raw in
            savedTap?(raw)
            continuation.yield(raw)
        }

        let wasPolling = pollTask != nil
        pollTask?.cancel()
        pollTask = nil
        defer {
            codecTap = savedTap
            if wasPolling, !skipPolling {
                pollTask = Task { [weak self] in await self?.pollLoop() }
            }
        }

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
