import Darwin
import Foundation
import OSLog

private let logger = Logger(subsystem: "com.jsvana.CWSweep", category: "JttySidecarClient")

// MARK: - JttySidecarClient

/// Client side of the jtty-sidecar shared-memory protocol (`JttyShmLayout`).
///
/// One instance maps the segment a `jtty-sidecar serve <name>` process
/// created. Receive audio is written into the segment's ring from the audio
/// thread (`writeReceiveAudio`), decoder results are polled from the main
/// actor (`drainResults`), and a transmit request renders one message at a
/// time (`transmit`). The protocol's wake-up semaphores are optional — the
/// server polls every 100 ms regardless — and `sem_open`/`shm_open` are C
/// variadic functions Swift cannot call, so this client polls the counters
/// and resolves `shm_open` through `dlsym` with its fixed arguments only
/// (the variadic `mode` is read by the callee only with `O_CREAT`).
final class JttySidecarClient: @unchecked Sendable {
    // MARK: Lifecycle

    /// Wrap memory laid out like the segment. Production code uses
    /// `open(name:)`; tests hand in a buffer they own.
    init(name: String, base: UnsafeMutableRawPointer, mappedSize: Int, unmapOnClose: Bool) {
        self.name = name
        self.base = base
        self.mappedSize = mappedSize
        self.unmapOnClose = unmapOnClose
        rxWritten = base.loadUnaligned(fromByteOffset: JttyShmLayout.rxWrittenOffset, as: Int64.self)
        resultsRead = base.loadUnaligned(fromByteOffset: JttyShmLayout.resultsWrittenOffset, as: Int64.self)
        txSeq = base.loadUnaligned(fromByteOffset: JttyShmLayout.txResponseSeqDoneOffset, as: Int32.self)
    }

    deinit {
        close()
    }

    // MARK: Internal

    enum ClientError: LocalizedError {
        case unavailable(String)
        case tooSmall(Int)
        case protocolMismatch(version: UInt32, size: UInt32)
        case notRunning
        case transmitTimeout
        case transmitRejected(JttyShmLayout.TxStatus)

        // MARK: Internal

        var errorDescription: String? {
            switch self {
            case let .unavailable(reason): "Shared memory segment unavailable: \(reason)"
            case let .tooSmall(size): "Shared memory segment is only \(size) bytes"
            case let .protocolMismatch(version, size):
                "Helper speaks protocol v\(version) with a \(size)-byte segment; CW Sweep expects "
                    + "v\(JttyShmLayout.version) / \(JttyShmLayout.totalSize) bytes"
            case .notRunning: "Helper is not running"
            case .transmitTimeout: "Helper did not render the message in time"
            case let .transmitRejected(status): "Helper rejected the message: \(status.description)"
            }
        }
    }

    let name: String

    // MARK: Header

    var magic: UInt32 {
        load(UInt32.self, at: JttyShmLayout.magicOffset)
    }

    var version: UInt32 {
        load(UInt32.self, at: JttyShmLayout.versionOffset)
    }

    var structSize: UInt32 {
        load(UInt32.self, at: JttyShmLayout.structSizeOffset)
    }

    var serverState: JttyShmLayout.ServerState? {
        JttyShmLayout.ServerState(rawValue: load(Int32.self, at: JttyShmLayout.serverStateOffset))
    }

    var heartbeat: UInt32 {
        load(UInt32.self, at: JttyShmLayout.heartbeatOffset)
    }

    var serverPid: Int32 {
        load(Int32.self, at: JttyShmLayout.serverPidOffset)
    }

    var decoderRestarts: Int32 {
        load(Int32.self, at: JttyShmLayout.decoderRestartsOffset)
    }

    var droppedSamples: Int64 {
        load(Int64.self, at: JttyShmLayout.rxDroppedOffset)
    }

    var resultsWritten: Int64 {
        load(Int64.self, at: JttyShmLayout.resultsWrittenOffset)
    }

    /// Header complete, protocol matches, server loop running.
    var isReady: Bool {
        magic == JttyShmLayout.magic && version == JttyShmLayout.version
            && structSize == UInt32(JttyShmLayout.totalSize) && serverState == .running
    }

    // MARK: Receive

    /// Total 12 kHz samples handed to the helper so far.
    var totalSamplesWritten: Int64 {
        rxLock.withLock { rxWritten }
    }

