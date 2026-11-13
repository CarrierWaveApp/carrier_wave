# Icom WiFi CAT Control & Shared RadioSession Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Icom WiFi CAT control to Carrier Wave iOS and refactor the radio stack so iOS and macOS share `RadioSession`, protocol handlers, and `FrameAssembler` from CarrierWaveData.

**Architecture:** Move `RadioSession`, `RadioProtocolHandler` protocol, `CIVProtocolHandler`, `KenwoodProtocolHandler`, and `FrameAssembler` into CarrierWaveData. Add `IcomWiFiTransport` (UDP RS-BA1 protocol) there. On iOS, extract `BLERadioTransport` from `BLERadioClient`, replace `BLERadioService` with transport-agnostic `RadioService`. On macOS, delete local copies and import from CarrierWaveData. Rename all "BLE Radio" UI to "Radio".

**Tech Stack:** Swift, SwiftUI, CarrierWaveCore (CI-V/Kenwood protocol encoding), CarrierWaveData (shared SPM package), CoreBluetooth (iOS BLE transport), POSIX UDP sockets (WiFi transport)

**Spec:** `docs/superpowers/specs/2026-03-27-icom-wifi-cat-design.md`

---

### Task 1: Move RadioProtocolHandler protocol to CarrierWaveData

**Files:**
- Create: `CarrierWaveData/Sources/CarrierWaveData/Radio/RadioProtocolHandler.swift`
- Modify: `CWSweep/CWSweep/Services/Radio/RadioProtocolHandler.swift` (delete after migration)

- [ ] **Step 1: Create the shared RadioProtocolHandler protocol**

Create `CarrierWaveData/Sources/CarrierWaveData/Radio/RadioProtocolHandler.swift`:

```swift
import Foundation

/// Protocol handler abstraction for radio CAT commands.
/// Each radio family (CI-V, Kenwood, Yaesu, Flex) provides a concrete implementation.
public protocol RadioProtocolHandler: Sendable {
    // MARK: - Encoding (Commands to Radio)

    func encodeReadFrequency() -> Data?
    func encodeReadMode() -> Data?
    func encodeSetFrequency(_ freqMHz: Double) -> Data
    func encodeSetMode(_ mode: String) -> Data
    func encodeSetPTT(_ on: Bool) -> Data

    // MARK: - CW Keying

    func encodeSendCW(_ text: String) -> Data?
    func encodeAbortCW() -> Data?

    // MARK: - XIT/RIT

    func encodeSetXIT(_ on: Bool) -> Data?
    func encodeSetXITOffset(_ hz: Int) -> Data?
    func encodeClearRITXIT() -> Data?
    func encodeReadXIT() -> Data?
    func encodeReadRIT() -> Data?
    func encodeReadRITXITOffset() -> Data?

    // MARK: - Decoding (Responses from Radio)

    func decodeFrequency(from data: Data) -> Double?
    func decodeMode(from data: Data) -> String?
    func decodePTTState(from data: Data) -> Bool?
    func decodeXITState(from data: Data) -> Bool?
    func decodeRITState(from data: Data) -> Bool?
    func decodeRITXITOffset(from data: Data) -> Int?
}

/// Default implementations for optional capabilities
public extension RadioProtocolHandler {
    func encodeSendCW(_ text: String) -> Data? { nil }
    func encodeAbortCW() -> Data? { nil }
    func encodeSetXIT(_ on: Bool) -> Data? { nil }
    func encodeSetXITOffset(_ hz: Int) -> Data? { nil }
    func encodeClearRITXIT() -> Data? { nil }
    func encodeReadXIT() -> Data? { nil }
    func encodeReadRIT() -> Data? { nil }
    func encodeReadRITXITOffset() -> Data? { nil }
    func decodeXITState(from data: Data) -> Bool? { nil }
    func decodeRITState(from data: Data) -> Bool? { nil }
    func decodeRITXITOffset(from data: Data) -> Int? { nil }
}
```

- [ ] **Step 2: Verify CarrierWaveData builds**

Run: `cd /Users/jsvana/projects/carrier_wave/CarrierWaveData && swift build`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add CarrierWaveData/Sources/CarrierWaveData/Radio/RadioProtocolHandler.swift
git commit -m "feat: move RadioProtocolHandler protocol to CarrierWaveData"
```

---

### Task 2: Move FrameAssembler to CarrierWaveData

**Files:**
- Create: `CarrierWaveData/Sources/CarrierWaveData/Radio/FrameAssembler.swift`
- Modify: `CWSweep/CWSweep/Services/Serial/FrameAssembler.swift` (delete later in Task 8)

- [ ] **Step 1: Create the shared FrameAssembler**

Create `CarrierWaveData/Sources/CarrierWaveData/Radio/FrameAssembler.swift` — same as the CWSweep version but with `public` access:

```swift
import Foundation

