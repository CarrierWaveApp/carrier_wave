import Foundation
import Testing
@testable import CarrierWaveData

// MARK: - Encoding

private func text(_ data: Data) -> String {
    String(bytes: data, encoding: .utf8) ?? "<invalid utf8>"
}

@Test func hamlibMoveAndQuery() {
    let move = RotatorProtocolCodec.moveCommand(
        RotatorPosition(azimuthDeg: 180.04, elevationDeg: 45.26), protocolKind: .hamlibRotctl
    )
    #expect(text(move) == "P 180.0 45.3\n")
    #expect(RotatorProtocolCodec.positionQueries(protocolKind: .hamlibRotctl).map(text) == ["p\n"])
    #expect(text(RotatorProtocolCodec.stopCommand(protocolKind: .hamlibRotctl)) == "S\n")
}

@Test func easycommMoveAndQuery() {
    let move = RotatorProtocolCodec.moveCommand(
        RotatorPosition(azimuthDeg: 180.5, elevationDeg: 45.2), protocolKind: .easycommII
    )
    #expect(text(move) == "AZ180.5 EL45.2\n")
    #expect(RotatorProtocolCodec.positionQueries(protocolKind: .easycommII).map(text) == ["AZ EL\n"])
    #expect(text(RotatorProtocolCodec.stopCommand(protocolKind: .easycommII)) == "SA SE\n")
}

@Test func gs232MoveIsZeroPaddedIntegers() {
    let move = RotatorProtocolCodec.moveCommand(
        RotatorPosition(azimuthDeg: 7.6, elevationDeg: 45.4), protocolKind: .gs232B
    )
    #expect(text(move) == "W008 045\r")
    #expect(RotatorProtocolCodec.positionQueries(protocolKind: .gs232B).map(text) == ["C2\r"])
}

@Test func satXMLMoveQueryAndStop() {
    let move = RotatorProtocolCodec.moveCommand(
        RotatorPosition(azimuthDeg: 180, elevationDeg: 45), protocolKind: .csnSATxml
    )
    #expect(text(move) == "<PST><AZIMUTH>180</AZIMUTH><ELEVATION>45</ELEVATION></PST>")
    #expect(
        RotatorProtocolCodec.positionQueries(protocolKind: .csnSATxml).map(text)
            == ["<PST>AZ?</PST>", "<PST>EL?</PST>"]
    )
    #expect(text(RotatorProtocolCodec.stopCommand(protocolKind: .csnSATxml)) == "<PST><STOP>1</STOP></PST>")
}

@Test func moveNormalizesAzimuthAndClampsElevation() {
    let move = RotatorProtocolCodec.moveCommand(
        RotatorPosition(azimuthDeg: -90, elevationDeg: -5), protocolKind: .easycommII
    )
    #expect(text(move) == "AZ270.0 EL0.0\n")
    let over = RotatorProtocolCodec.moveCommand(
        RotatorPosition(azimuthDeg: 370, elevationDeg: 95), protocolKind: .gs232B
    )
    #expect(text(over) == "W010 090\r")
}

// MARK: - Parsing

@Test func parsesHamlibTwoLineReply() {
    let parsed = RotatorProtocolCodec.parsePosition("180.00\n45.00\n")
    #expect(parsed == .init(azimuthDeg: 180, elevationDeg: 45))
    #expect(RotatorProtocolCodec.parsePosition("RPRT 0") == nil)
    #expect(RotatorProtocolCodec.hamlibReplyIsOK("RPRT 0\n"))
    #expect(!RotatorProtocolCodec.hamlibReplyIsOK("RPRT -1\n"))
}

@Test func parsesEasycommReplies() {
    #expect(RotatorProtocolCodec.parsePosition("AZ180.0 EL45.0") == .init(azimuthDeg: 180, elevationDeg: 45))
    #expect(RotatorProtocolCodec.parsePosition("AZ12.5") == .init(azimuthDeg: 12.5, elevationDeg: nil))
    #expect(RotatorProtocolCodec.parsePosition("EL3.0\r\n") == .init(azimuthDeg: nil, elevationDeg: 3))
}

@Test func parsesGS232Reply() {
    #expect(RotatorProtocolCodec.parsePosition("AZ=180 EL=045\r") == .init(azimuthDeg: 180, elevationDeg: 45))
}

