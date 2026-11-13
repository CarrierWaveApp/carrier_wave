import Foundation

// MARK: - SCULAN10Channel

/// Channel identifiers encoded in header byte 2.
public enum SCULAN10Channel: UInt8 {
    case ctrl = 0xFC
    case cat = 0xFD
    case audio = 0xFE
    case scope = 0xFA
}

// MARK: - SCULAN10MsgType

/// Message type identifiers encoded in header byte 4.
/// Server responses have bit 7 set (e.g., 0x85 = keepalive response).
public enum SCULAN10MsgType: UInt8 {
    case setup = 0x01
    case auth = 0x03
    case keepalive = 0x05
    case portInit = 0x06
    case data = 0x07
}

// MARK: - SCULAN10Crypto

/// Encryption and framing for the SCU-LAN10 network protocol.
///
/// Packet structure: `[5A 5A] [len LE16] [00 01] [header 8B] [encrypted body]`
///
/// Header byte layout (verified across 76K+ captured packets):
/// - b0: sequence counter
/// - b1: key ^ seq ^ 0xFC
/// - b2: key ^ channel_id
/// - b3: key ^ 0x03
/// - b4: key ^ msg_type
/// - b5: key (random XOR encryption key)
/// - b6: key ^ (body_len & 0xFF)
/// - b7: key ^ (0x07 ^ (body_len >> 8))
public enum SCULAN10Crypto {
    // MARK: Public

    /// Precomputed position-dependent scramble table.
    /// g(i) = (4*(i/4) + 6 + offset[i%4]) & 0xFF where offset = [0, 0xFF, 0xFE, 5]
    public static let gTable: [UInt8] = {
        var table = [UInt8](repeating: 0, count: 8_192)
        let offsets = [0, 0xFF, 0xFE, 5]
        for idx in 0 ..< 8_192 {
            let group = idx / 4
            let base = (4 * group + 6) & 0xFF
            table[idx] = UInt8((base + offsets[idx % 4]) & 0xFF)
        }
        return table
    }()

    public static let magic = Data([0x5A, 0x5A])
    public static let typeField = Data([0x00, 0x01])

    /// Fixed init keepalive packets sent at the start of every connection.
    public static let initPackets: [Data] = [
        Data(sculan10HexString: "5a5a0e00000101a0a15e585d595a5b585956"),
        Data(sculan10HexString: "5a5a0e000001024042bdbbbebab9b8bbbab5"),
        Data(sculan10HexString: "5a5a0e00000103e0e31c1a1f1b18191a1b14"),
        Data(sculan10HexString: "5a5a0e0000010480847b7d787c7f7e7d7c73"),
        Data(sculan10HexString: "5a5a0e000001052025dadcd9dddedfdcddd2"),
    ]

    /// Build an authentication packet with encrypted credentials.
    public static func buildAuthPacket(username: String, password: String) -> Data {
        let key: UInt8 = 0x3A
        let header = buildHeader(
            seq: 0x06, key: key,
            channel: .ctrl, msgType: .auth,
            bodyLen: 68
        )
        let plaintext = buildAuthPlaintext(
            username: username, password: password
        )
        return framePacket(header: header, plaintext: plaintext)
    }

    /// Build a framed, encrypted packet with a correct protocol header.
    public static func buildPacket(
        seq: UInt8,
        channel: SCULAN10Channel,
        msgType: SCULAN10MsgType,
        plaintext: Data
    ) -> Data {
        let key = UInt8.random(in: 0 ... 255)
        let header = buildHeader(
            seq: seq, key: key,
            channel: channel, msgType: msgType,
            bodyLen: plaintext.count
        )
        return framePacket(header: header, plaintext: plaintext)
    }

    /// Decrypt payload data (after 5a5a + length + type).
    /// Key is at payload byte 5; data starts at byte 8.
    public static func decryptPayload(_ payload: Data) -> Data {
        guard payload.count >= 9 else {
            return Data()
        }
        let key = payload[5]
        let dataLen = payload.count - 8
        var result = Data(count: dataLen)
        for idx in 0 ..< dataLen {
            result[idx] = payload[8 + idx] ^ key ^ gTable[idx]
        }
        return result
    }

    /// Decrypt 4096 spectrum samples from a scope payload.
    public static func decryptScopeData(_ payload: Data) -> Data {
        guard payload.count >= 4_104 else {
            return Data()
        }
        let key = payload[5]
        var spectrum = Data(count: 4_096)
        for idx in 0 ..< 4_096 {
            spectrum[idx] = payload[8 + idx] ^ key ^ gTable[idx]
        }
        return spectrum
    }

    // MARK: Private

    private static func buildHeader(
        seq: UInt8,
        key: UInt8,
        channel: SCULAN10Channel,
        msgType: SCULAN10MsgType,
        bodyLen: Int
    ) -> Data {
        var header = Data(count: 8)
        header[0] = seq
        header[1] = key ^ seq ^ 0xFC
        header[2] = key ^ channel.rawValue
        header[3] = key ^ 0x03
        header[4] = key ^ msgType.rawValue
        header[5] = key
        header[6] = key ^ UInt8(bodyLen & 0xFF)
        header[7] = key ^ (0x07 ^ UInt8((bodyLen >> 8) & 0xFF))
        return header
    }

    private static func framePacket(
        header: Data,
        plaintext: Data
    ) -> Data {
        let key = header[5]
        var encrypted = Data(count: plaintext.count)
        for idx in 0 ..< plaintext.count {
            encrypted[idx] = plaintext[idx] ^ key ^ gTable[idx]
        }
        let payload = header + encrypted
        let length = UInt16(payload.count + 2)
        var lengthBytes = Data(count: 2)
        lengthBytes[0] = UInt8(length & 0xFF)
        lengthBytes[1] = UInt8(length >> 8)
        return magic + lengthBytes + typeField + payload
    }

    private static func buildAuthPlaintext(
        username: String,
        password: String
    ) -> Data {
        var plaintext = Data([0x01, 0x00])

        var userBytes = Data(username.utf8)
        let userPad = max(0, 33 - userBytes.count)
        userBytes.append(contentsOf: [UInt8](repeating: 0, count: userPad))
        plaintext.append(contentsOf: userBytes.prefix(33))

        var passBytes = Data(password.utf8)
        let passPad = max(0, 33 - passBytes.count)
        passBytes.append(contentsOf: [UInt8](repeating: 0, count: passPad))
        plaintext.append(contentsOf: passBytes.prefix(33))

        return plaintext
    }
}

// MARK: - SCULAN10Error

public enum SCULAN10Error: LocalizedError {
    case notConnected
    case authFailed
    case timeout
    case noData
    case connectionCancelled

    // MARK: Public

    public var errorDescription: String? {
        switch self {
        case .notConnected: "Not connected to SCU-LAN10"
        case .authFailed: "Authentication failed"
        case .timeout: "Connection timed out"
        case .noData: "No data received"
        case .connectionCancelled: "Connection was cancelled"
        }
    }
}

// MARK: - Data+Hex

private extension Data {
    init(sculan10HexString hexString: String) {
        self.init()
        var hex = hexString
        while hex.count >= 2 {
            let byteString = String(hex.prefix(2))
            hex = String(hex.dropFirst(2))
            if let byte = UInt8(byteString, radix: 16) {
                append(byte)
            }
        }
    }
}
