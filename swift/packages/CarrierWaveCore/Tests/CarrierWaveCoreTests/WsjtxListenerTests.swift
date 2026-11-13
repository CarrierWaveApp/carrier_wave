//
//  WsjtxListenerTests.swift
//  CarrierWaveCoreTests
//
//  End-to-end gate for the WSJT-X UniFFI surface (CAR-281). A listener bound
//  through `WsjtxApi.start` must deliver a real loopback UDP datagram, decoded,
//  to a Swift `WsjtxListenerDelegate`, and the store-mapping helpers must turn
//  the event into an `FfiQso` the app can `upsertQso`. Wiring the delegate to
//  `FieldStore` + the UI is CAR-282.
//
//  Needs the staged xcframework (`rust/cw-core/scripts/build-xcframework.sh`).
//  The socket test skips (prints + returns) when the test host can't bind or
//  send on loopback, so sandboxed runners don't fail on it.
//

import CarrierWaveCwFfi
import Foundation
import Testing

struct WsjtxListenerTests {
    // MARK: Internal

    /// 2026-03-14T18:30:15Z — the QSO time in every sample below.
    static let timeOn: Int64 = 1_773_513_015
    /// 2026-03-14T18:31:00Z.
    static let timeOff: Int64 = 1_773_513_060

    @Test("listener delivers a decoded QSOLogged datagram to the Swift delegate")
    func listenerDeliversQsoLoggedOverUdp() async throws {
        let api = WsjtxApi()
        let delegate = StreamingDelegate()
        #expect(!api.isRunning())
        #expect(api.localPort() == nil)

        let port: UInt16
        do {
            port = try await api.start(host: "127.0.0.1", port: 0, delegate: delegate)
        } catch {
            print("WsjtxListenerTests: skipping — cannot bind a loopback UDP socket here: \(error)")
            return
        }
        defer { api.stop() }
        #expect(port != 0, "port 0 resolves to the OS-assigned port")
        #expect(api.isRunning())
        #expect(api.localPort() == port)

        do {
            try LoopbackUdp.send(WsjtxWire.sampleQsoLogged(), toPort: port)
        } catch {
            print("WsjtxListenerTests: skipping — cannot send on loopback here: \(error)")
            return
        }

        // Bound the wait: after 5 s stop the listener, which ends the stream.
        let watchdog = Task {
            try await Task.sleep(for: .seconds(5))
            api.stop()
        }
        var received: FfiWsjtxMessage?
        for await message in delegate.messages {
            received = message
            break
        }
        watchdog.cancel()

        guard case let .qsoLogged(qso)? = received else {
            Issue.record("expected .qsoLogged, got \(String(describing: received))")
            return
        }
        #expect(qso.id == "WSJT-X")
        #expect(qso.dxCall == "K1ABC")
        #expect(qso.dxGrid == "FN42")
        #expect(qso.txFrequencyHz == 14_075_245)
        #expect(qso.mode == "FT8")
        #expect(qso.reportSent == "-10")
        #expect(qso.reportReceived == "-05")
        #expect(qso.txPower == "50")
        #expect(qso.comments == "Nice QSO")
        #expect(qso.name == "Bob")
        #expect(qso.dateTimeOn == Self.timeOn)
        #expect(qso.dateTimeOff == Self.timeOff)
        #expect(qso.myCall == "W6JY")
        #expect(qso.myGrid == "CM87xx")
        #expect(delegate.senders.first?.hasPrefix("127.0.0.1:") == true)

        // The event maps straight into a store QSO for CAR-282 to upsert.
        let mapped = try wsjtxMapQsoLogged(message: qso, context: Self.context)
        #expect(mapped.callsign == "K1ABC")
        #expect(mapped.band == "20m")
        #expect(mapped.mode == "FT8")
        #expect(mapped.freqKhz == 14_075.245)
        #expect(mapped.qsoDate == Self.timeOn)
        #expect(mapped.stationCallsign == "W6JY")
        #expect(mapped.importSourceRawValue == "wsjtx")
        #expect(mapped.loggingSessionId == "session-1")
        #expect(mapped.dirty)

        // stop() ends the loop with exactly one onStopped and is idempotent.
        api.stop()
        #expect(!api.isRunning())
        #expect(api.localPort() == nil)
        let drain = Task {
            try await Task.sleep(for: .seconds(5))
            delegate.finishForTimeout()
        }
        for await _ in delegate.messages {}
        drain.cancel()
        api.stop()
        #expect(delegate.stopCount == 1)
        #expect(delegate.errors.isEmpty)
    }

