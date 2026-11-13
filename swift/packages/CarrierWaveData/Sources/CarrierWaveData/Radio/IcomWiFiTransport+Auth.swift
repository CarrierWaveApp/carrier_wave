import Foundation

// MARK: - Authentication Flow

extension IcomWiFiTransport {
    /// Full RS-BA1 authentication handshake on the control port (50001).
    func authenticate() async throws {
        guard let controlChannel else {
            throw IcomWiFiError.notConnected
        }

        try await performConnectionSetup(on: controlChannel)
        let loginResp = try await performLogin(on: controlChannel)

        guard loginResp.count >= 64 else {
            log("short login confirm — skipping auth challenge", nil)
            try await openCIVStream()
            controlChannel.enableStreaming()
            return
        }

        try await performAuthChallenge(on: controlChannel)
        try await waitForAuthAndMetadata(on: controlChannel)
        try await performStreamNegotiation(on: controlChannel)
        try await openCIVStream()
        controlChannel.enableStreaming()
    }

    private func performConnectionSetup(on channel: UDPChannel) async throws {
        let pkt3 = buildPkt3()
        log("TX pkt3 x2", pkt3)
        channel.send(pkt3)
        channel.send(pkt3)

        // Wait for pkt4, filtering pkt7 pings inline. Resend pkt3 every second:
        // the IC-9700 regularly ignores the first pair (bench, 2026-10-04), and
        // without a resend the whole attempt timed out and the UI retried ~7 s
        // later.
        let deadline4 = Date().addingTimeInterval(5.0)
        var lastPkt3 = Date()
        var gotPkt4 = false
        while Date() < deadline4 {
            if Date().timeIntervalSince(lastPkt3) >= 1.0 {
                log("TX pkt3 x2 (resend)", pkt3)
                channel.send(pkt3)
                channel.send(pkt3)
                lastPkt3 = Date()
            }
            guard let resp = await channel.receive(timeout: 0.5) else {
                continue
            }
            guard resp.count >= 16 else {
                continue
            }
            if resp.count == 21, resp[4] == 0x07, resp[16] == 0x00 {
                replyToPkt7(resp, channel: channel)
                continue
            }
            if resp[4] == 0x04 {
                log("RX pkt4", resp)
                remoteSID = readUInt32BE(resp, offset: 8)
                gotPkt4 = true
                break
            }
        }
        guard gotPkt4 else {
            throw IcomWiFiError.connectionTimeout
        }
        await drainChannel(channel)

        let pkt6 = buildPkt6()
        log("TX pkt6 x2", pkt6)
        channel.send(pkt6)
        channel.send(pkt6)
        // pkt6 ack is optional — use filtered receive to handle pkt7
        if let resp = await receiveHandshake(
            channel: channel, acceptSizes: [16], timeout: 3.0
        ) {
            log("RX pkt6 ack", resp)
        }
        await drainChannel(channel)
    }

    private func performLogin(on channel: UDPChannel) async throws -> Data {
        var loginPkt = buildLoginPacket()
        sendTracked(&loginPkt, channel: channel)
        log("TX login (\(loginPkt.count)B)", loginPkt)

        // Login response: 96B (0x60 header) on success, 80B (0x50) on failure,
        // or 16B with pkt[4]==0x02 in AP mode.
        guard let loginResp = await receiveHandshake(
            channel: channel,
            acceptHeaders: [0x60, 0x50],
            acceptSizes: [96, 80, 16],
            timeout: 5.0
        ) else {
            throw IcomWiFiError.connectionTimeout
        }
        log("RX login resp (\(loginResp.count)B)", loginResp)
        try validateLoginResponse(loginResp)
        return loginResp
    }

    private func performAuthChallenge(on channel: UDPChannel) async throws {
        var auth1 = buildAuthPacket(magic: 0x02)
        log("TX auth(0x02)", auth1)
        sendTracked(&auth1, channel: channel)

        var idle = buildIdlePacket()
        sendTracked(&idle, channel: channel)

        var auth2 = buildAuthPacket(magic: 0x05)
        log("TX auth(0x05)", auth2)
        sendTracked(&auth2, channel: channel)
    }

