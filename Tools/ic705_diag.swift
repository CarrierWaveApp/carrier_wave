#!/usr/bin/env swift
// swiftlint:disable all
//
// IC-705 WiFi Protocol Diagnostic Tool (Swift)
// ==============================================
// Connects to an Icom IC-705 (or similar) over WiFi using the RS-BA1 UDP protocol,
// runs the full handshake and CI-V exchange, and prints diagnostic output.
//
// Mirrors the Python ic705_diag.py — same protocol, same phases, Swift-native.
//
// Usage:
//   swift ic705_diag.swift --user <username> --pass <password> [--ip 192.168.59.1]
//
// Build & run (faster for repeated use):
//   swiftc -O ic705_diag.swift -o ic705_diag && ./ic705_diag --user admin --pass secret
//

import Darwin
import Foundation

// MARK: - RS-BA1 Protocol Constants

let CONTROL_PORT: UInt16 = 50_001
let SERIAL_PORT: UInt16 = 50_002
let AUDIO_PORT: UInt16 = 50_003

let CIV_PREAMBLE: UInt8 = 0xFE
let CIV_TERMINATOR: UInt8 = 0xFD
let CIV_CONTROLLER: UInt8 = 0xE0
let IC705_ADDR: UInt8 = 0xA4

let CIV_READ_FREQ: UInt8 = 0x03
let CIV_READ_MODE: UInt8 = 0x04
let CIV_SET_FREQ: UInt8 = 0x05
let CIV_SET_MODE: UInt8 = 0x06
let CIV_ACK: UInt8 = 0xFB
let CIV_NAK: UInt8 = 0xFA

let CIV_MODES: [UInt8: String] = [
    0x00: "LSB", 0x01: "USB", 0x02: "AM", 0x03: "CW",
    0x04: "RTTY", 0x05: "FM", 0x06: "WFM", 0x07: "CW-R", 0x08: "RTTY-R",
]

// MARK: - Passcode Encoding