    /// Open an existing segment `/<name>` read-write. Throws if it does not
    /// exist yet (the server creates it) or carries a different protocol.
    static func open(name: String) throws -> JttySidecarClient {
        guard let shmOpen = shmOpenSymbol else {
            throw ClientError.unavailable("shm_open symbol not found")
        }
        let fd = shmOpen("/" + name, O_RDWR)
        guard fd >= 0 else {
            throw ClientError.unavailable(String(cString: strerror(errno)))
        }
        defer { Darwin.close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0 else {
            throw ClientError.unavailable(String(cString: strerror(errno)))
        }
        // The server creates the object and then sizes it; mapping an
        // unsized object and touching it is a SIGBUS.
        let size = Int(info.st_size)
        guard size >= JttyShmLayout.totalSize else {
            throw ClientError.tooSmall(size)
        }
        guard let pointer = mmap(nil, JttyShmLayout.totalSize, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0),
              pointer != UnsafeMutableRawPointer(bitPattern: -1)
        else {
            throw ClientError.unavailable("mmap: \(String(cString: strerror(errno)))")
        }
        let client = JttySidecarClient(
            name: name, base: pointer, mappedSize: JttyShmLayout.totalSize, unmapOnClose: true
        )
        // Magic is written last; zero means "not ready", not "wrong protocol".
        if client.magic != 0,
           client.magic != JttyShmLayout.magic || client.version != JttyShmLayout.version
           || client.structSize != UInt32(JttyShmLayout.totalSize)
        {
            let mismatch = ClientError.protocolMismatch(version: client.version, size: client.structSize)
            client.close()
            throw mismatch
        }
        return client
    }

    func close() {
        guard !closed else {
            return
        }
        closed = true
        if unmapOnClose {
            munmap(base, mappedSize)
        }
    }

    // MARK: Control

    /// Steer the decoder: search bounds, preferred channel and its tolerance.
    func setSearch(nfa: Int32 = 200, nfb: Int32 = 3_000, f0: Float = 1_500, ftol: Float = 500) {
        store(nfa, at: JttyShmLayout.nfaOffset)
        store(nfb, at: JttyShmLayout.nfbOffset)
        store(f0, at: JttyShmLayout.f0Offset)
        store(ftol, at: JttyShmLayout.ftolOffset)
    }

    func send(command: JttyShmLayout.Command) {
        store(command.rawValue, at: JttyShmLayout.commandOffset)
    }

    /// Append 12 kHz mono samples to the receive ring. Safe to call from the
    /// audio thread; publishes the new count after the samples are in place.
    func writeReceiveAudio(_ samples: UnsafeBufferPointer<Int16>) {
        guard let source = samples.baseAddress, !samples.isEmpty, !closed else {
            return
        }
        rxLock.withLock {
            let ring = JttyShmLayout.rxRingSamples
            var written = rxWritten
            var remaining = samples.count
            var cursor = source
            while remaining > 0 {
                let index = Int(written % Int64(ring))
                let chunk = min(remaining, ring - index)
                (base + JttyShmLayout.rxPcmOffset + index * 2).copyMemory(from: cursor, byteCount: chunk * 2)
                cursor += chunk
                remaining -= chunk
                written += Int64(chunk)
            }
            OSMemoryBarrier()
            store(written, at: JttyShmLayout.rxWrittenOffset)
            rxWritten = written
        }
    }

    /// Results published since the last call, oldest first. If the client fell
    /// more than a ring behind, the overwritten entries are skipped.
    func drainResults() -> [JttyDecodeResult] {
        let written = resultsWritten
        guard written > resultsRead else {
            return []
        }
        OSMemoryBarrier()
        var start = resultsRead
        if written - start > Int64(JttyShmLayout.resultRing) {
            start = written - Int64(JttyShmLayout.resultRing)
        }
        var results: [JttyDecodeResult] = []
        results.reserveCapacity(Int(written - start))
        for index in start ..< written {
            results.append(readResult(slot: Int(index % Int64(JttyShmLayout.resultRing))))
        }
        resultsRead = written
        return results
    }

    // MARK: Transmit

    /// Render `text` to audio. One request at a time; resolves when the helper
    /// has filled the transmit buffer (typically well under a second).
    func transmit(
        text: String,
        profile: JttyExchangeProfile,
        sampleRate: Int,
        f0: Float,
        chained: Bool,
        timeout: Duration = .seconds(10)
    ) async throws -> JttyTxRendering {
        guard !closed, serverState == .running else {
            throw ClientError.notRunning
        }
        var bytes = [UInt8](repeating: 0, count: JttyShmLayout.textLength)
        for (index, byte) in text.utf8.prefix(JttyShmLayout.textLength - 1).enumerated() {
            bytes[index] = byte
        }
        bytes.withUnsafeBytes { raw in
            (base + JttyShmLayout.txRequestTextOffset).copyMemory(from: raw.baseAddress!, byteCount: raw.count)
        }
        store(profile.sidecarValue, at: JttyShmLayout.txRequestProfileOffset)
        store(Int32(sampleRate), at: JttyShmLayout.txRequestSampleRateOffset)
        store(Int32(chained ? 1 : 0), at: JttyShmLayout.txRequestChainedOffset)
        store(f0, at: JttyShmLayout.txRequestF0Offset)
        OSMemoryBarrier()
        txSeq &+= 1
        if txSeq == 0 {
            txSeq = 1
        }
        let seq = txSeq
        store(seq, at: JttyShmLayout.txRequestSeqOffset)

        let deadline = ContinuousClock.now + timeout
        while load(Int32.self, at: JttyShmLayout.txResponseSeqDoneOffset) != seq {
            guard ContinuousClock.now < deadline, !closed else {
                throw ClientError.transmitTimeout
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        OSMemoryBarrier()
        let status = JttyShmLayout.TxStatus(rawValue: load(Int32.self, at: JttyShmLayout.txResponseStatusOffset))
            ?? .failed
        guard status == .ok else {
            throw ClientError.transmitRejected(status)
        }
        let count = min(
            max(0, Int(load(Int32.self, at: JttyShmLayout.txResponseSamplesOffset))), JttyShmLayout.txMaxSamples
        )
        let frames = Int(load(Int32.self, at: JttyShmLayout.txResponseFramesOffset))
        let canonical = string(at: JttyShmLayout.txResponseTextOffset, length: JttyShmLayout.textLength)
        let samples = [Int16](unsafeUninitializedCapacity: count) { buffer, initialized in
            if count > 0 {
                UnsafeMutableRawPointer(buffer.baseAddress!)
                    .copyMemory(from: base + JttyShmLayout.txPcmOffset, byteCount: count * 2)
            }
            initialized = count
        }
        return JttyTxRendering(canonicalText: canonical, frames: frames, sampleRate: sampleRate, samples: samples)
    }

    // MARK: Private

    private typealias ShmOpenFunction = @convention(c) (UnsafePointer<CChar>, Int32) -> Int32

    private static let shmOpenSymbol: ShmOpenFunction? = {
        guard let handle = dlopen(nil, RTLD_NOW), let symbol = dlsym(handle, "shm_open") else {
            logger.error("dlsym(shm_open) failed")
            return nil
        }
        return unsafeBitCast(symbol, to: ShmOpenFunction.self)
    }()

    private let base: UnsafeMutableRawPointer
    private let mappedSize: Int
    private let unmapOnClose: Bool
    private let rxLock = NSLock()
    private var rxWritten: Int64
    private var resultsRead: Int64
    private var txSeq: Int32
    private var closed = false

    private func load<T>(_: T.Type, at offset: Int) -> T {
        base.loadUnaligned(fromByteOffset: offset, as: T.self)
    }

    private func store<T>(_ value: T, at offset: Int) {
        base.storeBytes(of: value, toByteOffset: offset, as: T.self)
    }

    private func string(at offset: Int, length: Int) -> String {
        let bytes = UnsafeRawBufferPointer(start: base + offset, count: length)
        let end = bytes.firstIndex(of: 0) ?? length
        return String(decoding: bytes[..<end], as: UTF8.self)
            .trimmingCharacters(in: .whitespaces)
    }

    private func readResult(slot: Int) -> JttyDecodeResult {
        let offset = JttyShmLayout.resultsOffset + slot * JttyShmLayout.resultStride
        return JttyDecodeResult(
            messageId: load(Int64.self, at: offset + JttyShmLayout.resultMessageIdOffset),
            startSample: load(Int64.self, at: offset + JttyShmLayout.resultStartSampleOffset),
            frequency: load(Float.self, at: offset + JttyShmLayout.resultFrequencyOffset),
            isComplete: load(Int32.self, at: offset + JttyShmLayout.resultEomOffset) != 0,
            text: string(at: offset + JttyShmLayout.resultTextOffset, length: JttyShmLayout.textLength)
        )
    }
}
