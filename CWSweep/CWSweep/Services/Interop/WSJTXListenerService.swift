import Foundation
import Network

// MARK: - WSJTXDecode

/// A decoded message from WSJT-X.
struct WSJTXDecode: Sendable, Identifiable {
    var id: UUID = .init()
    var timestamp: Date
    var callsign: String
    var frequency: Double
    var snr: Int
    var message: String
}

// MARK: - WSJTXListenerService

/// UDP listener for WSJT-X binary protocol messages.
actor WSJTXListenerService {
    // MARK: Lifecycle

    init(port: UInt16 = 2_237) {
        self.port = port
    }

    // MARK: Internal

    private(set) var isConnected = false

    /// Stream of decoded messages from WSJT-X.
    var decodedMessages: AsyncStream<WSJTXDecode> {
        AsyncStream { continuation in
            self.continuation = continuation
        }
    }

    func start() throws {
        let params = NWParameters.udp
        listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
        listener?.newConnectionHandler = { [weak self] connection in
            Task { await self?.handleConnection(connection) }
        }
        listener?.stateUpdateHandler = { [weak self] state in
            Task { await self?.handleListenerState(state) }
        }
        listener?.start(queue: .global(qos: .utility))
    }

    func stop() {
        listener?.cancel()
        listener = nil
        isConnected = false
        continuation?.finish()
    }

    // MARK: Private

    /// Magic number for WSJT-X binary protocol
    private static let magic: UInt32 = 0xADBC_CBDA

    private var listener: NWListener?
    private let port: UInt16
    private var continuation: AsyncStream<WSJTXDecode>.Continuation?

    private func handleListenerState(_ state: NWListener.State) {
        switch state {
        case .ready:
            isConnected = true
        case .failed,
             .cancelled:
            isConnected = false
        default:
            break
        }
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .utility))
        receiveData(from: connection)
    }

    nonisolated private func receiveData(from connection: NWConnection) {
        connection.receiveMessage { content, _, _, error in
            guard error == nil, let data = content else {
                return
            }
            Task { await self.parseMessage(data) }
            // Continue receiving
            self.receiveData(from: connection)
        }
    }

    private func parseMessage(_ data: Data) {
        guard data.count >= 8 else {
            return
        }

        // Check magic number
        let magic = data.withUnsafeBytes { $0.load(fromByteOffset: 0, as: UInt32.self).bigEndian }
        guard magic == Self.magic else {
            return
        }

        // Schema version (4 bytes) + message type (4 bytes)
        guard data.count >= 12 else {
            return
        }
        let messageType = data.withUnsafeBytes { $0.load(fromByteOffset: 8, as: UInt32.self).bigEndian }

        switch messageType {
        case 2: // Decode message
            if let decode = parseDecodeMessage(data) {
                continuation?.yield(decode)
            }
        default:
            break
        }
    }

    private func parseDecodeMessage(_ data: Data) -> WSJTXDecode? {
        // WSJT-X Decode message format after 12-byte header:
        // - 4 bytes: ID string length, then string
        // - 1 byte: new flag
        // - 4 bytes: time ms since midnight
        // - 4 bytes: snr
        // - 8 bytes: delta time
        // - 4 bytes: delta freq
        // - 4 bytes: mode string length, then string
        // - 4 bytes: message string length, then string
        // This is a simplified parser
        guard data.count > 30 else {
            return nil
        }

        var offset = 12

        // Skip ID string
        guard let (_, nextOffset) = readQString(from: data, at: offset) else {
            return nil
        }
        offset = nextOffset

        guard offset + 1 <= data.count else {
            return nil
        }
        offset += 1 // new flag

        guard offset + 4 <= data.count else {
            return nil
        }
        offset += 4 // time ms

        guard offset + 4 <= data.count else {
            return nil
        }
        let snr = data.withUnsafeBytes { $0.load(fromByteOffset: offset, as: Int32.self).bigEndian }
        offset += 4

        offset += 8 // delta time
        guard offset <= data.count else {
            return nil
        }

        guard offset + 4 <= data.count else {
            return nil
        }
        let deltaFreq = data.withUnsafeBytes { $0.load(fromByteOffset: offset, as: UInt32.self).bigEndian }
        offset += 4

        // Skip mode string
        guard let (_, modeEnd) = readQString(from: data, at: offset) else {
            return nil
        }
        offset = modeEnd

        // Read message string
        guard let (message, _) = readQString(from: data, at: offset) else {
            return nil
        }

        // Extract callsign from message (simplified: take second word)
        let parts = message.split(separator: " ")
        let callsign = parts.count >= 2 ? String(parts[1]) : message

        return WSJTXDecode(
            timestamp: Date(),
            callsign: callsign,
            frequency: Double(deltaFreq) / 1_000_000,
            snr: Int(snr),
            message: message
        )
    }

    /// Read a Qt-style QString from binary data (4-byte length prefix, UTF-16BE).
    private func readQString(from data: Data, at offset: Int) -> (String, Int)? {
        guard offset + 4 <= data.count else {
            return nil
        }
        let length = data.withUnsafeBytes {
            Int($0.load(fromByteOffset: offset, as: UInt32.self).bigEndian)
        }
        guard length >= 0 else {
            // -1 means null string in Qt
            return ("", offset + 4)
        }
        let stringStart = offset + 4
        let stringEnd = stringStart + length
        guard stringEnd <= data.count else {
            return nil
        }
        let stringData = data[stringStart ..< stringEnd]
        let string = String(data: stringData, encoding: .utf16BigEndian) ?? ""
        return (string, stringEnd)
    }
}
