import CarrierWaveData
import Foundation
import os

private let logger = Logger(subsystem: "com.jsvana.CWSweep", category: "SerialTransport")

// MARK: - Temporary file-based diagnostic logger (remove after debugging)

private let diagLog: FileHandle? = {
    let path = "/tmp/cwsweep_radio_diag.log"
    FileManager.default.createFile(atPath: path, contents: nil)
    return FileHandle(forWritingAtPath: path)
}()

private func diag(_ msg: String) {
    let line = "\(Date()) \(msg)\n"
    diagLog?.seekToEndOfFile()
    diagLog?.write(line.data(using: .utf8)!)
}

// MARK: - SerialRadioTransport

/// Serial port transport conforming to RadioTransport protocol.
/// Manages the read loop and exposes received data as an AsyncStream.
actor SerialRadioTransport: RadioTransport {
    // MARK: Lifecycle

    init(
        profile: RadioProfile,
        logCallback: (@Sendable (RadioCommandDirection, String) -> Void)? = nil
    ) {
        self.profile = profile
        self.logCallback = logCallback
        port = SerialPort(path: profile.serialPortPath)

        let (stream, continuation) = AsyncStream<Data>.makeStream()
        receivedData = stream
        self.continuation = continuation
    }

    // MARK: Internal

    let profile: RadioProfile
    nonisolated let receivedData: AsyncStream<Data>

    var isConnected: Bool {
        port.isOpen
    }

    func connect() async throws {
        diag("Opening \(profile.serialPortPath) at \(profile.baudRate) baud")
        try port.open(
            baudRate: profile.baudRate,
            dataBits: profile.dataBits,
            stopBits: profile.stopBits,
            parity: profile.parity,
            flowControl: profile.flowControl,
            assertDTR: profile.dtrSignal,
            assertRTS: profile.rtsSignal
        )
        diag("Port opened, fd=\(port.fileDescriptor), DTR=\(profile.dtrSignal), RTS=\(profile.rtsSignal)")

        // Let the radio settle after port open — the K3 needs time to exit
        // TEST mode if DTR was briefly asserted by the USB-serial driver.
        try? await Task.sleep(for: .milliseconds(100))
        diag("Post-open settle complete")

        // Start background read loop
        readTask = Task { [weak self] in
            guard let self else {
                return
            }
            await readLoop()
        }
    }

    func disconnect() async {
        readTask?.cancel()
        readTask = nil
        port.close()
        continuation.finish()
    }

    func send(_ data: Data) async throws {
        let ascii = String(data: data, encoding: .ascii) ?? data.map { String(format: "%02X", $0) }.joined()
        diag("SEND: \(ascii) (\(data.count) bytes)")
        logCallback?(.tx, ascii)
        _ = try port.write(data)
    }

    // MARK: Private

    private let port: SerialPort
    private let continuation: AsyncStream<Data>.Continuation
    private let logCallback: (@Sendable (RadioCommandDirection, String) -> Void)?
    private var readTask: Task<Void, Never>?

    private var readCount = 0

    private func readLoop() async {
        diag("readLoop started")
        while !Task.isCancelled, port.isOpen {
            do {
                let data = try port.read(maxBytes: 4_096)
                if !data.isEmpty {
                    let ascii = String(data: data, encoding: .ascii) ?? data.map { String(format: "%02X", $0) }.joined()
                    diag("RECV: \(ascii) (\(data.count) bytes)")
                    logCallback?(.rx, ascii)
                    continuation.yield(data)
                }
            } catch {
                if !Task.isCancelled {
                    diag("Read error: \(error)")
                    try? await Task.sleep(for: .milliseconds(100))
                }
            }
            readCount += 1
            if readCount % 500 == 0 {
                diag("readLoop alive, iterations=\(readCount)")
            }
            // Small yield to prevent tight-looping
            try? await Task.sleep(for: .milliseconds(10))
        }
        diag("readLoop exited, cancelled=\(Task.isCancelled), portOpen=\(port.isOpen)")
    }
}