    private func waitForAuthAndMetadata(on channel: UDPChannel) async throws {
        var authOk = false
        var gotA8 = false
        let deadline = Date().addingTimeInterval(10.0)

        while Date() < deadline, !(authOk && gotA8) {
            guard let pkt = await receiveHandshake(
                channel: channel,
                acceptHeaders: [0x40, 0xA8, 0x50],
                timeout: 1.0
            ) else {
                var idlePkt = buildIdlePacket()
                sendTracked(&idlePkt, channel: channel)
                continue
            }

            if pkt[0] == 0x40, pkt.count == 64, pkt[21] == 0x05 {
                authOk = true
                log("auth confirmed", nil)
            } else if pkt[0] == 0xA8, pkt.count >= 82 {
                a8ReplyID = pkt.subdata(in: 66 ..< 82)
                gotA8 = true
                log("0xA8 received", nil)
            }
        }

        guard authOk else {
            throw IcomWiFiError.authenticationFailed(stage: "auth confirm timeout")
        }
        guard gotA8 else {
            throw IcomWiFiError.authenticationFailed(stage: "0xA8 metadata timeout")
        }
    }

    private func performStreamNegotiation(on channel: UDPChannel) async throws {
        var connInfo = buildConnInfoPacket()
        log("TX connInfo (\(connInfo.count)B)", connInfo)
        sendTracked(&connInfo, channel: channel)

        let deadline = Date().addingTimeInterval(10.0)
        while Date() < deadline {
            guard let pkt = await receiveHandshake(
                channel: channel,
                acceptHeaders: [0x90, 0x50, 0x40],
                timeout: 1.0
            ) else {
                var idlePkt = buildIdlePacket()
                sendTracked(&idlePkt, channel: channel)
                continue
            }

            if pkt[0] == 0x90, pkt.count == 144, pkt[96] == 0x01 {
                let newRemote = readUInt32BE(pkt, offset: 8)
                let newLocal = readUInt32BE(pkt, offset: 12)
                if newRemote != 0 {
                    remoteSID = newRemote
                }
                if newLocal != 0 {
                    localSID = newLocal
                }
                if pkt.count >= 32 {
                    authID = pkt.subdata(in: 26 ..< 32)
                }
                log("connInfo grant — SIDs updated", nil)
                return
            }
        }
        throw IcomWiFiError.authenticationFailed(stage: "connInfo grant timeout")
    }

    func openCIVStream() async throws {
        guard let civChannel else {
            throw IcomWiFiError.notConnected
        }

        let civPkt3 = buildPkt3(remoteSID: remoteSID)
        log("TX CIV pkt3 x2", civPkt3)
        civChannel.send(civPkt3)
        civChannel.send(civPkt3)

        // Wait for CIV pkt4, filtering pkt7 pings
        let pkt4Deadline = Date().addingTimeInterval(3.0)
        var gotCIVPkt4 = false
        while Date() < pkt4Deadline {
            guard let resp = await civChannel.receive(timeout: 0.5) else {
                continue
            }
            guard resp.count >= 16 else {
                continue
            }
            if resp.count == 21, resp[4] == 0x07, resp[16] == 0x00 {
                // civRemoteSID not yet known — use control remoteSID (matches diag tool)
                replyToPkt7(resp, channel: civChannel, peerSID: civRemoteSID != 0 ? civRemoteSID : remoteSID)
                continue
            }
            if resp[4] == 0x04 {
                log("RX CIV pkt4", resp)
                civRemoteSID = readUInt32BE(resp, offset: 8)
                gotCIVPkt4 = true
                break
            }
        }
        guard gotCIVPkt4 else {
            throw IcomWiFiError.connectionTimeout
        }

        let civPkt6 = buildPkt6(remoteSID: civRemoteSID)
        log("TX CIV pkt6 x2", civPkt6)
        civChannel.send(civPkt6)
        civChannel.send(civPkt6)
        await drainChannel(civChannel)

        // Close any stale CIV session from a previous crashed connection
        var closePkt = buildCIVClosePacket()
        log("TX CIV close (preemptive)", closePkt)
        sendTracked(&closePkt, channel: civChannel, isCIV: true)
        try? await Task.sleep(for: .milliseconds(200))
        await drainChannel(civChannel)

        var openPkt = buildCIVOpenPacket()
        log("TX CIV open", openPkt)
        sendTracked(&openPkt, channel: civChannel, isCIV: true)

        try await Task.sleep(for: .milliseconds(300))
        await drainCIVChannel(civChannel)
        log("CIV stream opened", nil)
    }