    @Test("decode + store mapping work without a socket")
    func decodeAndMapWithoutSocket() throws {
        #expect(wsjtxDefaultPort() == 2237)

        let message = try wsjtxDecodeDatagram(datagram: WsjtxWire.sampleQsoLogged())
        guard case let .qsoLogged(qso) = message else {
            Issue.record("expected .qsoLogged, got \(message)")
            return
        }
        #expect(qso.dxCall == "K1ABC")
        #expect(qso.dateTimeOn == Self.timeOn)

        let close = try wsjtxDecodeDatagram(datagram: WsjtxWire.header(kind: 6, id: "WSJT-X"))
        #expect(close == .close(id: "WSJT-X"))

        #expect(throws: WsjtxError.self) {
            try wsjtxDecodeDatagram(datagram: Data([0, 0, 0, 0, 0, 0, 0, 3, 0, 0, 0, 0]))
        }

        // QSOLogged and LoggedADIF for the same QSO map to the same store id,
        // so upserting both collapses into one row.
        let fromLogged = try wsjtxMapQsoLogged(message: qso, context: Self.context)
        let fromAdif = try wsjtxMapLoggedAdif(
            message: FfiWsjtxLoggedAdif(id: "WSJT-X", adif: Self.sampleAdif),
            context: Self.context
        )
        #expect(fromAdif.count == 1)
        #expect(fromAdif.first?.id == fromLogged.id)
        #expect(fromAdif.first?.rawAdif?.contains("<call:5>K1ABC") == true)
        // 18:30:15 falls in the 18:30:00 two-minute bucket.
        #expect(wsjtxDedupKey(qso: fromLogged) == "K1ABC|20M|FT8|1773513000")

        // Import errors arrive as typed `WsjtxError`s.
        var blank = qso
        blank.dxCall = "  "
        do {
            _ = try wsjtxMapQsoLogged(message: blank, context: Self.context)
            Issue.record("expected MissingCallsign")
        } catch WsjtxError.MissingCallsign {
            // expected
        }
    }

    // MARK: Private

    private static let context = FfiWsjtxImportContext(
        stationCallsign: "W6JY",
        importedAt: 1_800_000_000,
        loggingSessionId: "session-1"
    )

    /// The record WSJT-X writes for the QSO in `WsjtxWire.sampleQsoLogged`.
    private static let sampleAdif = "WSJT-X ADIF Export<eoh>\n"
        + "<call:5>K1ABC <gridsquare:4>FN42 <mode:3>FT8 <rst_sent:3>-10 <rst_rcvd:3>-05 "
        + "<qso_date:8>20260314 <time_on:6>183015 <band:3>20m <freq:9>14.075245 "
        + "<station_callsign:4>W6JY <my_gridsquare:6>CM87xx <tx_pwr:2>50 <eor>"
}

// MARK: - Delegate

/// Collects delegate callbacks onto an `AsyncStream` the test awaits. UniFFI
/// calls these on a Rust runtime thread.
private final class StreamingDelegate: WsjtxListenerDelegate, @unchecked Sendable {
    // MARK: Lifecycle

    init() {
        (messages, continuation) = AsyncStream<FfiWsjtxMessage>.makeStream()
    }

    // MARK: Internal

    let messages: AsyncStream<FfiWsjtxMessage>

    var errors: [String] { lock.withLock { _errors } }
    var senders: [String] { lock.withLock { _senders } }
    var stopCount: Int { lock.withLock { _stopCount } }

    func onMessage(message: FfiWsjtxMessage, from: String) {
        lock.withLock { _senders.append(from) }
        continuation.yield(message)
    }