@Test func parsesSATXMLReplies() {
    #expect(RotatorProtocolCodec.parsePosition("AZ:180") == .init(azimuthDeg: 180, elevationDeg: nil))
    #expect(RotatorProtocolCodec.parsePosition("EL:45") == .init(azimuthDeg: nil, elevationDeg: 45))
    let merged = RotatorProtocolCodec.parsePosition("EL:45")?
        .merged(onto: RotatorPosition(azimuthDeg: 10, elevationDeg: 0))
    #expect(merged == RotatorPosition(azimuthDeg: 10, elevationDeg: 45))
}

@Test func rejectsGarbage() {
    #expect(RotatorProtocolCodec.parsePosition("") == nil)
    #expect(RotatorProtocolCodec.parsePosition("<html>PSR-100</html>") == nil)
    #expect(RotatorProtocolCodec.parsePosition("OK") == nil)
}

@Test func detectsProtocolFromReply() {
    #expect(RotatorProtocolCodec.detectProtocol(fromReply: "AZ:180") == .csnSATxml)
    #expect(RotatorProtocolCodec.detectProtocol(fromReply: "AZ=180 EL=045") == .gs232B)
    #expect(RotatorProtocolCodec.detectProtocol(fromReply: "AZ180.0 EL45.0") == .easycommII)
    #expect(RotatorProtocolCodec.detectProtocol(fromReply: "180.00\n45.00\n") == .hamlibRotctl)
    #expect(RotatorProtocolCodec.detectProtocol(fromReply: "RPRT 0") == .hamlibRotctl)
    #expect(RotatorProtocolCodec.detectProtocol(fromReply: "hello") == nil)
}

// MARK: - Positions and endpoints

@Test func axisErrorWrapsAzimuth() {
    let a = RotatorPosition(azimuthDeg: 359, elevationDeg: 10)
    let b = RotatorPosition(azimuthDeg: 1, elevationDeg: 12)
    #expect(a.maxAxisError(to: b) == 2)
}

@Test func endpointDefaultsFollowKindAndProtocol() {
    let sat = TrackerEndpoint(kind: .csnSAT, host: "192.168.1.40")
    #expect(sat.protocolKind == .hamlibRotctl)
    #expect(sat.port == 4_533)
    #expect(sat.replyPort == nil)
    #expect(sat.webURL?.absoluteString == "http://192.168.1.40/")

    let psr = TrackerEndpoint(kind: .psr100, host: "192.168.1.41")
    #expect(psr.protocolKind == .psr100HTTP)
    #expect(psr.port == 8_080)
    #expect(psr.replyPort == nil)
    let udp = TrackerEndpoint(kind: .psr100, host: "192.168.1.41", protocolKind: .easycommII)
    #expect(udp.port == 2_390)
    #expect(udp.replyPort == 2_391)
    #expect(psr.webURL?.absoluteString == "http://192.168.1.41:8080/")

    let xml = TrackerEndpoint(kind: .psr100, host: "10.0.0.5", protocolKind: .csnSATxml)
    #expect(xml.port == 12_000)
    #expect(xml.replyPort == 12_001)
}

@Test func localNetworkHostsSkipSelfAndEdges() {
    let net = TrackerDiscoveryService.LocalNetwork(
        interface: "en0", address: 0xC0A8_0105, mask: 0xFFFF_FF00
    )
    #expect(net.cidr == "192.168.1.0/24")
    #expect(net.broadcastAddress == "192.168.1.255")
    let hosts = net.hosts
    #expect(hosts.count == 253)
    #expect(!hosts.contains("192.168.1.5"))
    #expect(!hosts.contains("192.168.1.0"))
    #expect(!hosts.contains("192.168.1.255"))
    #expect(hosts.first == "192.168.1.1")
}