    /// Drain CIV channel after open, handling pkt7 and retransmit inline.
    private func drainCIVChannel(_ channel: UDPChannel) async {
        let deadline = Date().addingTimeInterval(2.0)
        var gotResponse = false
        while Date() < deadline {
            // Service control channel pkt7 during CIV drain
            if let controlChannel,
               let ctrlPkt = await controlChannel.receive(timeout: 0)
            {
                if ctrlPkt.count == 21, ctrlPkt[4] == 0x07, ctrlPkt[16] == 0x00 {
                    replyToPkt7(ctrlPkt, channel: controlChannel)
                }
            }

            guard let resp = await channel.receive(timeout: 0.2) else {
                if gotResponse {
                    break
                }
                continue
            }
            gotResponse = true
            guard resp.count >= 16 else {
                continue
            }
            if resp.count == 21, resp[4] == 0x07, resp[16] == 0x00 {
                replyToPkt7(resp, channel: channel, peerSID: civRemoteSID)
            } else if resp[4] == 0x01 {
                handleRetransmit(resp, channel: channel)
            }
        }
    }

    func validateLoginResponse(_ resp: Data) throws {
        // 0x50 header = auth failure
        if resp[0] == 0x50, resp.count >= 51,
           resp[48] == 0xFF, resp[49] == 0xFF, resp[50] == 0xFF
        {
            throw IcomWiFiError.authenticationFailed(stage: "credentials rejected (0x50)")
        }

        // 0x60 header, 96 bytes = full RS-BA1 login success
        if resp[0] == 0x60, resp.count == 96 {
            // Check credential rejection pattern
            if resp[48] == 0xFF, resp[49] == 0xFF,
               resp[50] == 0xFF, resp[51] == 0xFE
            {
                throw IcomWiFiError.authenticationFailed(stage: "credentials rejected")
            }
            if resp.count >= 32 {
                authID = resp.subdata(in: 26 ..< 32)
            }
            return
        }

        // Short 16B confirm (IC-705 AP mode)
        if resp.count >= 16, resp[4] == 0x02 {
            return
        }

        throw IcomWiFiError.authenticationFailed(
            stage: "unexpected login response (\(resp.count)B, hdr=0x\(String(format: "%02X", resp[0])))"
        )
    }

    /// Receive a handshake packet, handling protocol overhead (pkt7 pings,
    /// retransmit requests, idle pkt0) inline — matching the working diag tool.
    func receiveHandshake(
        channel: UDPChannel,
        acceptHeaders: Set<UInt8> = [],
        acceptSizes: Set<Int> = [],
        timeout: TimeInterval
    ) async -> Data? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else {
                break
            }
            guard let pkt = await channel.receive(
                timeout: min(remaining, 0.5)
            ) else {
                continue
            }
            guard pkt.count >= 16 else {
                continue
            }

            // Reply to pkt7 pings inline — radio expects these during auth
            if pkt.count == 21, pkt[4] == 0x07, pkt[16] == 0x00 {
                replyToPkt7(pkt, channel: channel)
                continue
            }

            // Handle retransmit requests
            if pkt[4] == 0x01 {
                handleRetransmit(pkt, channel: channel)
                continue
            }

            // Skip idle pkt0 (type 0x00, 16 bytes)
            if pkt.count == 16, pkt[4] == 0x00 {
                continue
            }

            // Check accept criteria (mirrors diag tool's recvCtrl)
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

    func replyToPkt7(
        _ pkt: Data, channel: UDPChannel, peerSID: UInt32? = nil
    ) {
        var reply = pkt
        reply[16] = 0x01
        writeUInt32BE(&reply, offset: 8, value: localSID)
        writeUInt32BE(&reply, offset: 12, value: peerSID ?? remoteSID)
        channel.send(reply)
    }

    func handleRetransmit(_ pkt: Data, channel: UDPChannel) {
        guard pkt.count == 16 else {
            return
        }
        let reqSeq = readUInt16LE(pkt, offset: 6)
        if let original = txBuffer[reqSeq] {
            channel.send(original)
            channel.send(original)
        } else {
            var idlePkt = Data(count: 16)
            idlePkt[0] = 0x10
            writeUInt16LE(&idlePkt, offset: 6, value: reqSeq)
            writeUInt32BE(&idlePkt, offset: 8, value: localSID)
            writeUInt32BE(&idlePkt, offset: 12, value: remoteSID)
            channel.send(idlePkt)
            channel.send(idlePkt)
        }
    }

    func drainChannel(_ channel: UDPChannel) async {
        while await channel.receive(timeout: 0.1) != nil {}
    }

    func log(_ msg: String, _ data: Data?) {
        onLog?(msg, data)
    }
}