    func onError(message: String) {
        lock.withLock { _errors.append(message) }
    }

    func onStopped() {
        lock.withLock { _stopCount += 1 }
        continuation.finish()
    }

    /// Ends the stream if `onStopped` never arrives, so a broken listener
    /// fails the assertions instead of hanging the test.
    func finishForTimeout() {
        continuation.finish()
    }

    // MARK: Private

    private let continuation: AsyncStream<FfiWsjtxMessage>.Continuation
    private let lock = NSLock()
    private var _errors: [String] = []
    private var _senders: [String] = []
    private var _stopCount = 0
}

// MARK: - Wire encoder

/// Minimal WSJT-X `QDataStream` encoder (big-endian), independent of the
/// Rust decoder, mirroring cw-net's test helpers.
private enum WsjtxWire {
    static let magic: UInt32 = 0xADBC_CBDA

    static func header(kind: UInt32, id: String) -> Data {
        var data = Data()
        putU32(&data, magic)
        putU32(&data, 3) // schema
        putU32(&data, kind)
        putString(&data, id)
        return data
    }

    /// Type 5 QSOLogged for K1ABC on 20 m FT8 at `WsjtxListenerTests.timeOn`.
    static func sampleQsoLogged() -> Data {
        var data = header(kind: 5, id: "WSJT-X")
        putDateTime(&data, epochSeconds: WsjtxListenerTests.timeOff)
        putString(&data, "K1ABC") // dx call
        putString(&data, "FN42") // dx grid
        putU64(&data, 14_075_245) // tx frequency Hz
        putString(&data, "FT8") // mode
        putString(&data, "-10") // report sent
        putString(&data, "-05") // report received
        putString(&data, "50") // tx power
        putString(&data, "Nice QSO") // comments
        putString(&data, "Bob") // name
        putDateTime(&data, epochSeconds: WsjtxListenerTests.timeOn)
        putString(&data, "") // operator call
        putString(&data, "W6JY") // my call
        putString(&data, "CM87xx") // my grid
        putString(&data, "") // exchange sent
        putString(&data, "") // exchange received
        putString(&data, "") // ADIF propagation mode
        return data
    }

    static func putU32(_ data: inout Data, _ value: UInt32) {
        withUnsafeBytes(of: value.bigEndian) { data.append(contentsOf: $0) }
    }

    static func putU64(_ data: inout Data, _ value: UInt64) {
        withUnsafeBytes(of: value.bigEndian) { data.append(contentsOf: $0) }
    }

    static func putString(_ data: inout Data, _ string: String) {
        let bytes = Array(string.utf8)
        putU32(&data, UInt32(bytes.count))
        data.append(contentsOf: bytes)
    }

    /// Qt `QDateTime` in UTC (timespec 1): Julian day (i64) + ms since
    /// midnight (u32) + timespec byte. JDN 2440588 == 1970-01-01.
    static func putDateTime(_ data: inout Data, epochSeconds: Int64) {
        let days = epochSeconds / 86_400
        let seconds = epochSeconds % 86_400
        withUnsafeBytes(of: (days + 2_440_588).bigEndian) { data.append(contentsOf: $0) }
        putU32(&data, UInt32(seconds) * 1_000)
        data.append(1)
    }
}

// MARK: - Loopback UDP

private enum LoopbackUdp {
    enum SendError: Error {
        case socket(Int32)
        case sendto(Int32)
        case shortWrite(Int)
    }

    /// Send one datagram to `127.0.0.1:port` over a throwaway BSD socket.
    static func send(_ datagram: Data, toPort port: UInt16) throws {
        let fd = socket(AF_INET, SOCK_DGRAM, 0)
        guard fd >= 0 else { throw SendError.socket(errno) }
        defer { close(fd) }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        let sent = datagram.withUnsafeBytes { bytes -> Int in
            withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { generic in
                    sendto(fd, bytes.baseAddress, bytes.count, 0, generic, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        guard sent >= 0 else { throw SendError.sendto(errno) }
        guard sent == datagram.count else { throw SendError.shortWrite(sent) }
    }
}