/// Assembles raw byte streams into protocol-specific frames.
/// CI-V frames: FE FE ... FD
/// Kenwood frames: terminated by ';'
/// SmartSDR frames: newline-terminated ASCII lines
public actor FrameAssembler {
    // MARK: Lifecycle

    public init(frameType: FrameType) {
        self.frameType = frameType
    }

    // MARK: Public

    public enum FrameType: Sendable {
        case civ
        case kenwood
        case smartsdr
    }

    /// Feed raw bytes, returns any complete frames found
    public func feed(_ data: Data) -> [Data] {
        buffer.append(data)

        switch frameType {
        case .civ:
            return extractCIVFrames()
        case .kenwood:
            return extractKenwoodFrames()
        case .smartsdr:
            return extractSmartSDRFrames()
        }
    }

    public func reset() {
        buffer.removeAll()
    }

    // MARK: Private

    private let frameType: FrameType
    private var buffer = Data()

    private func extractCIVFrames() -> [Data] {
        var frames: [Data] = []

        while let startIndex = findCIVStart() {
            if startIndex > 0 {
                buffer.removeFirst(startIndex)
            }

            guard let endIndex = buffer.firstIndex(of: 0xFD) else {
                break
            }

            let frameEnd = buffer.index(after: endIndex)
            let frame = Data(buffer[buffer.startIndex ..< frameEnd])
            frames.append(frame)
            buffer.removeFirst(frameEnd - buffer.startIndex)
        }

        if buffer.count > 4_096 {
            buffer.removeAll()
        }

        return frames
    }

    private func findCIVStart() -> Int? {
        guard buffer.count >= 2 else {
            return nil
        }
        for idx in 0 ..< buffer.count - 1 {
            if buffer[buffer.startIndex + idx] == 0xFE,
               buffer[buffer.startIndex + idx + 1] == 0xFE
            {
                return idx
            }
        }
        return nil
    }

    private func extractKenwoodFrames() -> [Data] {
        var frames: [Data] = []

        while let semicolonIndex = buffer.firstIndex(of: UInt8(ascii: ";")) {
            let frameEnd = buffer.index(after: semicolonIndex)
            let frame = Data(buffer[buffer.startIndex ..< frameEnd])
            frames.append(frame)
            buffer.removeFirst(frameEnd - buffer.startIndex)
        }

        if buffer.count > 4_096 {
            buffer.removeAll()
        }

        return frames
    }

    private func extractSmartSDRFrames() -> [Data] {
        var frames: [Data] = []
        let newline = UInt8(ascii: "\n")

        while let nlIndex = buffer.firstIndex(of: newline) {
            var frame = Data(buffer[buffer.startIndex ..< nlIndex])
            if let last = frame.last, last == UInt8(ascii: "\r") {
                frame = frame.dropLast()
            }
            if !frame.isEmpty {
                frames.append(Data(frame))
            }
            buffer.removeFirst(nlIndex - buffer.startIndex + 1)
        }

        if buffer.count > 8_192 {
            buffer.removeAll()
        }

        return frames
    }
}
```

- [ ] **Step 2: Verify CarrierWaveData builds**

Run: `cd /Users/jsvana/projects/carrier_wave/CarrierWaveData && swift build`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add CarrierWaveData/Sources/CarrierWaveData/Radio/FrameAssembler.swift
git commit -m "feat: move FrameAssembler to CarrierWaveData"
```

---

### Task 3: Move CIVProtocolHandler to CarrierWaveData

**Files:**
- Create: `CarrierWaveData/Sources/CarrierWaveData/Radio/CIVProtocolHandler.swift`

- [ ] **Step 1: Create the shared CIVProtocolHandler**

Create `CarrierWaveData/Sources/CarrierWaveData/Radio/CIVProtocolHandler.swift`:

