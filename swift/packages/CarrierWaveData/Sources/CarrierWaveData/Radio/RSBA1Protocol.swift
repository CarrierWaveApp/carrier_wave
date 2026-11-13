import Foundation

// MARK: - RSBA1Ports

enum RSBA1Ports {
    static let control: UInt16 = 50_001
    static let serial: UInt16 = 50_002
    static let audio: UInt16 = 50_003
}

// MARK: - RSBA1PacketSize

enum RSBA1PacketSize {
    static let ping: Int = 16
    static let pingExtended: Int = 21
    static let authChallenge: Int = 64
    static let login: Int = 128
    static let connInfo: Int = 144
    static let streamRequest: Int = 64
}

// MARK: - Passcode Encoding

/// RS-BA1 passcode substitution cipher (from kappanhang passcode.go).
/// Each character is offset by its index position, then looked up in a substitution table.
private let passcodeSequence: [Int: UInt8] = [
    32: 0x47, 33: 0x5D, 34: 0x4C, 35: 0x42, 36: 0x66,
    37: 0x20, 38: 0x23, 39: 0x46, 40: 0x4E, 41: 0x57,
    42: 0x45, 43: 0x3D, 44: 0x67, 45: 0x76, 46: 0x60,
    47: 0x41, 48: 0x62, 49: 0x39, 50: 0x59, 51: 0x2D,
    52: 0x68, 53: 0x7E, 54: 0x7C, 55: 0x65, 56: 0x7D,
    57: 0x49, 58: 0x29, 59: 0x72, 60: 0x73, 61: 0x78,
    62: 0x21, 63: 0x6E, 64: 0x5A, 65: 0x5E, 66: 0x4A,
    67: 0x3E, 68: 0x71, 69: 0x2C, 70: 0x2A, 71: 0x54,
    72: 0x3C, 73: 0x3A, 74: 0x63, 75: 0x4F, 76: 0x43,
    77: 0x75, 78: 0x27, 79: 0x79, 80: 0x5B, 81: 0x35,
    82: 0x70, 83: 0x48, 84: 0x6B, 85: 0x56, 86: 0x6F,
    87: 0x34, 88: 0x32, 89: 0x6C, 90: 0x30, 91: 0x61,
    92: 0x6D, 93: 0x7B, 94: 0x2F, 95: 0x4B, 96: 0x64,
    97: 0x38, 98: 0x2B, 99: 0x2E, 100: 0x50, 101: 0x40,
    102: 0x3F, 103: 0x55, 104: 0x33, 105: 0x37, 106: 0x25,
    107: 0x77, 108: 0x24, 109: 0x26, 110: 0x74, 111: 0x6A,
    112: 0x28, 113: 0x53, 114: 0x4D, 115: 0x69, 116: 0x22,
    117: 0x5C, 118: 0x44, 119: 0x31, 120: 0x36, 121: 0x58,
    122: 0x3B, 123: 0x7A, 124: 0x51, 125: 0x5F, 126: 0x52,
]

/// Encode a string using the RS-BA1 passcode substitution cipher.
/// Returns a fixed 16-byte array, zero-padded if shorter.
func encodePasscode(_ input: String) -> Data {
    var result = Data(count: 16)
    let chars = Array(input.utf8)
    for idx in 0 ..< min(chars.count, 16) {
        var pos = Int(chars[idx]) + idx
        if pos > 126 {
            pos = 32 + (pos % 127)
        }
        result[idx] = passcodeSequence[pos] ?? 0
    }
    return result
}
