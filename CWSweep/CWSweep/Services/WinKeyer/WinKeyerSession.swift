import Foundation
import os

private let logger = Logger(subsystem: "com.jsvana.CWSweep", category: "WinKeyerSession")

// MARK: - WinKeyerSession

/// Actor managing serial I/O with a K1EL WinKeyer 3.
///
/// Opens the port at 1200 baud (8N2), sends Host Open, and runs
/// an async receive loop that classifies incoming bytes as status,
/// speed pot, or echo-back, publishing events via an AsyncStream.
actor WinKeyerSession {
    // MARK: Lifecycle

    init(portPath: String, baudRate: Int = 1_200) {
        self.portPath = portPath
        self.baudRate = baudRate
        port = SerialPort(path: portPath)

        let (stream, continuation) = AsyncStream<WinKeyerEvent>.makeStream()
        eventStream = stream
        eventContinuation = continuation
    }

    // MARK: Internal

    let portPath: String
    let eventStream: AsyncStream<WinKeyerEvent>

    /// Whether the session is currently connected.
    private(set) var isConnected = false

    /// Open the serial port, send Host Open, and start the receive loop.
    func start() async throws {
        let path = portPath
        let baud = baudRate
        logger.info("Opening WinKeyer on \(path) at \(baud) baud")

        try port.open(
            baudRate: baudRate,
            dataBits: 8,
            stopBits: 2,
            parity: .none,
            flowControl: .none,
            assertDTR: true,
            assertRTS: true
        )

        // Send Admin: Host Open
        let hostOpen = WinKeyerProtocolEncoder.encodeHostOpen()
        _ = try port.write(hostOpen)
        logger.debug("Sent Host Open")

        // Wait briefly for firmware revision response
        try await Task.sleep(for: .milliseconds(200))

        let response = try port.read(maxBytes: 64)
        if let firmwareByte = response.first {
            logger.info("WinKeyer firmware revision: \(firmwareByte)")
            isConnected = true
            eventContinuation.yield(.connected(firmwareVersion: firmwareByte))
        } else {
            logger.warning("No firmware revision received — continuing anyway")
            isConnected = true
            eventContinuation.yield(.connected(firmwareVersion: 0))
        }

        // Enable WK3 mode for full feature set
        let wk3Mode = WinKeyerProtocolEncoder.encodeSetWK3Mode()
        _ = try port.write(wk3Mode)

        // Start receive loop
        receiveTask = Task { [weak self] in
            await self?.receiveLoop()
        }
    }

    /// Send Host Close and tear down.
    func stop() {
        receiveTask?.cancel()
        receiveTask = nil

        if port.isOpen {
            let hostClose = WinKeyerProtocolEncoder.encodeHostClose()
            _ = try? port.write(hostClose)
            port.close()
        }

        isConnected = false
        eventContinuation.yield(.disconnected)
        eventContinuation.finish()
        logger.info("WinKeyer session closed")
    }

    /// Configure the speed pot parameters on the WinKeyer.
    /// Set range to 0 to disable the pot and use software speed control only.
    func setSpeedPot(min: UInt8, range: UInt8) throws {
        let data = WinKeyerProtocolEncoder.encodeSetSpeedPot(min: min, range: range)
        _ = try port.write(data)
    }

    /// Set WPM speed.
    func setSpeed(_ wpm: UInt8) throws {
        let data = WinKeyerProtocolEncoder.encodeSetSpeed(wpm)
        _ = try port.write(data)
    }

    /// Send ASCII text to the WinKeyer CW buffer.
    /// Characters are sent as-is; the WinKeyer handles Morse encoding.
    func sendText(_ text: String) throws {
        let ascii = text.uppercased()
        for char in ascii.utf8 {
            // Only send printable ASCII (0x20–0x7F)
            guard char >= 0x20, char <= 0x7F else {
                continue
            }
            _ = try port.write(Data([char]))
        }
    }

    /// Clear the WinKeyer send buffer and stop sending.
    func cancelSending() throws {
        // Cancel buffer stops sending and clears
        _ = try port.write(WinKeyerProtocolEncoder.encodeCancelBuffer())
        // Clear buffer flushes anything remaining
        _ = try port.write(WinKeyerProtocolEncoder.encodeClearBuffer())
    }

    /// Send a stored message by slot number (1-based).
    func sendStoredMessage(slot: UInt8) throws {
        let data = WinKeyerProtocolEncoder.encodeSendMessage(slot: slot)
        _ = try port.write(data)
    }

    /// Set PTT state.
    func setPTT(_ on: Bool) throws {
        _ = try port.write(WinKeyerProtocolEncoder.encodePTTControl(on))
    }

    /// Key down/up immediately.
    func keyImmediate(_ down: Bool) throws {
        _ = try port.write(WinKeyerProtocolEncoder.encodeKeyImmediate(down))
    }

    // MARK: Private

    private let port: SerialPort
    private let baudRate: Int
    private let eventContinuation: AsyncStream<WinKeyerEvent>.Continuation
    private var receiveTask: Task<Void, Never>?

    private func receiveLoop() async {
        logger.debug("Receive loop started")

        while !Task.isCancelled {
            do {
                let data = try port.read(maxBytes: 256)
                if data.isEmpty {
                    // No data available — yield to avoid spinning
                    try await Task.sleep(for: .milliseconds(20))
                    continue
                }

                for byte in data {
                    classifyByte(byte)
                }
            } catch {
                if !Task.isCancelled {
                    logger.error("Read error: \(error)")
                    eventContinuation.yield(.error(error.localizedDescription))
                }
                break
            }
        }

        logger.debug("Receive loop ended")
    }

    private func classifyByte(_ byte: UInt8) {
        if WinKeyerProtocolEncoder.isStatusByte(byte) {
            let status = WinKeyerProtocolEncoder.decodeStatus(byte)
            eventContinuation.yield(.statusChanged(status))
        } else if WinKeyerProtocolEncoder.isSpeedPotByte(byte) {
            let speed = WinKeyerProtocolEncoder.decodeSpeedPot(byte)
            eventContinuation.yield(.speedPotChanged(wpm: speed))
        } else {
            // Echo-back of sent character
            eventContinuation.yield(.echoCharacter(byte))
        }
    }
}