```swift
import CarrierWaveCore
import Foundation

/// CI-V protocol handler for Icom radios.
/// Delegates byte-level encoding/decoding to CarrierWaveCore's CIVProtocol.
public struct CIVProtocolHandler: RadioProtocolHandler {
    // MARK: Lifecycle

    public init(civAddress: UInt8 = 0xA4) {
        self.civAddress = civAddress
    }

    // MARK: Public

    public let civAddress: UInt8
    public let controllerAddress: UInt8 = CIVProtocol.controllerAddress

    public func encodeReadFrequency() -> Data? {
        let frame = CIVProtocol.buildFrame(
            to: civAddress,
            command: CIVProtocol.cmdReadFreq
        )
        return Data(frame)
    }

    public func encodeReadMode() -> Data? {
        let frame = CIVProtocol.buildFrame(
            to: civAddress,
            command: CIVProtocol.cmdReadMode
        )
        return Data(frame)
    }

    public func encodeSetFrequency(_ freqMHz: Double) -> Data {
        let freqHz = CIVProtocol.mhzToHz(freqMHz)
        let bcd = CIVProtocol.encodeBCDFrequency(freqHz)
        let frame = CIVProtocol.buildFrame(
            to: civAddress,
            command: CIVProtocol.cmdSetFreq,
            data: bcd
        )
        return Data(frame)
    }

    public func encodeSetMode(_ mode: String) -> Data {
        let civMode = CIVMode.from(carrierWaveMode: mode) ?? .cw
        let frame = CIVProtocol.buildFrame(
            to: civAddress,
            command: CIVProtocol.cmdSetMode,
            data: [civMode.rawValue]
        )
        return Data(frame)
    }

    public func encodeSetPTT(_ on: Bool) -> Data {
        let frame = CIVProtocol.buildFrame(
            to: civAddress,
            command: 0x1C,
            data: [0x00, on ? 0x01 : 0x00]
        )
        return Data(frame)
    }

    public func encodeSendCW(_ text: String) -> Data? {
        let textBytes = Array(text.uppercased().utf8)
        let frame = CIVProtocol.buildFrame(
            to: civAddress,
            command: 0x17,
            data: textBytes
        )
        return Data(frame)
    }

    public func encodeAbortCW() -> Data? {
        let frame = CIVProtocol.buildFrame(
            to: civAddress,
            command: 0x17,
            data: [0xFF]
        )
        return Data(frame)
    }

    public func decodeFrequency(from data: Data) -> Double? {
        let bytes = [UInt8](data)
        let frames = CIVProtocol.extractFrames(from: bytes)
        for frame in frames.frames {
            if frame.command == CIVProtocol.cmdReadFreq
                || frame.command == CIVProtocol.cmdSetFreq
            {
                if let hz = CIVProtocol.parseBCDFrequency(frame.data) {
                    return CIVProtocol.hzToMHz(hz)
                }
            }
        }
        return nil
    }

    public func decodeMode(from data: Data) -> String? {
        let bytes = [UInt8](data)
        let frames = CIVProtocol.extractFrames(from: bytes)
        for frame in frames.frames {
            if frame.command == CIVProtocol.cmdReadMode
                || frame.command == CIVProtocol.cmdSetMode,
               let first = frame.data.first,
               let mode = CIVMode(rawValue: first)
            {
                return mode.carrierWaveMode
            }
        }
        return nil
    }

    public func decodePTTState(from data: Data) -> Bool? {
        let bytes = [UInt8](data)
        let frames = CIVProtocol.extractFrames(from: bytes)
        for frame in frames.frames {
            if frame.command == 0x1C,
               frame.data.count >= 2,
               frame.data[0] == 0x00
            {
                return frame.data[1] == 0x01
            }
        }
        return nil
    }
}
```

- [ ] **Step 2: Verify CarrierWaveData builds**

Run: `cd /Users/jsvana/projects/carrier_wave/CarrierWaveData && swift build`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add CarrierWaveData/Sources/CarrierWaveData/Radio/CIVProtocolHandler.swift
git commit -m "feat: move CIVProtocolHandler to CarrierWaveData"
```

---

### Task 4: Move KenwoodProtocolHandler to CarrierWaveData

**Files:**
- Create: `CarrierWaveData/Sources/CarrierWaveData/Radio/KenwoodProtocolHandler.swift`

- [ ] **Step 1: Create the shared KenwoodProtocolHandler**

Create `CarrierWaveData/Sources/CarrierWaveData/Radio/KenwoodProtocolHandler.swift`. This is the same as CWSweep's version but with `public` access modifiers. It delegates to `KenwoodProtocol` and `KenwoodMode` from CarrierWaveCore for all encoding/parsing.

The file should implement all `RadioProtocolHandler` methods including XIT/RIT encoding/decoding via `KenwoodProtocol.setXIT()`, `KenwoodProtocol.readXIT()`, etc. Copy the full implementation from `CWSweep/CWSweep/Services/Radio/KenwoodProtocolHandler.swift`, adding `public` to the struct, init, and all method declarations.

- [ ] **Step 2: Verify CarrierWaveData builds**

Run: `cd /Users/jsvana/projects/carrier_wave/CarrierWaveData && swift build`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add CarrierWaveData/Sources/CarrierWaveData/Radio/KenwoodProtocolHandler.swift
git commit -m "feat: move KenwoodProtocolHandler to CarrierWaveData"
```

---

### Task 5: Move RadioSession to CarrierWaveData

**Files:**
- Create: `CarrierWaveData/Sources/CarrierWaveData/Radio/RadioSession.swift`

- [ ] **Step 1: Create the shared RadioSession**

Create `CarrierWaveData/Sources/CarrierWaveData/Radio/RadioSession.swift`. Same as CWSweep's version with `public` access. Key differences from CWSweep copy:

