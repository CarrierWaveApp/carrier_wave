import Darwin
import Foundation

// MARK: - Tracked Send

extension IcomWiFiTransport {
    /// Send a tracked packet: overwrite bytes 6-7 with seq, store in txBuffer.
    func sendTracked(
        _ pkt: inout Data, channel: UDPChannel, isCIV: Bool = false
    ) {
        let seq: UInt16
        if isCIV {
            seq = civTrackedSeq
            civTrackedSeq += 1
        } else {
            seq = trackedSeq
            trackedSeq += 1
        }
        writeUInt16LE(&pkt, offset: 6, value: seq)
        txBuffer[seq] = pkt
        channel.send(pkt)

        // Prune oldest entries to prevent unbounded growth
        if txBuffer.count > maxTxBufferSize {
            let sortedKeys = txBuffer.keys.sorted()
            let removeCount = txBuffer.count - maxTxBufferSize
            for key in sortedKeys.prefix(removeCount) {
                txBuffer.removeValue(forKey: key)
            }
        }
    }
}

// MARK: - Packet Builders

extension IcomWiFiTransport {
    func buildPkt3(remoteSID sid: UInt32? = nil) -> Data {
        var pkt = Data(count: RSBA1PacketSize.ping)
        pkt[0] = 0x10; pkt[4] = 0x03
        writeUInt32BE(&pkt, offset: 8, value: localSID)
        writeUInt32BE(&pkt, offset: 12, value: sid ?? remoteSID)
        return pkt
    }

    func buildPkt6(remoteSID sid: UInt32? = nil) -> Data {
        var pkt = Data(count: RSBA1PacketSize.ping)
        pkt[0] = 0x10; pkt[4] = 0x06; pkt[6] = 0x01
        writeUInt32BE(&pkt, offset: 8, value: localSID)
        writeUInt32BE(&pkt, offset: 12, value: sid ?? remoteSID)
        return pkt
    }

    func buildPkt5() -> Data {
        var pkt = Data(count: RSBA1PacketSize.ping)
        pkt[0] = 0x10; pkt[4] = 0x05
        writeUInt32BE(&pkt, offset: 8, value: localSID)
        writeUInt32BE(&pkt, offset: 12, value: remoteSID)
        return pkt
    }

    func buildLoginPacket() -> Data {
        var pkt = Data(count: RSBA1PacketSize.login)
        pkt[0] = 0x80
        writeUInt32BE(&pkt, offset: 8, value: localSID)
        writeUInt32BE(&pkt, offset: 12, value: remoteSID)
        pkt[19] = 0x70
        pkt[20] = 0x01
        pkt[23] = UInt8(authInnerSeq & 0xFF)
        pkt[24] = UInt8((authInnerSeq >> 8) & 0xFF)
        authInnerSeq += 1
        pkt[26] = UInt8.random(in: 0 ... 255)
        pkt[27] = UInt8.random(in: 0 ... 255)
        pkt.replaceSubrange(64 ..< 80, with: encodePasscode(config.username))
        pkt.replaceSubrange(80 ..< 96, with: encodePasscode(config.password))
        let nameBytes = Array("icom-cw\0".utf8)
        for idx in 0 ..< min(nameBytes.count, 8) {
            pkt[96 + idx] = nameBytes[idx]
        }
        return pkt
    }

    func buildAuthPacket(magic: UInt8) -> Data {
        var pkt = Data(count: RSBA1PacketSize.authChallenge)
        pkt[0] = 0x40
        writeUInt32BE(&pkt, offset: 8, value: localSID)
        writeUInt32BE(&pkt, offset: 12, value: remoteSID)
        pkt[19] = 0x30
        pkt[20] = 0x01
        pkt[21] = magic
        pkt[23] = UInt8(authInnerSeq & 0xFF)
        pkt[24] = UInt8((authInnerSeq >> 8) & 0xFF)
        authInnerSeq += 1
        for idx in 0 ..< min(authID.count, 6) {
            pkt[26 + idx] = authID[idx]
        }
        return pkt
    }

    func buildConnInfoPacket() -> Data {
        var pkt = Data(count: RSBA1PacketSize.connInfo)
        pkt[0] = 0x90
        writeUInt32BE(&pkt, offset: 8, value: localSID)
        writeUInt32BE(&pkt, offset: 12, value: remoteSID)
        pkt[19] = 0x80
        pkt[20] = 0x01
        pkt[21] = 0x03
        pkt[23] = UInt8(authInnerSeq & 0xFF)
        pkt[24] = UInt8((authInnerSeq >> 8) & 0xFF)
        authInnerSeq += 1
        for idx in 0 ..< min(authID.count, 6) {
            pkt[26 + idx] = authID[idx]
        }
        for idx in 0 ..< min(a8ReplyID.count, 16) {
            pkt[32 + idx] = a8ReplyID[idx]
        }
        let radioName = Array("IC-705\0\0".utf8)
        for idx in 0 ..< min(radioName.count, 8) {
            pkt[64 + idx] = radioName[idx]
        }
        pkt.replaceSubrange(96 ..< 112, with: encodePasscode(config.username))
        pkt[112] = 0x01
        pkt[113] = 0x01
        pkt[114] = 0x04
        pkt[115] = 0x04
        writeUInt16BE(&pkt, offset: 118, value: 48_000)
        writeUInt16BE(&pkt, offset: 122, value: 48_000)
        writeUInt16BE(&pkt, offset: 126, value: RSBA1Ports.serial)
        writeUInt16BE(&pkt, offset: 130, value: RSBA1Ports.audio)
        writeUInt16BE(&pkt, offset: 134, value: 300)
        pkt[136] = 0x01
        return pkt
    }