let PASSCODE_TABLE: [Int: UInt8] = [
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

func encodePasscode(_ text: String) -> [UInt8] {
    var result = [UInt8](repeating: 0, count: 16)
    let chars = Array(text.utf8)
    for idx in 0 ..< min(chars.count, 16) {
        var pos = Int(chars[idx]) + idx
        if pos > 126 {
            pos = 32 + (pos % 127)
        }
        result[idx] = PASSCODE_TABLE[pos] ?? 0
    }
    return result
}

// MARK: - Binary Helpers

func w32be(_ buf: inout [UInt8], _ off: Int, _ val: UInt32) {
    buf[off] = UInt8((val >> 24) & 0xFF)
    buf[off + 1] = UInt8((val >> 16) & 0xFF)
    buf[off + 2] = UInt8((val >> 8) & 0xFF)
    buf[off + 3] = UInt8(val & 0xFF)
}

func r32be(_ buf: [UInt8], _ off: Int) -> UInt32 {
    UInt32(buf[off]) << 24 | UInt32(buf[off + 1]) << 16
        | UInt32(buf[off + 2]) << 8 | UInt32(buf[off + 3])
}

func w16le(_ buf: inout [UInt8], _ off: Int, _ val: UInt16) {
    buf[off] = UInt8(val & 0xFF)
    buf[off + 1] = UInt8((val >> 8) & 0xFF)
}

func r16le(_ buf: [UInt8], _ off: Int) -> UInt16 {
    UInt16(buf[off]) | UInt16(buf[off + 1]) << 8
}

func w16be(_ buf: inout [UInt8], _ off: Int, _ val: UInt16) {
    buf[off] = UInt8((val >> 8) & 0xFF)
    buf[off + 1] = UInt8(val & 0xFF)
}

func hexDump(_ data: [UInt8], prefix: String = "  ") -> String {
    var lines: [String] = []
    for start in stride(from: 0, to: data.count, by: 16) {
        let end = min(start + 16, data.count)
        let chunk = Array(data[start ..< end])
        let hx = chunk.map { String(format: "%02X", $0) }.joined(separator: " ")
        let asc = chunk.map { (32 ... 126).contains(Int($0)) ? String(UnicodeScalar($0)) : "." }
            .joined()
        lines.append(String(format: "%@%04X  %-48s  %@", prefix, start, hx, asc))
    }
    return lines.joined(separator: "\n")
}

func parseBCDFreq(_ data: [UInt8]) -> Int? {
    guard data.count >= 5 else {
        return nil
    }
    var freq = 0
    var mult = 1
    for idx in 0 ..< 5 {
        let lo = Int(data[idx] & 0x0F)
        let hi = Int((data[idx] >> 4) & 0x0F)
        guard lo <= 9, hi <= 9 else {
            return nil
        }
        freq += lo * mult
        mult *= 10
        freq += hi * mult
        mult *= 10
    }
    return freq
}

func encodeBCDFreq(_ hz: Int) -> [UInt8] {
    var remaining = hz
    var bytes: [UInt8] = []
    for _ in 0 ..< 5 {
        let lo = UInt8(remaining % 10)
        remaining /= 10
        let hi = UInt8(remaining % 10)
        remaining /= 10
        bytes.append((hi << 4) | lo)
    }
    return bytes
}

func formatFreq(_ hz: Int) -> String {
    let mhz = Double(hz) / 1_000_000.0
    return hz % 1_000 == 0
        ? String(format: "%.3f MHz", mhz)
        : String(format: "%.6f MHz", mhz)
}

// MARK: - UDPSock

final class UDPSock {
    // MARK: Lifecycle

    init(host: String, port: UInt16) {
        self.host = host
        self.port = port
    }

    // MARK: Internal

    let host: String
    let port: UInt16
    var fd: Int32 = -1
    var remoteAddr = sockaddr_in()
    var localPort: UInt16 = 0

    func open() throws {
        guard let hostent = gethostbyname(host) else {
            throw DiagError.dns(host)
        }
        guard let addrPtr = hostent.pointee.h_addr_list[0] else {
            throw DiagError.dns(host)
        }
        var inAddr = in_addr()
        memcpy(&inAddr, addrPtr, Int(hostent.pointee.h_length))

        fd = socket(AF_INET, SOCK_DGRAM, 0)
        guard fd >= 0 else {
            throw DiagError.socket
        }

        // kappanhang: bind local port = remote port for RS-BA1 compatibility
        var localAddr = sockaddr_in()
        localAddr.sin_family = sa_family_t(AF_INET)
        localAddr.sin_addr.s_addr = INADDR_ANY

        // Try matching port first, fall back to random
        localAddr.sin_port = port.bigEndian
        var bindResult = withUnsafePointer(to: &localAddr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.bind(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if bindResult != 0 {
            localAddr.sin_port = 0
            bindResult = withUnsafePointer(to: &localAddr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                    Darwin.bind(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        guard bindResult == 0 else {
            Darwin.close(fd)
            throw DiagError.bind
        }

        // Get assigned local port
        var boundAddr = sockaddr_in()
        var addrLen = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &boundAddr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                getsockname(fd, sockPtr, &addrLen)
            }
        }
        localPort = UInt16(bigEndian: boundAddr.sin_port)

        remoteAddr.sin_family = sa_family_t(AF_INET)
        remoteAddr.sin_port = port.bigEndian
        remoteAddr.sin_addr = inAddr

        // Non-blocking receive
        var flags = fcntl(fd, F_GETFL, 0)
        flags |= O_NONBLOCK
        _ = fcntl(fd, F_SETFL, flags)
    }

    func send(_ data: [UInt8]) {
        guard fd >= 0 else {
            return
        }
        data.withUnsafeBufferPointer { buf in
            withUnsafePointer(to: &remoteAddr) { addrPtr in
                addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                    _ = sendto(fd, buf.baseAddress, data.count, 0, sockPtr,
                               socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
    }

    func recv(timeout: TimeInterval = 3.0) -> [UInt8]? {
        guard fd >= 0 else {
            return nil
        }
        var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
        let timeoutMs = Int32(timeout * 1_000)
        let result = poll(&pfd, 1, timeoutMs)
        if result > 0 {
            var buf = [UInt8](repeating: 0, count: 8_192)
            let bytesRead = Darwin.recv(fd, &buf, buf.count, 0)
            if bytesRead > 0 {
                return Array(buf[0 ..< bytesRead])
            }
        }
        return nil
    }

    func recvAll(timeout: TimeInterval = 1.0) -> [[UInt8]] {
        var packets: [[UInt8]] = []
        let deadline = CFAbsoluteTimeGetCurrent() + timeout
        while CFAbsoluteTimeGetCurrent() < deadline {
            let remaining = deadline - CFAbsoluteTimeGetCurrent()
            guard remaining > 0 else {
                break
            }
            if let pkt = recv(timeout: min(remaining, 0.1)) {
                packets.append(pkt)
            } else if !packets.isEmpty {
                break
            }
        }
        return packets
    }

    func drain() {
        _ = recvAll(timeout: 0.3)
    }

    func close() {
        if fd >= 0 {
            Darwin.close(fd)
            fd = -1
        }
    }
}

// MARK: - DiagError

enum DiagError: Error, CustomStringConvertible {
    case dns(String)
    case socket
    case bind
    case timeout(String)
    case auth(String)

    // MARK: Internal

    var description: String {
        switch self {
        case let .dns(host): "DNS resolution failed for \(host)"
        case .socket: "Failed to create UDP socket"
        case .bind: "Failed to bind UDP socket"
        case let .timeout(phase): "Timeout: \(phase)"
        case let .auth(msg): "Auth failed: \(msg)"
        }
    }
}

// MARK: - IC705Diag

final class IC705Diag {
    // MARK: Lifecycle

    init(ip: String, username: String, password: String, targetFreqHz: Int? = nil, runTour: Bool = false) {
        self.ip = ip
        self.username = username
        self.password = password
        self.targetFreqHz = targetFreqHz
        self.runTour = runTour
    }

    // MARK: Internal

    // MARK: - CI-V Parsing

    struct CIVFrame {
        let to: UInt8
        let from: UInt8
        let command: UInt8
        let data: [UInt8]
    }

    struct TourStop {
        let freqHz: Int
        let band: String
        let activity: String
    }

    static let tourStops: [TourStop] = [
        TourStop(freqHz: 3_530_000, band: "80m", activity: "CW"),
        TourStop(freqHz: 7_030_000, band: "40m", activity: "CW"),
        TourStop(freqHz: 14_060_000, band: "20m", activity: "CW"),
        TourStop(freqHz: 18_130_000, band: "17m", activity: "USB"),
        TourStop(freqHz: 21_060_000, band: "15m", activity: "CW"),
        TourStop(freqHz: 28_060_000, band: "10m", activity: "CW"),
        TourStop(freqHz: 50_090_000, band: "6m", activity: "CW"),
        TourStop(freqHz: 145_000_000, band: "2m", activity: "USB"),
    ]

    let ip: String
    let username: String
    let password: String
    let targetFreqHz: Int?
    let runTour: Bool
    let startTime = CFAbsoluteTimeGetCurrent()

    var localSID: UInt32 = 0
    var remoteSID: UInt32 = 0
    var civRemoteSID: UInt32 = 0
    var trackedSeq: UInt16 = 1
    var pingSeq: UInt16 = 2
    var civTrackedSeq: UInt16 = 1
    var civDataSeq: UInt16 = 0
    var authInnerSeq: UInt16 = 0
    var authID = [UInt8](repeating: 0, count: 6)
    var a8ReplyID = [UInt8](repeating: 0, count: 16)
    var authOk = false
    var txBuf: [UInt16: [UInt8]] = [:]
    var lastReauthTime: CFAbsoluteTime = 0
    let reauthInterval: TimeInterval = 55.0

    var ctrl: UDPSock?
    var civ: UDPSock?

    let dwellSeconds: TimeInterval = 40.0

    // MARK: - Logging

    func elapsed() -> String {
        String(format: "%7.3fs", CFAbsoluteTimeGetCurrent() - startTime)
    }

    func logTX(_ label: String, _ data: [UInt8]? = nil) {
        let sz = data.map { "(\($0.count)B)" } ?? ""
        print("  [\(elapsed())] >>> \(label) \(sz)")
        if let data, data.count <= 256 {
            print(hexDump(data))
        }
    }

    func logRX(_ label: String, _ data: [UInt8]? = nil) {
        let sz = data.map { "(\($0.count)B)" } ?? ""
        print("  [\(elapsed())] <<< \(label) \(sz)")
        if let data, data.count <= 256 {
            print(hexDump(data))
        }
    }

    func logInfo(_ msg: String) {
        print("  [\(elapsed())] [INFO]  \(msg)")
    }

    func logError(_ msg: String) {
        print("  [\(elapsed())] [ERROR] \(msg)")
    }

    func logWarn(_ msg: String) {
        print("  [\(elapsed())] [WARN]  \(msg)")
    }

    // MARK: - Reauth & Channel Servicing

    func sendReauthIfNeeded() {
        guard let sock = ctrl else {
            return
        }
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastReauthTime >= reauthInterval else {
            return
        }
        lastReauthTime = now
        var reauth = makeAuth(magic: 0x05)
        logTX("reauth(0x05) [periodic]", reauth)
        sendTracked(sock, &reauth)
    }

    /// Service both control and CIV channels — pkt7, idle, retransmit.
    /// Returns (ctrlPkt7Count, civPkt7Count, retransmitCount) for telemetry.
    @discardableResult
    func serviceChannels() -> (ctrl7: Int, civ7: Int, retx: Int) {
        var ctrl7 = 0; var civ7 = 0; var retx = 0
        if let sock = ctrl {
            while let pkt = sock.recv(timeout: 0) {
                guard pkt.count >= 16 else {
                    continue
                }
                if isPkt7(pkt) {
                    handlePkt7(pkt, sock: sock); ctrl7 += 1
                } else if pkt[4] == 0x01 {
                    handleRetransmit(pkt, sock: sock); retx += 1
                } else if pkt[4] == 0x05 {
                    logWarn("Received pkt5 (disconnect) from radio on control!")
                }
            }
        }
        if let civSock = civ {
            while let pkt = civSock.recv(timeout: 0) {
                guard pkt.count >= 16 else {
                    continue
                }
                if pkt.count == 21, pkt[4] == 0x07, pkt[16] == 0x00 {
                    var reply = pkt
                    reply[16] = 0x01
                    w32be(&reply, 8, localSID)
                    w32be(&reply, 12, civRemoteSID)
                    civSock.send(reply); civ7 += 1
                } else if pkt[4] == 0x01 {
                    handleRetransmit(pkt, sock: civSock); retx += 1
                } else if pkt[4] == 0x05 {
                    logWarn("Received pkt5 (disconnect) from radio on CIV!")
                }
            }
        }
        return (ctrl7, civ7, retx)
    }

    /// Dwell for the given duration, servicing channels and sending reauth/idle.
    /// Logs telemetry every 10 seconds for timeout debugging.
    func dwell(seconds: TimeInterval) {
        guard let sock = ctrl else {
            return
        }
        let deadline = CFAbsoluteTimeGetCurrent() + seconds
        var lastIdleTime = CFAbsoluteTimeGetCurrent()
        var lastTelemetryTime = CFAbsoluteTimeGetCurrent()
        var totalCtrl7 = 0; var totalCiv7 = 0; var totalRetx = 0; var totalIdles = 0
        while CFAbsoluteTimeGetCurrent() < deadline {
            let counts = serviceChannels()
            totalCtrl7 += counts.ctrl7
            totalCiv7 += counts.civ7
            totalRetx += counts.retx
            sendReauthIfNeeded()

            let now = CFAbsoluteTimeGetCurrent()
            if now - lastIdleTime >= 0.5 {
                var idlePkt = makeIdle()
                sendTracked(sock, &idlePkt)
                lastIdleTime = now
                totalIdles += 1
            }

            // Telemetry heartbeat every 10s
            if now - lastTelemetryTime >= 10.0 {
                let remaining = Int(deadline - now)
                let sinceReauth = Int(now - lastReauthTime)
                logInfo(
                    "[telemetry] \(remaining)s left | pkt7: ctrl=\(totalCtrl7) civ=\(totalCiv7) | retx=\(totalRetx) | idles=\(totalIdles) | reauth \(sinceReauth)s ago"
                )
                lastTelemetryTime = now
            }

            Thread.sleep(forTimeInterval: 0.05)
        }
        logInfo(
            "[telemetry] dwell complete | pkt7: ctrl=\(totalCtrl7) civ=\(totalCiv7) | retx=\(totalRetx) | idles=\(totalIdles)"
        )
    }

    // MARK: - Tracked Send

    func sendTracked(_ sock: UDPSock, _ pkt: inout [UInt8], isCIV: Bool = false) {
        let seq: UInt16
        if isCIV {
            seq = civTrackedSeq
            civTrackedSeq += 1
        } else {
            seq = trackedSeq
            trackedSeq += 1
        }
        w16le(&pkt, 6, seq)
        txBuf[seq] = pkt
        sock.send(pkt)
    }

    // MARK: - Packet Builders

    func makePkt3() -> [UInt8] {
        var pkt = [UInt8](repeating: 0, count: 16)
        pkt[0] = 0x10; pkt[4] = 0x03
        w32be(&pkt, 8, localSID)
        w32be(&pkt, 12, remoteSID)
        return pkt
    }

    func makePkt5() -> [UInt8] {
        var pkt = [UInt8](repeating: 0, count: 16)
        pkt[0] = 0x10; pkt[4] = 0x05
        w32be(&pkt, 8, localSID)
        w32be(&pkt, 12, remoteSID)
        return pkt
    }

    func makePkt6() -> [UInt8] {
        var pkt = [UInt8](repeating: 0, count: 16)
        pkt[0] = 0x10; pkt[4] = 0x06; pkt[6] = 0x01
        w32be(&pkt, 8, localSID)
        w32be(&pkt, 12, remoteSID)
        return pkt
    }

    func makePkt7() -> [UInt8] {
        var pkt = [UInt8](repeating: 0, count: 21)
        pkt[0] = 0x15; pkt[4] = 0x07
        let seq = pingSeq
        pingSeq += 1
        w16le(&pkt, 6, seq)
        w32be(&pkt, 8, localSID)
        w32be(&pkt, 12, remoteSID)
        pkt[16] = 0x00
        pkt[17] = UInt8.random(in: 0 ... 255)
        pkt[18] = UInt8(seq & 0xFF)
        pkt[19] = UInt8((seq >> 8) & 0xFF)
        pkt[20] = 0x06
        return pkt
    }

    func makeIdle() -> [UInt8] {
        var pkt = [UInt8](repeating: 0, count: 16)
        pkt[0] = 0x10
        w32be(&pkt, 8, localSID)
        w32be(&pkt, 12, remoteSID)
        return pkt
    }

    func makeCIVIdle() -> [UInt8] {
        var pkt = [UInt8](repeating: 0, count: 16)
        pkt[0] = 0x10
        w32be(&pkt, 8, localSID)
        w32be(&pkt, 12, civRemoteSID)
        return pkt
    }

    func makeLogin() -> [UInt8] {
        var pkt = [UInt8](repeating: 0, count: 128)
        pkt[0] = 0x80
        w32be(&pkt, 8, localSID)
        w32be(&pkt, 12, remoteSID)
        pkt[19] = 0x70
        pkt[20] = 0x01
        pkt[23] = UInt8(authInnerSeq & 0xFF)
        pkt[24] = UInt8((authInnerSeq >> 8) & 0xFF)
        authInnerSeq += 1
        pkt[26] = UInt8.random(in: 0 ... 255)
        pkt[27] = UInt8.random(in: 0 ... 255)
        let encUser = encodePasscode(username)
        let encPass = encodePasscode(password)
        for idx in 0 ..< 16 {
            pkt[64 + idx] = encUser[idx]
        }
        for idx in 0 ..< 16 {
            pkt[80 + idx] = encPass[idx]
        }
        let name = Array("icom-cw\0".utf8)
        for idx in 0 ..< min(name.count, 8) {
            pkt[96 + idx] = name[idx]
        }
        return pkt
    }

    func makeAuth(magic: UInt8) -> [UInt8] {
        var pkt = [UInt8](repeating: 0, count: 64)
        pkt[0] = 0x40
        w32be(&pkt, 8, localSID)
        w32be(&pkt, 12, remoteSID)
        pkt[19] = 0x30
        pkt[20] = 0x01
        pkt[21] = magic
        pkt[23] = UInt8(authInnerSeq & 0xFF)
        pkt[24] = UInt8((authInnerSeq >> 8) & 0xFF)
        authInnerSeq += 1
        for idx in 0 ..< 6 {
            pkt[26 + idx] = authID[idx]
        }
        return pkt
    }

    func makeConnInfo() -> [UInt8] {
        var pkt = [UInt8](repeating: 0, count: 144)
        pkt[0] = 0x90
        w32be(&pkt, 8, localSID)
        w32be(&pkt, 12, remoteSID)
        pkt[19] = 0x80
        pkt[20] = 0x01
        pkt[21] = 0x03
        pkt[23] = UInt8(authInnerSeq & 0xFF)
        pkt[24] = UInt8((authInnerSeq >> 8) & 0xFF)
        authInnerSeq += 1
        for idx in 0 ..< 6 {
            pkt[26 + idx] = authID[idx]
        }
        for idx in 0 ..< 16 {
            pkt[32 + idx] = a8ReplyID[idx]
        }
        let radioName = Array("IC-705\0\0".utf8)
        for idx in 0 ..< min(radioName.count, 8) {
            pkt[64 + idx] = radioName[idx]
        }
        let encUser = encodePasscode(username)
        for idx in 0 ..< 16 {
            pkt[96 + idx] = encUser[idx]
        }
        pkt[112] = 0x01; pkt[113] = 0x01; pkt[114] = 0x04; pkt[115] = 0x04
        w16be(&pkt, 118, 48_000)
        w16be(&pkt, 122, 48_000)
        w16be(&pkt, 126, SERIAL_PORT)
        w16be(&pkt, 130, AUDIO_PORT)
        w16be(&pkt, 134, 300)
        pkt[136] = 0x01
        return pkt
    }

    func makeCIVOpen() -> [UInt8] {
        var pkt = [UInt8](repeating: 0, count: 22)
        pkt[0] = 0x16
        w32be(&pkt, 8, localSID)
        w32be(&pkt, 12, civRemoteSID)
        pkt[16] = 0xC0; pkt[17] = 0x01
        pkt[19] = UInt8((civDataSeq >> 8) & 0xFF)
        pkt[20] = UInt8(civDataSeq & 0xFF)
        civDataSeq += 1
        pkt[21] = 0x05
        return pkt
    }

    func makeCIVClose() -> [UInt8] {
        var pkt = [UInt8](repeating: 0, count: 22)
        pkt[0] = 0x16
        w32be(&pkt, 8, localSID)
        w32be(&pkt, 12, civRemoteSID)
        pkt[16] = 0xC0; pkt[17] = 0x01
        pkt[19] = UInt8((civDataSeq >> 8) & 0xFF)
        pkt[20] = UInt8(civDataSeq & 0xFF)
        civDataSeq += 1
        pkt[21] = 0x00
        return pkt
    }

    func makeCIVData(_ payload: [UInt8]) -> [UInt8] {
        let total = 21 + payload.count
        var pkt = [UInt8](repeating: 0, count: total)
        pkt[0] = UInt8(total & 0xFF)
        w32be(&pkt, 8, localSID)
        w32be(&pkt, 12, civRemoteSID)
        pkt[16] = 0xC1
        pkt[17] = UInt8(payload.count & 0xFF)
        pkt[19] = UInt8((civDataSeq >> 8) & 0xFF)
        pkt[20] = UInt8(civDataSeq & 0xFF)
        civDataSeq += 1
        for idx in 0 ..< payload.count {
            pkt[21 + idx] = payload[idx]
        }
        return pkt
    }

    func makeCIVFrame(cmd: UInt8, data: [UInt8]? = nil) -> [UInt8] {
        var frame: [UInt8] = [CIV_PREAMBLE, CIV_PREAMBLE, IC705_ADDR, CIV_CONTROLLER, cmd]
        if let data {
            frame.append(contentsOf: data)
        }
        frame.append(CIV_TERMINATOR)
        return frame
    }

    // MARK: - Receive Helpers

    func handlePkt7(_ pkt: [UInt8], sock: UDPSock) {
        guard pkt.count >= 21 else {
            return
        }
        var reply = pkt
        reply[16] = 0x01
        w32be(&reply, 8, localSID)
        w32be(&reply, 12, remoteSID)
        sock.send(reply)
    }

    func handleRetransmit(_ pkt: [UInt8], sock: UDPSock) {
        if pkt.count == 16 {
            let reqSeq = r16le(pkt, 6)
            if let original = txBuf[reqSeq] {
                sock.send(original); sock.send(original)
            } else {
                var idle = [UInt8](repeating: 0, count: 16)
                idle[0] = 0x10
                w16le(&idle, 6, reqSeq)
                w32be(&idle, 8, localSID)
                w32be(&idle, 12, remoteSID)
                sock.send(idle); sock.send(idle)
            }
        }
    }

    func isPkt7(_ pkt: [UInt8]) -> Bool {
        pkt.count == 21 && pkt[4] == 0x07
    }

    func isIdle(_ pkt: [UInt8]) -> Bool {
        pkt.count == 16 && pkt[4] == 0x00
    }

    /// Receive from control, handling pkt7 and idle inline.
    func recvCtrl(
        timeout: TimeInterval = 5.0,
        acceptHeaders: Set<UInt8> = [],
        acceptSizes: Set<Int> = []
    ) -> [UInt8]? {
        let deadline = CFAbsoluteTimeGetCurrent() + timeout
        guard let sock = ctrl else {
            return nil
        }
        while CFAbsoluteTimeGetCurrent() < deadline {
            let remaining = deadline - CFAbsoluteTimeGetCurrent()
            guard remaining > 0 else {
                break
            }
            guard let pkt = sock.recv(timeout: min(remaining, 0.5)) else {
                continue
            }
            guard pkt.count >= 16 else {
                continue
            }

            if isPkt7(pkt) {
                handlePkt7(pkt, sock: sock)
                continue
            }
            if pkt[4] == 0x01 {
                handleRetransmit(pkt, sock: sock)
                continue
            }
            if isIdle(pkt) {
                continue
            }

            if !acceptHeaders.isEmpty, acceptHeaders.contains(pkt[0]) {
                return pkt
            }
            if !acceptSizes.isEmpty, acceptSizes.contains(pkt.count) {
                return pkt
            }
            if acceptHeaders.isEmpty, acceptSizes.isEmpty {
                return pkt
            }
        }
        return nil
    }

    func extractCIVFrames(_ data: [UInt8]) -> [CIVFrame] {
        var frames: [CIVFrame] = []
        var pos = 0
        while pos < data.count {
            // Find preamble
            var start: Int?
            while pos + 1 < data.count {
                if data[pos] == CIV_PREAMBLE, data[pos + 1] == CIV_PREAMBLE {
                    start = pos
                    while (start! + 2) < data.count, data[start! + 2] == CIV_PREAMBLE {
                        start! += 1
                    }
                    break
                }
                pos += 1
            }
            guard let frameStart = start else {
                break
            }
            guard frameStart + 5 < data.count else {
                break
            }
            guard let endIdx = data[(frameStart + 4)...].firstIndex(of: CIV_TERMINATOR) else {
                break
            }
            let frameData = Array(data[(frameStart + 5) ..< endIdx])
            frames.append(CIVFrame(
                to: data[frameStart + 2],
                from: data[frameStart + 3],
                command: data[frameStart + 4],
                data: frameData
            ))
            pos = endIdx + 1
        }
        return frames
    }

    // MARK: - Diagnostic Phases

    func run() {
        print("\n=== IC-705 WiFi Protocol Diagnostic (Swift) ===")
        print("  Target: \(ip):\(CONTROL_PORT)")
        print("  User:   \(username)")
        print("  Pass:   \(String(repeating: "*", count: password.count))")
        if let targetFreqHz {
            print("  Freq:   \(formatFreq(targetFreqHz))")
        }
        print()

        if runTour {
            printPlan()
        }

        do {
            print("=== Phase 1: Network Reachability ===")
            try phaseReachability()

            print("\n=== Phase 2: Login ===")
            try phaseLogin()

            print("\n=== Phase 3: Auth Challenge ===")
            try phaseAuth()

            print("\n=== Phase 4: Stream Negotiation ===")
            try phaseStreams()

            print("\n=== Phase 5: CI-V Stream ===")
            try phaseCIVOpen()

            print("\n=== Phase 6: CI-V Commands ===")
            phaseCIVCommands()

            if runTour {
                print("\n=== Phase 7: VFO Band Tour ===")
                phaseVFOTour()
            } else if let targetFreqHz {
                print("\n=== Phase 7: VFO Set Test ===")
                phaseVFOSet(targetHz: targetFreqHz)
            }

            if !runTour {
                print("\n=== Phase 8: Keepalive ===")
                phaseKeepalive()

                print("\n=== Phase 9: Unsolicited (5s) ===")
                phaseUnsolicited()
            }

        } catch {
            logError("\(error)")
        }

        print("\n=== Cleanup ===")
        disconnect()

        let totalTime = CFAbsoluteTimeGetCurrent() - startTime
        print("  Total session time: \(String(format: "%.1f", totalTime))s")
        print("\n=== Done ===\n")
    }

    func phaseReachability() throws {
        let ctrlSock = UDPSock(host: ip, port: CONTROL_PORT)
        let civSock = UDPSock(host: ip, port: SERIAL_PORT)
        try ctrlSock.open()
        try civSock.open()
        ctrl = ctrlSock
        civ = civSock

        logInfo("Local ctrl port: \(ctrlSock.localPort), CIV port: \(civSock.localPort)")

        // Build localSID from IP + port
        let localIP = (try? resolveLocalIP()) ?? "127.0.0.1"
        let parts = localIP.split(separator: ".").compactMap { UInt32($0) }
        if parts.count == 4 {
            let ipInt = (parts[0] << 24) | (parts[1] << 16) | (parts[2] << 8) | parts[3]
            localSID = ((ipInt << 16) | (UInt32(ctrlSock.localPort) & 0xFFFF))
        } else {
            localSID = UInt32.random(in: 1 ... UInt32.max)
        }
        logInfo("Local SID: 0x\(String(format: "%08X", localSID))")

        // pkt3 x2
        let pkt3 = makePkt3()
        logTX("pkt3 x2", pkt3)
        ctrlSock.send(pkt3); ctrlSock.send(pkt3)

        guard let resp = ctrlSock.recv(timeout: 5.0), resp.count >= 16, resp[4] == 0x04 else {
            logError("No pkt4 response within 5s")
            throw DiagError.timeout("pkt4")
        }
        logRX("pkt4", resp)
        remoteSID = r32be(resp, 8)
        logInfo("Remote SID: 0x\(String(format: "%08X", remoteSID))")
        ctrlSock.drain()

        // pkt6 x2
        let pkt6 = makePkt6()
        logTX("pkt6 x2", pkt6)
        ctrlSock.send(pkt6); ctrlSock.send(pkt6)
        if let ack = recvCtrl(timeout: 3.0, acceptSizes: [16]) {
            logRX("pkt6 ack", ack)
        } else {
            logWarn("No pkt6 ack (continuing)")
        }
        ctrlSock.drain()
    }

    func phaseLogin() throws {
        guard let sock = ctrl else {
            throw DiagError.socket
        }

        var login = makeLogin()
        logTX("login (\(login.count)B, user=\(username))", login)
        sendTracked(sock, &login)

        guard let resp = recvCtrl(timeout: 5.0, acceptHeaders: [0x60, 0x50], acceptSizes: [96, 80, 16])
        else {
            logError("No login response within 5s")
            throw DiagError.timeout("login")
        }
        logRX("login resp (\(resp.count)B, hdr=0x\(String(format: "%02X", resp[0])))", resp)

        // Check 0x50 auth failure
        if resp[0] == 0x50, resp.count >= 51,
           resp[48] == 0xFF, resp[49] == 0xFF, resp[50] == 0xFF
        {
            throw DiagError.auth("credentials rejected (0x50)")
        }

        // Check 0x60 login success
        if resp[0] == 0x60, resp.count == 96 {
            if resp.count > 51, resp[48] == 0xFF, resp[49] == 0xFF,
               resp[50] == 0xFF, resp[51] == 0xFE
            {
                throw DiagError.auth("invalid username/password")
            }
            authID = Array(resp[26 ..< 32])
            logInfo("Login OK — authID: \(authID.map { String(format: "%02X", $0) }.joined())")
            if resp.count >= 80 {
                let nameBytes = Array(resp[64 ..< 80])
                if let name = extractString(nameBytes) {
                    logInfo("Connection type: \(name)")
                }
            }
            return
        }

        // Short 16B confirm (AP mode)
        if resp.count == 16, resp[4] == 0x02 {
            logInfo("Short login confirm (IC-705 AP mode)")
            return
        }

        throw DiagError.auth("unexpected login response (\(resp.count)B)")
    }

    func phaseAuth() throws {
        guard let sock = ctrl else {
            throw DiagError.socket
        }

        var auth1 = makeAuth(magic: 0x02)
        logTX("auth(0x02)", auth1)
        sendTracked(sock, &auth1)

        var idle = makeIdle()
        sendTracked(sock, &idle)

        var auth2 = makeAuth(magic: 0x05)
        logTX("auth(0x05)", auth2)
        sendTracked(sock, &auth2)

        logInfo("Waiting for auth confirm (0x40) and 0xA8 metadata...")
        let deadline = CFAbsoluteTimeGetCurrent() + 10.0
        while CFAbsoluteTimeGetCurrent() < deadline {
            if authOk, a8ReplyID != [UInt8](repeating: 0, count: 16) {
                break
            }

            guard let pkt = recvCtrl(timeout: 1.0, acceptHeaders: [0x40, 0xA8, 0x50]) else {
                var idlePkt = makeIdle()
                sendTracked(sock, &idlePkt)
                continue
            }
            logRX("(\(pkt.count)B, hdr=0x\(String(format: "%02X", pkt[0])))", pkt)

            if pkt[0] == 0x40, pkt.count == 64, pkt[21] == 0x05 {
                authOk = true
                logInfo("Auth confirmed (0x40, byte 21 = 0x05)")
            } else if pkt[0] == 0xA8, pkt.count >= 82 {
                a8ReplyID = Array(pkt[66 ..< 82])
                logInfo("0xA8 received — a8replyID: \(a8ReplyID.map { String(format: "%02X", $0) }.joined())")
                if pkt.count > 114 {
                    if let name = extractString(Array(pkt[82 ..< min(114, pkt.count)])) {
                        logInfo("Radio: \(name)")
                    }
                }
            }
        }

        guard authOk else {
            throw DiagError.auth("auth confirm timeout")
        }
        guard a8ReplyID != [UInt8](repeating: 0, count: 16) else {
            throw DiagError.auth("0xA8 timeout")
        }
    }

    func phaseStreams() throws {
        guard let sock = ctrl else {
            throw DiagError.socket
        }

        var connInfo = makeConnInfo()
        logTX("connInfo (\(connInfo.count)B)", connInfo)
        sendTracked(sock, &connInfo)

        let deadline = CFAbsoluteTimeGetCurrent() + 10.0
        while CFAbsoluteTimeGetCurrent() < deadline {
            guard let pkt = recvCtrl(timeout: 1.0, acceptHeaders: [0x90, 0x50, 0x40]) else {
                var idlePkt = makeIdle()
                sendTracked(sock, &idlePkt)
                continue
            }
            logRX("(\(pkt.count)B, hdr=0x\(String(format: "%02X", pkt[0])))", pkt)

            if pkt[0] == 0x90, pkt.count == 144, pkt[96] == 0x01 {
                logInfo("ConnInfo SUCCESS (byte 96 = 0x01)")
                let newRemote = r32be(pkt, 8)
                let newLocal = r32be(pkt, 12)
                if newRemote != 0 {
                    remoteSID = newRemote
                }
                if newLocal != 0 {
                    localSID = newLocal
                }
                if pkt.count >= 32 {
                    authID = Array(pkt[26 ..< 32])
                }
                logInfo(
                    "SIDs updated: local=0x\(String(format: "%08X", localSID)) remote=0x\(String(format: "%08X", remoteSID))"
                )
                if let name = extractString(Array(pkt[64 ..< 96])) {
                    logInfo("Device: \(name)")
                }
                return
            } else if pkt[0] == 0x90 {
                logInfo("0x90 with byte 96 = 0x\(String(format: "%02X", pkt[96])) (not grant yet)")
            }
        }
        throw DiagError.timeout("connInfo grant")
    }

    func phaseCIVOpen() throws {
        guard let civSock = civ else {
            throw DiagError.socket
        }

        // CIV port: pkt3 x2 -> pkt4 -> pkt6 x2 -> open
        var civPkt3 = [UInt8](repeating: 0, count: 16)
        civPkt3[0] = 0x10; civPkt3[4] = 0x03
        w32be(&civPkt3, 8, localSID)
        w32be(&civPkt3, 12, remoteSID)
        logTX("CIV pkt3 x2", civPkt3)
        civSock.send(civPkt3); civSock.send(civPkt3)

        // Wait for CIV pkt4, filtering pkt7 pings that arrive first
        let civPkt4Deadline = CFAbsoluteTimeGetCurrent() + 3.0
        var gotCIVPkt4 = false
        while CFAbsoluteTimeGetCurrent() < civPkt4Deadline {
            guard let resp = civSock.recv(timeout: 0.5) else {
                continue
            }
            guard resp.count >= 16 else {
                continue
            }
            // Filter pkt7 pings on CIV channel
            if resp.count == 21, resp[4] == 0x07, resp[16] == 0x00 {
                var reply = resp
                reply[16] = 0x01
                w32be(&reply, 8, localSID)
                w32be(&reply, 12, remoteSID)
                civSock.send(reply)
                logInfo("Filtered pkt7 during CIV pkt4 wait")
                continue
            }
            if resp[4] == 0x04 {
                logRX("CIV pkt4", resp)
                civRemoteSID = r32be(resp, 8)
                logInfo(
                    "CIV remoteSID: 0x\(String(format: "%08X", civRemoteSID)) (control was 0x\(String(format: "%08X", remoteSID)))"
                )
                gotCIVPkt4 = true
                break
            }
            logInfo("Skipped non-pkt4 (\(resp.count)B, type=0x\(String(format: "%02X", resp[4])))")
        }
        guard gotCIVPkt4 else {
            throw DiagError.timeout("CIV pkt4")
        }
        civSock.drain()

        var civPkt6 = [UInt8](repeating: 0, count: 16)
        civPkt6[0] = 0x10; civPkt6[4] = 0x06; civPkt6[6] = 0x01
        w32be(&civPkt6, 8, localSID)
        w32be(&civPkt6, 12, civRemoteSID)
        logTX("CIV pkt6 x2", civPkt6)
        civSock.send(civPkt6); civSock.send(civPkt6)
        civSock.drain()

        // Close any stale CIV session from a previous crashed connection
        var closePkt = makeCIVClose()
        logTX("CIV close (preemptive)", closePkt)
        sendTracked(civSock, &closePkt, isCIV: true)
        Thread.sleep(forTimeInterval: 0.2)
        civSock.drain()

        var openPkt = makeCIVOpen()
        logTX("CIV open (0xC0/0x05)", openPkt)
        sendTracked(civSock, &openPkt, isCIV: true)

        Thread.sleep(forTimeInterval: 0.3)

        // Filtered receive: handle pkt7/retransmit during CIV open
        let openDeadline = CFAbsoluteTimeGetCurrent() + 2.0
        var openResps = 0
        while CFAbsoluteTimeGetCurrent() < openDeadline {
            // Service control pkt7
            if let ctrlPkt = ctrl?.recv(timeout: 0) {
                if isPkt7(ctrlPkt) {
                    handlePkt7(ctrlPkt, sock: ctrl!)
                }
            }
            guard let rx = civSock.recv(timeout: 0.2) else {
                if openResps > 0 {
                    break
                }
                continue
            }
            guard rx.count >= 16 else {
                continue
            }
            openResps += 1
            let pktType = rx[4]
            let marker = rx.count > 16 ? rx[16] : 0
            let seq = r16le(rx, 6)
            logRX(
                "CIV resp \(rx.count)B type=0x\(String(format: "%02X", pktType)) seq=\(seq) marker=0x\(String(format: "%02X", marker))"
            )

            // Reply to pkt7 on CIV channel
            if rx.count == 21, pktType == 0x07, marker == 0x00 {
                var reply = rx
                reply[16] = 0x01
                w32be(&reply, 8, localSID)
                w32be(&reply, 12, civRemoteSID)
                civSock.send(reply)
                continue
            }
            // Handle retransmit
            if pktType == 0x01 {
                logInfo("Retransmit req during CIV open! seq=\(seq)")
                handleRetransmit(rx, sock: civSock)
                continue
            }
        }
        logInfo("CI-V stream opened (\(openResps) responses)")
    }

    /// Receive from CIV channel, handling pkt7 pings and idle packets inline.
    /// Also services control channel pkt7 pings to keep the session alive.
    func recvCIV(timeout: TimeInterval = 2.0) -> [[UInt8]] {
        guard let civSock = civ else {
            return []
        }
        var dataPackets: [[UInt8]] = []
        let deadline = CFAbsoluteTimeGetCurrent() + timeout
        while CFAbsoluteTimeGetCurrent() < deadline {
            let remaining = deadline - CFAbsoluteTimeGetCurrent()
            guard remaining > 0 else {
                break
            }

            // Service control channel pkt7 non-blockingly
            if let ctrlPkt = ctrl?.recv(timeout: 0) {
                if isPkt7(ctrlPkt) {
                    handlePkt7(ctrlPkt, sock: ctrl!)
                }
            }

            guard let pkt = civSock.recv(timeout: min(remaining, 0.1)) else {
                if !dataPackets.isEmpty {
                    break
                }
                continue
            }
            guard pkt.count >= 16 else {
                continue
            }

            // Reply to pkt7 on CIV channel
            if pkt.count == 21, pkt[4] == 0x07, pkt[16] == 0x00 {
                var reply = pkt
                reply[16] = 0x01
                w32be(&reply, 8, localSID)
                w32be(&reply, 12, civRemoteSID)
                civSock.send(reply)
                continue
            }

            // Skip idles
            if pkt.count == 16, pkt[4] == 0x00 {
                continue
            }
            // Handle retransmit
            if pkt[4] == 0x01 {
                handleRetransmit(pkt, sock: civSock); continue
            }

            dataPackets.append(pkt)
        }
        return dataPackets
    }

    func phaseCIVCommands() {
        guard civ != nil else {
            return
        }

        let commands: [(String, UInt8, [UInt8]?)] = [
            ("Read Freq", CIV_READ_FREQ, nil),
            ("Read Mode", CIV_READ_MODE, nil),
            ("Read S-Meter", 0x15, [0x02]),
            ("Read ID", 0x19, [0x00]),
        ]

        for (label, cmd, sub) in commands {
            print("  --- \(label) ---")
            let frame = makeCIVFrame(cmd: cmd, data: sub)
            var pkt = makeCIVData(frame)
            logTX("CI-V \(label)", pkt)
            sendTracked(civ!, &pkt, isCIV: true)

            let resps = recvCIV(timeout: 2.0)
            for rx in resps {
                logRX("\(label) resp (\(rx.count)B)", rx)
                if rx.count > 21, rx[16] == 0xC1 {
                    let civPayload = Array(rx[21...])
                    let frames = extractCIVFrames(civPayload)
                    for fr in frames {
                        if fr.command == CIV_READ_FREQ || fr.command == 0x05,
                           let hz = parseBCDFreq(fr.data)
                        {
                            logInfo("Frequency: \(formatFreq(hz))")
                        }
                        if fr.command == CIV_READ_MODE || fr.command == 0x06,
                           let first = fr.data.first
                        {
                            let mode = CIV_MODES[first] ?? "0x\(String(format: "%02X", first))"
                            logInfo("Mode: \(mode)")
                        }
                        if fr.command == CIV_ACK {
                            logInfo("ACK")
                        }
                        if fr.command == CIV_NAK {
                            logWarn("NAK")
                        }
                    }
                }
            }
            if resps.isEmpty {
                logWarn("No CI-V data response (only pkt7/idle filtered)")
            }
        }
    }

    /// Read current VFO, set to target frequency, verify, then restore original.
    func phaseVFOSet(targetHz: Int) {
        guard let civSock = civ else {
            return
        }

        // Step 1: Read current frequency
        print("  --- Read current VFO ---")
        let readFrame = makeCIVFrame(cmd: CIV_READ_FREQ)
        var readPkt = makeCIVData(readFrame)
        logTX("CI-V Read Freq", readPkt)
        sendTracked(civSock, &readPkt, isCIV: true)

        var originalHz: Int?
        let readResps = recvCIV(timeout: 2.0)
        for rx in readResps {
            if rx.count > 21, rx[16] == 0xC1 {
                let payload = Array(rx[21...])
                for fr in extractCIVFrames(payload) {
                    if fr.command == CIV_READ_FREQ || fr.command == CIV_SET_FREQ,
                       let hz = parseBCDFreq(fr.data)
                    {
                        originalHz = hz
                        logInfo("Current VFO: \(formatFreq(hz))")
                    }
                }
            }
        }
        guard let originalHz else {
            logError("Could not read current frequency")
            return
        }

        // Step 2: Set to target frequency
        print("  --- Set VFO to \(formatFreq(targetHz)) ---")
        let bcd = encodeBCDFreq(targetHz)
        let setFrame = makeCIVFrame(cmd: CIV_SET_FREQ, data: bcd)
        var setPkt = makeCIVData(setFrame)
        logTX("CI-V Set Freq \(formatFreq(targetHz))", setPkt)
        sendTracked(civSock, &setPkt, isCIV: true)

        var gotAck = false
        let setResps = recvCIV(timeout: 2.0)
        for rx in setResps {
            if rx.count > 21, rx[16] == 0xC1 {
                let payload = Array(rx[21...])
                for fr in extractCIVFrames(payload) {
                    if fr.command == CIV_ACK {
                        gotAck = true
                        logInfo("Set freq ACK")
                    }
                    if fr.command == CIV_NAK {
                        logWarn("Set freq NAK!")
                    }
                    if fr.command == CIV_SET_FREQ,
                       let hz = parseBCDFreq(fr.data)
                    {
                        logInfo("Radio echoed: \(formatFreq(hz))")
                    }
                }
            }
        }

        // Step 3: Read back to verify
        print("  --- Verify VFO ---")
        var verifyPkt = makeCIVData(readFrame)
        sendTracked(civSock, &verifyPkt, isCIV: true)
        let verifyResps = recvCIV(timeout: 2.0)
        for rx in verifyResps {
            if rx.count > 21, rx[16] == 0xC1 {
                let payload = Array(rx[21...])
                for fr in extractCIVFrames(payload) {
                    if fr.command == CIV_READ_FREQ || fr.command == CIV_SET_FREQ,
                       let hz = parseBCDFreq(fr.data)
                    {
                        if hz == targetHz {
                            logInfo("VERIFIED: VFO is now \(formatFreq(hz))")
                        } else {
                            logWarn("MISMATCH: expected \(formatFreq(targetHz)), got \(formatFreq(hz))")
                        }
                    }
                }
            }
        }

        // Step 4: Restore original frequency
        print("  --- Restore VFO to \(formatFreq(originalHz)) ---")
        let restoreBcd = encodeBCDFreq(originalHz)
        let restoreFrame = makeCIVFrame(cmd: CIV_SET_FREQ, data: restoreBcd)
        var restorePkt = makeCIVData(restoreFrame)
        logTX("CI-V Restore Freq", restorePkt)
        sendTracked(civSock, &restorePkt, isCIV: true)

        let restoreResps = recvCIV(timeout: 2.0)
        for rx in restoreResps {
            if rx.count > 21, rx[16] == 0xC1 {
                let payload = Array(rx[21...])
                for fr in extractCIVFrames(payload) {
                    if fr.command == CIV_ACK {
                        logInfo("Restore ACK — back to \(formatFreq(originalHz))")
                    }
                    if fr.command == CIV_NAK {
                        logWarn("Restore NAK!")
                    }
                }
            }
        }

        if !gotAck {
            logWarn("Never received ACK for set frequency")
        }
    }

    func printPlan() {
        let totalDwell = Int(dwellSeconds) * IC705Diag.tourStops.count
        let estimatedMinutes = (totalDwell + 30) / 60 // +30s for handshake/commands overhead
        print("=== Test Plan ===")
        print("  1. Connect to IC-705 at \(ip) (UDP handshake, login, auth)")
        print("  2. Open CI-V serial stream on port \(SERIAL_PORT)")
        print("  3. Read current VFO frequency and mode")
        print("  4. VFO tour — \(IC705Diag.tourStops.count) bands, ~\(Int(dwellSeconds))s each:")
        for (idx, stop) in IC705Diag.tourStops.enumerated() {
            let letter = String(UnicodeScalar(UInt8(0x61) + UInt8(idx)))
            print("     \(letter). \(formatFreq(stop.freqHz)) (\(stop.band) \(stop.activity))")
        }
        print("  5. Restore original VFO frequency")
        print("  6. Disconnect cleanly (deauth + pkt5)")
        print()
        print("  Estimated duration: ~\(estimatedMinutes) minutes")
        print("  Reauth sent every \(Int(reauthInterval))s to prevent session timeout")
        print("  Channels serviced continuously (pkt7, idle, retransmit)")
        print()
    }

    func phaseVFOTour() {
        guard let civSock = civ else {
            return
        }

        // Read original frequency to restore later
        print("  --- Read original VFO ---")
        let readFrame = makeCIVFrame(cmd: CIV_READ_FREQ)
        var readPkt = makeCIVData(readFrame)
        sendTracked(civSock, &readPkt, isCIV: true)

        var originalHz: Int?
        for rx in recvCIV(timeout: 2.0) {
            if rx.count > 21, rx[16] == 0xC1 {
                for fr in extractCIVFrames(Array(rx[21...])) {
                    if fr.command == CIV_READ_FREQ || fr.command == CIV_SET_FREQ,
                       let hz = parseBCDFreq(fr.data)
                    {
                        originalHz = hz
                        logInfo("Original VFO: \(formatFreq(hz))")
                    }
                }
            }
        }

        // Initialize reauth timer from session start
        lastReauthTime = CFAbsoluteTimeGetCurrent()

        // Tour each band
        for (idx, stop) in IC705Diag.tourStops.enumerated() {
            let stepNum = idx + 1
            print(
                "\n  --- Tour \(stepNum)/\(IC705Diag.tourStops.count): \(stop.band) \(stop.activity) (\(formatFreq(stop.freqHz))) ---"
            )

            // Set frequency
            let bcd = encodeBCDFreq(stop.freqHz)
            let setFrame = makeCIVFrame(cmd: CIV_SET_FREQ, data: bcd)
            var setPkt = makeCIVData(setFrame)
            logTX("Set VFO \(formatFreq(stop.freqHz))")
            sendTracked(civSock, &setPkt, isCIV: true)

            var gotAck = false
            for rx in recvCIV(timeout: 2.0) {
                if rx.count > 21, rx[16] == 0xC1 {
                    for fr in extractCIVFrames(Array(rx[21...])) {
                        if fr.command == CIV_ACK {
                            gotAck = true
                        }
                        if fr.command == CIV_NAK {
                            logWarn("NAK for \(stop.band)!")
                        }
                    }
                }
            }
            if gotAck {
                logInfo("ACK — tuned to \(stop.band)")
            } else {
                logWarn("No ACK for \(stop.band)")
            }

            // Read back to verify
            var verifyPkt = makeCIVData(readFrame)
            sendTracked(civSock, &verifyPkt, isCIV: true)
            for rx in recvCIV(timeout: 2.0) {
                if rx.count > 21, rx[16] == 0xC1 {
                    for fr in extractCIVFrames(Array(rx[21...])) {
                        if fr.command == CIV_READ_FREQ || fr.command == CIV_SET_FREQ,
                           let hz = parseBCDFreq(fr.data)
                        {
                            if hz == stop.freqHz {
                                logInfo("Verified: \(formatFreq(hz))")
                            } else {
                                logWarn("Mismatch: expected \(formatFreq(stop.freqHz)), got \(formatFreq(hz))")
                            }
                        }
                    }
                }
            }

            // Dwell on this frequency
            logInfo("Dwelling \(Int(dwellSeconds))s on \(stop.band)...")
            dwell(seconds: dwellSeconds)
            logInfo("Done with \(stop.band)")
        }

        // Restore original frequency
        if let originalHz {
            print("\n  --- Restore VFO to \(formatFreq(originalHz)) ---")
            let restoreBcd = encodeBCDFreq(originalHz)
            let restoreFrame = makeCIVFrame(cmd: CIV_SET_FREQ, data: restoreBcd)
            var restorePkt = makeCIVData(restoreFrame)
            logTX("Restore VFO")
            sendTracked(civSock, &restorePkt, isCIV: true)
            for rx in recvCIV(timeout: 2.0) {
                if rx.count > 21, rx[16] == 0xC1 {
                    for fr in extractCIVFrames(Array(rx[21...])) {
                        if fr.command == CIV_ACK {
                            logInfo("Restored to \(formatFreq(originalHz))")
                        }
                    }
                }
            }
        }
    }

    func phaseKeepalive() {
        guard let sock = ctrl else {
            return
        }
        let pkt7 = makePkt7()
        logTX("pkt7 (keepalive)", pkt7)
        sock.send(pkt7)
        if let resp = sock.recv(timeout: 2.0) {
            logRX("pkt7 reply (\(resp.count)B)", resp)
            if resp.count >= 17, resp[16] == 0x01 {
                logInfo("Keepalive OK")
            }
        } else {
            logWarn("No keepalive reply")
        }
    }

    func phaseUnsolicited() {
        guard let civSock = civ else {
            return
        }
        logInfo("Listening for unsolicited CI-V data for 5 seconds...")
        let deadline = CFAbsoluteTimeGetCurrent() + 5.0
        var civCount = 0
        var totalCount = 0
        while CFAbsoluteTimeGetCurrent() < deadline {
            // Service control channel pkt7
            if let ctrlPkt = ctrl?.recv(timeout: 0) {
                if isPkt7(ctrlPkt) {
                    handlePkt7(ctrlPkt, sock: ctrl!)
                }
            }

            guard let pkt = civSock.recv(timeout: 0.3) else {
                continue
            }
            totalCount += 1

            // Reply to pkt7 on CIV channel
            if pkt.count == 21, pkt[4] == 0x07, pkt[16] == 0x00 {
                var reply = pkt
                reply[16] = 0x01
                w32be(&reply, 8, localSID)
                w32be(&reply, 12, civRemoteSID)
                civSock.send(reply)
                continue
            }
            // Skip idles
            if pkt.count == 16, pkt[4] == 0x00 {
                continue
            }

            if pkt.count > 21, pkt[16] == 0xC1 {
                civCount += 1
                let civPayload = Array(pkt[21...])
                let frames = extractCIVFrames(civPayload)
                for fr in frames {
                    if fr.command == CIV_READ_FREQ || fr.command == 0x05,
                       let hz = parseBCDFreq(fr.data)
                    {
                        logRX("Unsolicited freq: \(formatFreq(hz))")
                    } else if fr.command == CIV_READ_MODE || fr.command == 0x06,
                              let first = fr.data.first
                    {
                        let mode = CIV_MODES[first] ?? "0x\(String(format: "%02X", first))"
                        logRX("Unsolicited mode: \(mode)")
                    } else {
                        logRX("Unsolicited cmd=0x\(String(format: "%02X", fr.command)) (\(fr.data.count)B data)")
                    }
                }
            } else {
                logRX(
                    "Non-CIV packet (\(pkt.count)B, marker=0x\(String(format: "%02X", pkt.count > 16 ? pkt[16] : 0)))"
                )
            }
        }
        logInfo("Received \(totalCount) total, \(civCount) CI-V data packets")
    }

    func disconnect() {
        // Close CIV session so the radio releases it for the next connection
        if let civSock = civ {
            var closePkt = makeCIVClose()
            sendTracked(civSock, &closePkt, isCIV: true)
            Thread.sleep(forTimeInterval: 0.1)
        }

        if let sock = ctrl {
            var deauth = makeAuth(magic: 0x01)
            sendTracked(sock, &deauth)
            Thread.sleep(forTimeInterval: 0.1)
            let pkt5 = makePkt5()
            sock.send(pkt5); sock.send(pkt5)
            Thread.sleep(forTimeInterval: 0.5)
        }
        ctrl?.close()
        civ?.close()
        logInfo("Disconnected")
    }

    // MARK: - Helpers

    func resolveLocalIP() throws -> String {
        let sock = socket(AF_INET, SOCK_DGRAM, 0)
        defer { Darwin.close(sock) }
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = UInt16(80).bigEndian
        inet_pton(AF_INET, ip, &addr.sin_addr)
        _ = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                connect(sock, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        var localAddr = sockaddr_in()
        var addrLen = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &localAddr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                getsockname(sock, sockPtr, &addrLen)
            }
        }
        var buf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        var addrCopy = localAddr.sin_addr
        inet_ntop(AF_INET, &addrCopy, &buf, socklen_t(INET_ADDRSTRLEN))
        return String(cString: buf)
    }

    func extractString(_ bytes: [UInt8]) -> String? {
        if let nullIdx = bytes.firstIndex(of: 0) {
            let trimmed = Array(bytes[0 ..< nullIdx])
            let str = String(bytes: trimmed, encoding: .ascii)
            return str?.isEmpty == true ? nil : str
        }
        let str = String(bytes: bytes, encoding: .ascii)
        return str?.isEmpty == true ? nil : str
    }
}

// MARK: - Main

func printUsage() {
    print("""
    IC-705 WiFi Protocol Diagnostic Tool (Swift)

    Usage:
      swift ic705_diag.swift --user <username> --pass <password> [--ip <address>] [--tour]

    Options:
      --user    Radio username (required)
      --pass    Radio password (required)
      --ip      Radio IP address (default: 192.168.59.1)
      --freq    Target frequency in MHz to test VFO set (e.g. 14.074)
      --tour    Run multi-band VFO tour (~5 min session with reauth)
      --help    Show this help

    Prerequisites:
      1. Enable WiFi: MENU > SET > WLAN Set > WLAN > ON
      2. Enable remote: MENU > SET > WLAN Set > Remote Settings > Network Control > ON
      3. Set credentials: MENU > SET > WLAN Set > Remote Settings > Network User1
    """)
}

var args = CommandLine.arguments.dropFirst()
var ip = "192.168.59.1"
var username: String?
var password: String?
var freqMHz: Double?
var tour = false

while let arg = args.first {
    args = args.dropFirst()
    switch arg {
    case "--ip":
        guard let val = args.first else {
            printUsage(); exit(1)
        }
        ip = val; args = args.dropFirst()
    case "--user":
        guard let val = args.first else {
            printUsage(); exit(1)
        }
        username = val; args = args.dropFirst()
    case "--pass":
        guard let val = args.first else {
            printUsage(); exit(1)
        }
        password = val; args = args.dropFirst()
    case "--freq":
        guard let val = args.first, let mhz = Double(val) else {
            printUsage(); exit(1)
        }
        freqMHz = mhz; args = args.dropFirst()
    case "--tour":
        tour = true
    case "--help",
         "-h":
        printUsage(); exit(0)
    default:
        print("Unknown option: \(arg)")
        printUsage(); exit(1)
    }
}

guard let username, let password else {
    print("Error: --user and --pass are required\n")
    printUsage()
    exit(1)
}

let targetHz = freqMHz.map { Int($0 * 1_000_000) }
let diag = IC705Diag(ip: ip, username: username, password: password, targetFreqHz: targetHz, runTour: tour)
diag.run()
