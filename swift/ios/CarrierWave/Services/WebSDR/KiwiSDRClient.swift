import CarrierWaveCore
import CarrierWaveData
import Foundation

// MARK: - KiwiSDRClient

/// Client for streaming audio from a KiwiSDR receiver.
///
/// Thin wrapper over the Rust core (`SdrApi.connect`), which owns the
/// websocket protocol: auth handshake, sample-rate negotiation, compression,
/// tuning, AGC, keepalive, server-redirect following, and IMA ADPCM decode.
/// Decoded PCM frames stream back through `SdrAudioListener` and are exposed
/// here as the same `AsyncStream<AudioFrame>` the previous all-Swift client
/// provided.
actor KiwiSDRClient {
    // MARK: Lifecycle

    init(host: String, port: Int = 8_073) {
        self.host = host
        self.port = port
    }

    // MARK: Internal

    /// Audio frame received from the KiwiSDR
    struct AudioFrame {
        let samples: [Int16]
        let sampleRate: Double
        let sMeter: UInt16
        let timestamp: Date
    }

    /// Negotiated sample rate from the server handshake
    private(set) var negotiatedSampleRate: Double = 12_000

    /// Host actually connected to (differs from the requested host after a
    /// server redirect; the Rust core follows up to 3 redirects internally).
    private(set) var effectiveHost: String?
    private(set) var effectivePort: Int?

    /// Connect and start receiving audio. Returns an AsyncStream of audio
    /// frames. `mode` is the Carrier Wave mode string (CW/SSB/FT8/…); the
    /// Rust core resolves it to a KiwiSDR mode + passband by frequency.
    func connect(
        frequencyKHz: Double,
        mode: String,
        password: String? = nil
    ) async throws -> AsyncStream<AudioFrame> {
        guard connection == nil else {
            throw KiwiSDRError.alreadyConnected
        }

        let api = try SdrApiProvider.shared()
        let (stream, continuation) = AsyncStream<AudioFrame>.makeStream()
        let listener = FrameListener(continuation: continuation)

        let newConnection = try await api.connect(
            host: host,
            port: UInt16(port),
            frequencyKhz: frequencyKHz,
            mode: mode,
            password: password,
            listener: listener
        )

        connection = newConnection
        audioContinuation = continuation
        negotiatedSampleRate = newConnection.sampleRate()
        effectiveHost = newConnection.effectiveHost()
        effectivePort = Int(newConnection.effectivePort())
        listener.setSampleRate(negotiatedSampleRate)

        continuation.onTermination = { [weak self] _ in
            Task { await self?.disconnect() }
        }

        return stream
    }

    /// Disconnect from the KiwiSDR
    func disconnect() {
        connection?.disconnect()
        connection = nil
        audioContinuation?.finish()
        audioContinuation = nil
        effectiveHost = nil
        effectivePort = nil
    }

    /// Retune to a new frequency
    func retune(frequencyKHz: Double) async throws {
        guard let connection else {
            throw KiwiSDRError.notConnected
        }
        try connection.retune(frequencyKhz: frequencyKHz)
    }

    /// Change mode (Carrier Wave mode string; SSB resolves by frequency)
    func changeMode(_ mode: String, frequencyMHz: Double?) async throws {
        guard let connection else {
            throw KiwiSDRError.notConnected
        }
        try connection.changeMode(mode: mode, frequencyMhz: frequencyMHz)
    }

    // MARK: Private

    /// Bridges Rust callback frames into the AsyncStream. Called from Rust
    /// worker threads; the continuation and lock-guarded sample rate are the
    /// only state touched, both thread-safe.
    private final class FrameListener: SdrAudioListener, @unchecked Sendable {
        // MARK: Lifecycle

        init(continuation: AsyncStream<AudioFrame>.Continuation) {
            self.continuation = continuation
        }

        // MARK: Internal

        func setSampleRate(_ rate: Double) {
            lock.withLock { sampleRate = rate }
        }

        func onAudioFrame(samples: [Int16], sMeter: UInt16) {
            let rate = lock.withLock { sampleRate }
            continuation.yield(AudioFrame(
                samples: samples,
                sampleRate: rate,
                sMeter: sMeter,
                timestamp: Date()
            ))
        }

        func onDisconnected(reason _: String) {
            continuation.finish()
        }

        // MARK: Private

        private let continuation: AsyncStream<AudioFrame>.Continuation
        private let lock = NSLock()
        private var sampleRate: Double = 12_000
    }

    private let host: String
    private let port: Int

    private var connection: SdrConnection?
    private var audioContinuation: AsyncStream<AudioFrame>.Continuation?
}