    func buildPkt7Request() -> Data {
        var pkt = Data(count: RSBA1PacketSize.pingExtended)
        pkt[0] = 0x15; pkt[4] = 0x07
        let seq = pingSeq
        pingSeq += 1
        writeUInt16LE(&pkt, offset: 6, value: seq)
        writeUInt32BE(&pkt, offset: 8, value: localSID)
        writeUInt32BE(&pkt, offset: 12, value: remoteSID)
        pkt[16] = 0x00
        pkt[17] = UInt8.random(in: 0 ... 255)
        pkt[18] = UInt8(seq & 0xFF)
        pkt[19] = UInt8((seq >> 8) & 0xFF)
        pkt[20] = 0x06
        return pkt
    }

    func buildIdlePacket() -> Data {
        var pkt = Data(count: RSBA1PacketSize.ping)
        pkt[0] = 0x10
        writeUInt32BE(&pkt, offset: 8, value: localSID)
        writeUInt32BE(&pkt, offset: 12, value: remoteSID)
        return pkt
    }

    func buildCIVIdlePacket() -> Data {
        var pkt = Data(count: RSBA1PacketSize.ping)
        pkt[0] = 0x10
        writeUInt32BE(&pkt, offset: 8, value: localSID)
        writeUInt32BE(&pkt, offset: 12, value: civRemoteSID)
        return pkt
    }

    func buildCIVOpenPacket() -> Data {
        var pkt = Data(count: 22)
        pkt[0] = 0x16
        writeUInt32BE(&pkt, offset: 8, value: localSID)
        writeUInt32BE(&pkt, offset: 12, value: civRemoteSID)
        pkt[16] = 0xC0
        pkt[17] = 0x01
        pkt[19] = UInt8((civDataSeq >> 8) & 0xFF)
        pkt[20] = UInt8(civDataSeq & 0xFF)
        civDataSeq += 1
        pkt[21] = 0x05
        return pkt
    }

    func buildCIVClosePacket() -> Data {
        var pkt = Data(count: 22)
        pkt[0] = 0x16
        writeUInt32BE(&pkt, offset: 8, value: localSID)
        writeUInt32BE(&pkt, offset: 12, value: civRemoteSID)
        pkt[16] = 0xC0
        pkt[17] = 0x01
        pkt[19] = UInt8((civDataSeq >> 8) & 0xFF)
        pkt[20] = UInt8(civDataSeq & 0xFF)
        civDataSeq += 1
        pkt[21] = 0x00
        return pkt
    }

    func buildCIVDataPacket(payload: Data) -> Data {
        let headerSize = 21
        let totalSize = headerSize + payload.count
        var pkt = Data(count: totalSize)
        pkt[0] = UInt8(totalSize & 0xFF)
        writeUInt32BE(&pkt, offset: 8, value: localSID)
        writeUInt32BE(&pkt, offset: 12, value: civRemoteSID)
        pkt[16] = 0xC1
        pkt[17] = UInt8(payload.count & 0xFF)
        pkt[19] = UInt8((civDataSeq >> 8) & 0xFF)
        pkt[20] = UInt8(civDataSeq & 0xFF)
        civDataSeq += 1
        pkt.replaceSubrange(headerSize ..< totalSize, with: payload)
        return pkt
    }
}

// MARK: - Binary Helpers

extension IcomWiFiTransport {
    func generateSessionID() -> UInt32 {
        UInt32.random(in: 1 ... UInt32.max)
    }

    /// Derive session ID from local IP + port, matching kappanhang convention.
    /// Falls back to random if local IP resolution fails.
    func deriveSessionID(localPort: UInt16) -> UInt32 {
        guard let ipInt = resolveLocalIPInt() else {
            return generateSessionID()
        }
        return (ipInt << 16) | (UInt32(localPort) & 0xFFFF)
    }

    /// Resolve the local IP address used to reach the radio as a host-order UInt32.
    /// Uses the kernel routing table via a dummy UDP connect.
    private func resolveLocalIPInt() -> UInt32? {
        let sock = socket(AF_INET, SOCK_DGRAM, 0)
        guard sock >= 0 else {
            return nil
        }
        defer { Darwin.close(sock) }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = UInt16(80).bigEndian
        inet_pton(AF_INET, config.ipAddress, &addr.sin_addr)

        let connectResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.connect(sock, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard connectResult == 0 else {
            return nil
        }

        var localAddr = sockaddr_in()
        var addrLen = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &localAddr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                getsockname(sock, sockPtr, &addrLen)
            }
        }

        return UInt32(bigEndian: localAddr.sin_addr.s_addr)
    }

    func writeUInt32BE(_ data: inout Data, offset: Int, value: UInt32) {
        data[offset] = UInt8((value >> 24) & 0xFF)
        data[offset + 1] = UInt8((value >> 16) & 0xFF)
        data[offset + 2] = UInt8((value >> 8) & 0xFF)
        data[offset + 3] = UInt8(value & 0xFF)
    }

    func writeUInt16LE(_ data: inout Data, offset: Int, value: UInt16) {
        data[offset] = UInt8(value & 0xFF)
        data[offset + 1] = UInt8((value >> 8) & 0xFF)
    }

    func writeUInt16BE(_ data: inout Data, offset: Int, value: UInt16) {
        data[offset] = UInt8((value >> 8) & 0xFF)
        data[offset + 1] = UInt8(value & 0xFF)
    }

    func readUInt32BE(_ data: Data, offset: Int) -> UInt32 {
        UInt32(data[offset]) << 24 |
            UInt32(data[offset + 1]) << 16 |
            UInt32(data[offset + 2]) << 8 |
            UInt32(data[offset + 3])
    }

    func readUInt16LE(_ data: Data, offset: Int) -> UInt16 {
        UInt16(data[offset]) | UInt16(data[offset + 1]) << 8
    }
}