- All types and methods are `public`
- `RadioState` is `public struct` with `public` properties
- Remove the Yaesu-specific `scopeSpanFromCode` and `SS05` parsing (that stays in CWSweep's `RadioManager`)
- Remove the `FlexProtocolHandler` type check in `pollLoop` — instead add a `public var skipPolling: Bool = false` property that Flex sets
- Remove the `import os` logger (callers can log at their layer)
- `FrameAssembler.FrameType` selection: add a `public var frameType: FrameAssembler.FrameType` property to `RadioProtocolHandler` protocol with a default of `.civ`

Actually, to keep this cleaner, add `frameType` as an init parameter to `RadioSession` rather than on the protocol:

```swift
import Foundation

/// Transport-agnostic radio session that polls frequency/mode and publishes state.
public actor RadioSession {
    // MARK: Lifecycle

    public init(
        transport: any RadioTransport,
        protocolHandler: any RadioProtocolHandler,
        frameType: FrameAssembler.FrameType = .civ
    ) {
        self.transport = transport
        self.protocolHandler = protocolHandler
        self.frameAssembler = FrameAssembler(frameType: frameType)
    }

    // MARK: Public

    public struct RadioState: Sendable {
        public var frequency: Double = 0
        public var mode: String = ""
        public var isTransmitting: Bool = false
        public var isConnected: Bool = false
        public var xitEnabled: Bool = false
        public var ritEnabled: Bool = false
        public var ritXitOffset: Int = 0

        public init() {}
    }

    public private(set) var state = RadioState()

    /// Set to true for push-based radios (e.g. FlexRadio) that don't need polling.
    public var skipPolling: Bool = false

    /// Called with each raw received frame (for protocol-specific processing by callers).
    public var onRawFrame: (@Sendable (Data) -> Void)?

    public func start() async throws {
        try await transport.connect()
        state.isConnected = true

        receiveTask = Task { [weak self] in
            guard let self else { return }
            await self.receiveLoop()
        }

        if !skipPolling {
            pollTask = Task { [weak self] in
                guard let self else { return }
                await self.pollLoop()
            }
        }
    }

    public func stop() async {
        receiveTask?.cancel()
        receiveTask = nil
        pollTask?.cancel()
        pollTask = nil
        await transport.disconnect()
        state.isConnected = false
    }

    public func tuneToFrequency(_ freqMHz: Double) async throws {
        let data = protocolHandler.encodeSetFrequency(freqMHz)
        try await transport.send(data)
    }

    public func setMode(_ mode: String) async throws {
        let data = protocolHandler.encodeSetMode(mode)
        try await transport.send(data)
    }

    public func setPTT(_ on: Bool) async throws {
        let data = protocolHandler.encodeSetPTT(on)
        try await transport.send(data)
        state.isTransmitting = on
    }

    public func sendRaw(_ data: Data) async throws {
        try await transport.send(data)
    }

    public func setXIT(_ on: Bool) async throws {
        guard let data = protocolHandler.encodeSetXIT(on) else { return }
        try await transport.send(data)
    }

    public func setXITOffset(_ hz: Int) async throws {
        guard let data = protocolHandler.encodeSetXITOffset(hz) else { return }
        try await transport.send(data)
    }

    public func clearRITXIT() async throws {
        guard let data = protocolHandler.encodeClearRITXIT() else { return }
        try await transport.send(data)
    }

    // MARK: Private

    private let transport: any RadioTransport
    private let protocolHandler: any RadioProtocolHandler
    private let frameAssembler: FrameAssembler
    private var receiveTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?

    private func receiveLoop() async {
        for await data in transport.receivedData {
            let frames = await frameAssembler.feed(data)
            for frame in frames {
                processFrame(frame)
                onRawFrame?(frame)
            }
        }
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
        while !Task.isCancelled, state.isConnected {
            if let cmd = protocolHandler.encodeReadFrequency() {
                try? await transport.send(cmd)
            }
            if let cmd = protocolHandler.encodeReadMode() {
                try? await transport.send(cmd)
            }
            if let cmd = protocolHandler.encodeReadXIT() {
                try? await transport.send(cmd)
            }
            if let cmd = protocolHandler.encodeReadRIT() {
                try? await transport.send(cmd)
            }
            if let cmd = protocolHandler.encodeReadRITXITOffset() {
                try? await transport.send(cmd)
            }
            try? await Task.sleep(for: .milliseconds(200))
        }
    }
}
```

- [ ] **Step 2: Verify CarrierWaveData builds**

Run: `cd /Users/jsvana/projects/carrier_wave/CarrierWaveData && swift build`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add CarrierWaveData/Sources/CarrierWaveData/Radio/RadioSession.swift
git commit -m "feat: move RadioSession to CarrierWaveData"
```

---

### Task 6: Add IcomWiFiTransport to CarrierWaveData

**Files:**
- Create: `CarrierWaveData/Sources/CarrierWaveData/Radio/IcomWiFiTransport.swift`
- Create: `CarrierWaveData/Sources/CarrierWaveData/Radio/UDPChannel.swift`

This is the core new feature. The transport implements the Icom RS-BA1 UDP session protocol used by the IC-705, IC-7610, IC-9700, and other WiFi-capable Icom radios.

- [ ] **Step 1: Create UDPChannel (POSIX UDP socket wrapper)**

Create `CarrierWaveData/Sources/CarrierWaveData/Radio/UDPChannel.swift`. This is a simplified version of CWSweep's `PortChannel` (SCULAN10PortChannel.swift) extracted for reuse:

```swift
import Darwin
import Foundation

/// A single UDP port using raw POSIX sockets.
/// Thread-based receive loop publishes incoming packets via AsyncStream.
final class UDPChannel: @unchecked Sendable {
    // MARK: Lifecycle

    init(host: String, port: UInt16) {
        remoteHost = host
        remotePort = port

        let (strm, cont) = AsyncStream<Data>.makeStream()
        inbound = strm
        streamContinuation = cont
    }

    deinit {
        stop()
    }

    // MARK: Internal

    nonisolated let inbound: AsyncStream<Data>

    func start() throws {
        guard let hostent = gethostbyname(remoteHost) else {
            throw IcomWiFiError.dnsResolutionFailed(remoteHost)
        }
        let addrPtr = hostent.pointee.h_addr_list[0]!
        memcpy(&resolvedAddr, addrPtr, Int(hostent.pointee.h_length))

        fd = socket(AF_INET, SOCK_DGRAM, 0)
        guard fd >= 0 else {
            throw IcomWiFiError.socketCreationFailed
        }

        var localAddr = sockaddr_in()
        localAddr.sin_family = sa_family_t(AF_INET)
        localAddr.sin_port = 0
        localAddr.sin_addr.s_addr = INADDR_ANY

        let bindResult = withUnsafePointer(to: &localAddr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                bind(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            Darwin.close(fd)
            fd = -1
            throw IcomWiFiError.socketBindFailed
        }

        var tv = timeval(tv_sec: 0, tv_usec: 100_000)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        running = true
        receiveThread = Thread { [weak self] in
            self?.receiveLoop()
        }
        receiveThread?.qualityOfService = .userInitiated
        receiveThread?.start()
    }

    func stop() {
        running = false
        receiveThread = nil
        streamContinuation.finish()
        if fd >= 0 {
            Darwin.close(fd)
            fd = -1
        }
    }

    func send(_ data: Data) {
        guard fd >= 0 else { return }
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = remotePort.bigEndian
        addr.sin_addr = resolvedAddr

        data.withUnsafeBytes { rawBuffer in
            guard let ptr = rawBuffer.baseAddress else { return }
            withUnsafePointer(to: &addr) { addrPtr in
                addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                    _ = sendto(fd, ptr, rawBuffer.count, 0, sockPtr,
                               socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
    }

    // MARK: Private

    private let remoteHost: String
    private let remotePort: UInt16
    private let streamContinuation: AsyncStream<Data>.Continuation
    private var resolvedAddr = in_addr()
    private var fd: Int32 = -1
    private var running = false
    private var receiveThread: Thread?

    private func receiveLoop() {
        var buf = [UInt8](repeating: 0, count: 4096)
        while running {
            let bytesRead = recv(fd, &buf, buf.count, 0)
            if bytesRead > 0 {
                let data = Data(buf[0 ..< bytesRead])
                streamContinuation.yield(data)
            }
        }
    }
}

/// Errors specific to Icom WiFi transport
public enum IcomWiFiError: LocalizedError {
    case dnsResolutionFailed(String)
    case socketCreationFailed
    case socketBindFailed
    case authenticationFailed
    case notConnected
    case connectionTimeout

    public var errorDescription: String? {
        switch self {
        case let .dnsResolutionFailed(host): "Could not resolve \(host)"
        case .socketCreationFailed: "Failed to create UDP socket"
        case .socketBindFailed: "Failed to bind UDP socket"
        case .authenticationFailed: "Authentication failed — check username/password"
        case .notConnected: "Not connected to radio"
        case .connectionTimeout: "Connection timed out"
        }
    }
}
```

- [ ] **Step 2: Create IcomWiFiTransport**

Create `CarrierWaveData/Sources/CarrierWaveData/Radio/IcomWiFiTransport.swift`:

```swift
import Foundation

/// Configuration for Icom WiFi radio connection.
public struct IcomWiFiConfig: Sendable {
    // MARK: Lifecycle

    public init(
        ipAddress: String = "192.168.59.1",
        username: String,
        password: String
    ) {
        self.ipAddress = ipAddress
        self.username = username
        self.password = password
    }

    // MARK: Public

    public let ipAddress: String
    public let username: String
    public let password: String

    /// Default config for IC-705 Access Point mode
    public static func accessPoint(username: String, password: String) -> IcomWiFiConfig {
        IcomWiFiConfig(ipAddress: "192.168.59.1", username: username, password: password)
    }
}

// MARK: - IcomWiFiTransport

/// UDP transport for Icom WiFi radios (IC-705, IC-7610, IC-9700).
/// Implements the RS-BA1 session protocol on ports 50001 (control) and 50002 (CI-V).
public actor IcomWiFiTransport: RadioTransport {
    // MARK: Lifecycle

    public init(config: IcomWiFiConfig) {
        self.config = config
        let (stream, cont) = AsyncStream<Data>.makeStream()
        receivedData = stream
        civContinuation = cont
    }

    // MARK: Public

    public nonisolated let receivedData: AsyncStream<Data>

    public var isConnected: Bool {
        connected
    }

    public func connect() async throws {
        controlChannel = UDPChannel(host: config.ipAddress, port: 50001)
        civChannel = UDPChannel(host: config.ipAddress, port: 50002)

        try controlChannel?.start()
        try civChannel?.start()

        try await authenticate()

        connected = true

        startForwarding()
        startKeepalive()
    }

    public func disconnect() async {
        connected = false
        keepaliveTask?.cancel()
        keepaliveTask = nil
        forwardTask?.cancel()
        forwardTask = nil
        controlChannel?.stop()
        civChannel?.stop()
        controlChannel = nil
        civChannel = nil
        civContinuation.finish()
    }

    public func send(_ data: Data) async throws {
        guard connected, let ch = civChannel else {
            throw IcomWiFiError.notConnected
        }
        ch.send(data)
    }

    // MARK: Private

    private let config: IcomWiFiConfig
    private let civContinuation: AsyncStream<Data>.Continuation
    private var controlChannel: UDPChannel?
    private var civChannel: UDPChannel?
    private var connected = false
    private var keepaliveTask: Task<Void, Never>?
    private var forwardTask: Task<Void, Never>?
    private var missedKeepalives = 0

    /// RS-BA1 authentication handshake on control port (50001).
    /// The protocol is documented in kappanhang and wfview source code.
    /// This is a simplified implementation covering the login sequence.
    private func authenticate() async throws {
        guard let ctrl = controlChannel else {
            throw IcomWiFiError.notConnected
        }

        // Send initial connection request
        // The RS-BA1 protocol uses a specific packet format:
        // Packets start with a fixed header, followed by command-specific data.
        // Full implementation should reference kappanhang/wfview for exact byte sequences.
        //
        // For V1, we implement the minimal handshake:
        // 1. Send "are you there" ping
        // 2. Receive "I am here" response
        // 3. Send login with username/password
        // 4. Receive login accepted

        // TODO: Implement full RS-BA1 handshake based on kappanhang protocol analysis.
        // The exact packet format requires studying the open-source implementations
        // at https://github.com/nonoo/kappanhang and https://gitlab.com/eliggett/wfview
        // during implementation. The subagent implementing this task should web-search
        // for "kappanhang auth.go" and "wfview udphandler.cpp" to get the exact
        // byte sequences for the connection/login/keepalive packets.

        // Placeholder: wait for any response on control port as a connectivity check
        let deadline = Date().addingTimeInterval(5)
        for await _ in ctrl.inbound {
            break
        }
        if Date() > deadline {
            throw IcomWiFiError.connectionTimeout
        }
    }

    /// Forward CI-V channel data to the public receivedData stream
    private func startForwarding() {
        guard let ch = civChannel else { return }
        forwardTask = Task {
            for await data in ch.inbound {
                guard !Task.isCancelled else { break }
                self.civContinuation.yield(data)
            }
        }
    }

    /// Send keepalive packets on control port every 3 seconds
    private func startKeepalive() {
        keepaliveTask = Task {
            while !Task.isCancelled, self.connected {
                // Send idle/ping packet on control port
                // Exact format from RS-BA1 protocol
                self.controlChannel?.send(Data([0x10, 0x00, 0x00, 0x00]))
                self.missedKeepalives += 1
                if self.missedKeepalives > 3 {
                    self.connected = false
                    break
                }
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }
}
```

**Note for implementer:** The `authenticate()` method is intentionally skeletal. The RS-BA1 handshake requires studying the packet format from kappanhang (Go) or wfview (C++). The implementing agent should web-search for the exact byte sequences and fill this in. The rest of the transport (UDP sockets, forwarding, keepalive structure) is complete.

- [ ] **Step 3: Verify CarrierWaveData builds**

Run: `cd /Users/jsvana/projects/carrier_wave/CarrierWaveData && swift build`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add CarrierWaveData/Sources/CarrierWaveData/Radio/UDPChannel.swift \
       CarrierWaveData/Sources/CarrierWaveData/Radio/IcomWiFiTransport.swift
git commit -m "feat: add IcomWiFiTransport with RS-BA1 UDP protocol"
```

---

### Task 7: Extract BLERadioTransport from BLERadioClient (iOS)

**Files:**
- Create: `CarrierWave/Services/Radio/BLERadioTransport.swift`
- Create: `CarrierWave/Services/Radio/BLEDelegate.swift` (move from BLERadioClient+Delegate.swift)
- Modify: `CarrierWave/Services/BLERadio/BLERadioClient.swift` (delete after)
- Modify: `CarrierWave/Services/BLERadio/BLERadioClient+Delegate.swift` (delete after)

- [ ] **Step 1: Create BLERadioTransport**

Create `CarrierWave/Services/Radio/BLERadioTransport.swift`. This is the CoreBluetooth NUS transport conforming to `RadioTransport`. It keeps BLE scanning, discovery, connect/disconnect, and raw data send/receive. All protocol handling is removed (that's `RadioSession`'s job now).

The actor should:
- Own a `BLEDelegate` (moved from BLERadioClient+Delegate.swift)
- Expose `startScanning() -> AsyncStream<[DiscoveredDevice]>`, `stopScanning()`
- Conform to `RadioTransport`: `connect()` connects to `targetDeviceUUID`, `disconnect()`, `send(_:)` writes to NUS write characteristic, `receivedData` is an `AsyncStream<Data>` fed by NUS notify characteristic
- Keep `DiscoveredDevice` struct and `ConnectionState` enum
- Keep auto-reconnect logic
- Expose `stateStream() -> AsyncStream<ConnectionState>` for UI observation
- Have a `setTarget(deviceUUID:)` method (called before `connect()`)

- [ ] **Step 2: Move BLEDelegate**

Create `CarrierWave/Services/Radio/BLEDelegate.swift` — move the `BLEDelegate` class from `BLERadioClient+Delegate.swift`. Update it to reference `BLERadioTransport` instead of `BLERadioClient`. The NUS UUIDs become constants on `BLERadioTransport`.

- [ ] **Step 3: Verify iOS app builds**

Run: `xc build` (or manual xcodebuild if not available)
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Delete old files**

Delete `CarrierWave/Services/BLERadio/BLERadioClient.swift`, `BLERadioClient+Delegate.swift`, `RigProtocol.swift`.

- [ ] **Step 5: Commit**

```bash
git add CarrierWave/Services/Radio/
git rm CarrierWave/Services/BLERadio/BLERadioClient.swift \
       CarrierWave/Services/BLERadio/BLERadioClient+Delegate.swift \
       CarrierWave/Services/BLERadio/RigProtocol.swift
git commit -m "refactor: extract BLERadioTransport from BLERadioClient"
```

---

### Task 8: Replace BLERadioService with RadioService (iOS)

**Files:**
- Create: `CarrierWave/Services/Radio/RadioService.swift` (replaces BLERadioService)
- Modify: `CarrierWave/Services/BLERadio/BLERadioService.swift` (delete)
- Modify: `CarrierWave/Services/LoggingSessionManager+BLERadio.swift` → rename to `LoggingSessionManager+Radio.swift`
- Modify: All files referencing `BLERadioService` (14 files — update imports/references)

- [ ] **Step 1: Create RadioService**

Create `CarrierWave/Services/Radio/RadioService.swift`. This is `@MainActor @Observable`, owns a `RadioSession` configured with either `BLERadioTransport` or `IcomWiFiTransport`.

Key design:
- `enum TransportType: String { case ble, wifi }` persisted in UserDefaults
- `transportType` property — changing it disconnects and recreates the session
- For BLE: creates `BLERadioTransport` + `RadioSession` with CI-V or Kenwood protocol handler
- For WiFi: creates `IcomWiFiTransport` + `RadioSession` with `CIVProtocolHandler`
- Polling/state observation: a Task reads `session.state` every 200ms and publishes to `@Observable` properties
- Feedback loop prevention stays here (same logic as current `BLERadioService`)
- BLE-specific: `startScan()`, `stopScan()`, `selectDevice()`, `forgetDevice()` delegate to BLE transport
- WiFi-specific: `IcomWiFiConfig` stored as IP in UserDefaults, credentials in Keychain
- `static let shared` singleton

- [ ] **Step 2: Rename LoggingSessionManager+BLERadio.swift**

Rename to `LoggingSessionManager+Radio.swift`. Replace all `BLERadioService` references with `RadioService`. Method names: `connectBLERadio()` → `connectRadio()`, `disconnectBLERadio()` → `disconnectRadio()`.

- [ ] **Step 3: Update all call sites**

Update all 14 files that reference `BLERadioService`:
- `LoggingSessionManager.swift` / `+SessionManagement.swift`: `connectBLERadio()` → `connectRadio()`, `disconnectBLERadio()` → `disconnectRadio()`
- `LoggerView+Commands.swift`, `+Modifiers.swift`, `+SessionBadges.swift`: `showBLERadioPanel` → `showRadioPanel`
- `ActivityLogView.swift`, `ActivityLogSpotsList.swift`: `BLERadioService.shared` → `RadioService.shared`
- `SettingsView+Sections.swift`: "BLE Radio" → "Radio"

- [ ] **Step 4: Delete old files**

```bash
git rm CarrierWave/Services/BLERadio/BLERadioService.swift
```

- [ ] **Step 5: Verify iOS app builds**

Run: `xc build`
Expected: BUILD SUCCEEDED

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "refactor: replace BLERadioService with transport-agnostic RadioService"
```

---

### Task 9: Update Settings UI — Radio settings with transport picker

**Files:**
- Create: `CarrierWave/Views/Settings/RadioSettingsView.swift` (replaces BLERadioSettingsView)
- Modify: `CarrierWave/Views/Settings/BLERadioSettingsView.swift` (delete)
- Modify: `CarrierWave/Views/Logger/BLERadioPanel.swift` → rename to `RadioPanel.swift`

- [ ] **Step 1: Create RadioSettingsView**

Create `CarrierWave/Views/Settings/RadioSettingsView.swift`. Navigation title: "Radio". Structure:

1. **Transport picker** — Segmented control: BLE | WiFi
2. **BLE section** (shown when BLE selected) — same as current: saved device, scan list, connect/disconnect/forget
3. **WiFi section** (shown when WiFi selected):
   - Mode picker: "Access Point" / "Station" (Picker)
   - IP Address: pre-filled `192.168.59.1` for AP (disabled), editable TextField for Station
   - Username: TextField
   - Password: SecureField
   - Connect / Disconnect button
   - Connection status
4. **Advanced section** (always shown) — Protocol picker, CI-V address field

WiFi credentials save to Keychain on connect. IP and mode save to UserDefaults.

- [ ] **Step 2: Rename BLERadioPanel → RadioPanel**

Rename file and struct. Update references in `LoggerView+Modifiers.swift`. Change help text from "Settings > BLE Radio" to "Settings > Radio".

- [ ] **Step 3: Update SettingsView+Sections.swift**

Change navigation link text from "BLE Radio" to "Radio". Change destination from `BLERadioSettingsView` to `RadioSettingsView`.

- [ ] **Step 4: Delete old file**

```bash
git rm CarrierWave/Views/Settings/BLERadioSettingsView.swift
git rm CarrierWave/Views/Logger/BLERadioPanel.swift
```

- [ ] **Step 5: Verify iOS app builds**

Run: `xc build`
Expected: BUILD SUCCEEDED

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: radio settings UI with WiFi/BLE transport picker"
```

---

### Task 10: Migrate CWSweep to shared types

**Files:**
- Modify: `CWSweep/CWSweep/Services/Radio/RadioSession.swift` (delete — use CarrierWaveData)
- Modify: `CWSweep/CWSweep/Services/Radio/RadioProtocolHandler.swift` (delete — use CarrierWaveData)
- Modify: `CWSweep/CWSweep/Services/Radio/CIVProtocolHandler.swift` (delete — use CarrierWaveData)
- Modify: `CWSweep/CWSweep/Services/Radio/KenwoodProtocolHandler.swift` (delete — use CarrierWaveData)
- Modify: `CWSweep/CWSweep/Services/Serial/FrameAssembler.swift` (delete — use CarrierWaveData)
- Modify: `CWSweep/CWSweep/Services/Radio/RadioManager.swift` (update imports)
- Modify: `CWSweep/CWSweep/Services/Radio/YaesuProtocolHandler.swift` (conform to shared protocol)
- Modify: `CWSweep/CWSweep/Services/Radio/ElecraftProtocolHandler.swift` (conform to shared protocol)
- Modify: `CWSweep/CWSweep/Services/Radio/FlexProtocolHandler.swift` (conform to shared protocol)

- [ ] **Step 1: Update YaesuProtocolHandler to import from CarrierWaveData**

Add `import CarrierWaveData` and ensure it conforms to the shared `RadioProtocolHandler` protocol. The protocol signature is identical, so this should be a matter of adding the import.

- [ ] **Step 2: Update ElecraftProtocolHandler**

Add `import CarrierWaveData`. Its internal `kenwood: KenwoodProtocolHandler` now references the shared type.

- [ ] **Step 3: Update FlexProtocolHandler**

Add `import CarrierWaveData`.

- [ ] **Step 4: Update RadioManager**

Add `import CarrierWaveData`. Remove local type references. The `RadioSession.RadioState` type now comes from CarrierWaveData. Handle `scopeSpanKHz` — this was on the old `RadioState` but not the shared one. Add it back as a local property on `RadioManager` parsed from raw frames via `onRawFrame` callback.

- [ ] **Step 5: Delete local copies**

```bash
git rm CWSweep/CWSweep/Services/Radio/RadioSession.swift \
       CWSweep/CWSweep/Services/Radio/RadioProtocolHandler.swift \
       CWSweep/CWSweep/Services/Radio/CIVProtocolHandler.swift \
       CWSweep/CWSweep/Services/Radio/KenwoodProtocolHandler.swift \
       CWSweep/CWSweep/Services/Serial/FrameAssembler.swift
```

- [ ] **Step 6: Verify CWSweep builds**

Run: `cd /Users/jsvana/projects/carrier_wave/CWSweep && xcodebuild -project CWSweep.xcodeproj -scheme CWSweep build -allowProvisioningUpdates`
Expected: BUILD SUCCEEDED

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "refactor: migrate CWSweep to shared RadioSession from CarrierWaveData"
```

---

### Task 11: Update FILE_INDEX.md and CHANGELOG.md

**Files:**
- Modify: `docs/FILE_INDEX.md`
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Update FILE_INDEX.md**

Add entries for new CarrierWaveData radio files. Remove BLERadio entries. Add new Radio entries under CarrierWave. Update CWSweep entries to note shared types.

- [ ] **Step 2: Update CHANGELOG.md**

Under `[Unreleased]`:

```markdown
### Added
- Icom WiFi CAT control — connect to IC-705 and other WiFi-capable Icom radios via Access Point or Station mode
- Shared RadioSession, protocol handlers, and FrameAssembler between iOS and macOS via CarrierWaveData

### Changed
- "BLE Radio" settings renamed to "Radio" with transport picker (BLE / WiFi)
- Radio protocol handlers (CI-V, Kenwood) moved to shared CarrierWaveData package
```

- [ ] **Step 3: Commit**

```bash
git add docs/FILE_INDEX.md CHANGELOG.md
git commit -m "docs: update FILE_INDEX.md and CHANGELOG.md for radio refactor"
```