@Test func cidrParsingWidensToSlash24AndAcceptsBareAddresses() {
    let net = TrackerDiscoveryService.LocalNetwork(cidr: "192.168.20.0/24")
    #expect(net?.cidr == "192.168.20.0/24")
    #expect(net?.hosts.count == 254)
    let bare = TrackerDiscoveryService.LocalNetwork(cidr: "192.168.20.89")
    #expect(bare?.cidr == "192.168.20.0/24")
    #expect(bare?.hosts.contains("192.168.20.89") == true)
    let wide = TrackerDiscoveryService.LocalNetwork(cidr: "10.0.0.0/16")
    #expect(wide?.cidr == "10.0.0.0/24")
    let single = TrackerDiscoveryService.LocalNetwork(cidr: "10.1.2.3/32")
    #expect(single?.cidr == "10.1.2.3/32")
    #expect(single?.hosts.isEmpty == true)
    #expect(TrackerDiscoveryService.LocalNetwork(cidr: "not-an-ip") == nil)
    #expect(TrackerDiscoveryService.LocalNetwork(cidr: "192.168.1.300") == nil)
    #expect(TrackerDiscoveryService.LocalNetwork(cidr: "192.168.1.0/4") == nil)
}

@MainActor
@Test func rememberingAHostLearnsItsNetworkAndSweepsItLater() throws {
    let defaults = try #require(UserDefaults(suiteName: "TrackerDiscoveryTests-\(UUID().uuidString)"))
    let discovery = TrackerDiscoveryService(defaults: defaults)
    discovery.remember(host: "192.0.2.89") // TEST-NET-1: never a local interface
    #expect(discovery.knownHosts.contains("192.0.2.89"))
    #expect(discovery.extraNetworks == ["192.0.2.0/24"])
    #expect(discovery.addNetwork("198.51.100.7") == "198.51.100.0/24")
    #expect(discovery.addNetwork("garbage") == nil)
    discovery.removeNetwork("192.0.2.0/24")
    #expect(!discovery.knownHosts.contains("192.0.2.89"))
    #expect(discovery.extraNetworks == ["198.51.100.0/24"])
    // Persisted for the next launch.
    let again = TrackerDiscoveryService(defaults: defaults)
    #expect(again.extraNetworks == ["198.51.100.0/24"])
}

@Test func psr100HTTPCommandsMatchTheRotorsOwnPage() {
    let move = RotatorProtocolCodec.moveCommand(
        RotatorPosition(azimuthDeg: 180.4, elevationDeg: 45.6), protocolKind: .psr100HTTP
    )
    #expect(text(move) == "AZ180EL46")
    #expect(
        RotatorProtocolCodec.positionQueries(protocolKind: .psr100HTTP).map(text)
            == [RotatorProtocolCodec.statusQueryToken]
    )
    #expect(text(RotatorProtocolCodec.stopCommand(protocolKind: .psr100HTTP)) == "STOP")
    // Moves answer "Command executed: AZ=180 EL=46"; position comes from /data JSON.
    #expect(
        RotatorProtocolCodec.parsePosition("Command executed: AZ=180 EL=46") == .init(azimuthDeg: 180, elevationDeg: 46)
    )
    let json = #"{"azimuth":123,"elevation":45.5,"azTarget":130,"elTarget":45,"uptime":"0:15:17"}"#
    #expect(RotatorProtocolCodec.parsePosition(json) == .init(azimuthDeg: 123, elevationDeg: 45.5))
    #expect(RotatorProtocolCodec.parsePosition(#"{"uptime":"1:00"}"#) == nil)
    #expect(RotatorProtocolCodec.parsePosition("Invalid command format") == nil)
    #expect(RotatorProtocolKind.psr100HTTP.expectsReply)
    #expect(!RotatorProtocolKind.gs232B.expectsReply)
}

@Test func manualJogWrapsAndClamps() {
    let north = RotatorPosition(azimuthDeg: 2, elevationDeg: 0)
    let left = RotatorController.jogged(from: north, dAz: -5, dEl: 0, minElevation: 0)
    #expect(left == RotatorPosition(azimuthDeg: 357, elevationDeg: 0))
    let down = RotatorController.jogged(from: north, dAz: 0, dEl: -5, minElevation: 0)
    #expect(down.elevationDeg == 0)
    let floor = RotatorController.jogged(from: north, dAz: 0, dEl: 3, minElevation: 5)
    #expect(floor.elevationDeg == 5)
    let zenith = RotatorController.jogged(
        from: RotatorPosition(azimuthDeg: 359, elevationDeg: 88), dAz: 15, dEl: 15, minElevation: 0
    )
    #expect(zenith == RotatorPosition(azimuthDeg: 14, elevationDeg: 90))
}
