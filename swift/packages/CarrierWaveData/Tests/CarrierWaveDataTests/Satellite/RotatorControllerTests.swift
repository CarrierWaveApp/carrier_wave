import Foundation
import Testing
@testable import CarrierWaveData

// MARK: - FakeRotatorTransport

/// Records every command and answers like a PSR-100 web server.
private actor FakeRotatorTransport: RotatorTransport {
    var sent: [String] = []
    var azimuth = 0.0
    var elevation = 0.0

    func connect() async throws {}
    func disconnect() async {}

    func send(_ data: Data, expectReply _: Bool, timeout _: Duration) async throws -> String? {
        let command = String(decoding: data, as: UTF8.self)
        sent.append(command)
        if command == RotatorProtocolCodec.statusQueryToken {
            return "{\"azimuth\":\(azimuth),\"elevation\":\(elevation),\"azTarget\":0,\"elTarget\":0}"
        }
        if command == "STOP" {
            return "Command executed: STOP"
        }
        // Echo the move the way the rotor does and "arrive" instantly.
        if let position = RotatorProtocolCodec.parsePosition(
            command.replacingOccurrences(of: "AZ", with: "AZ=").replacingOccurrences(of: "EL", with: " EL=")
        ) {
            azimuth = position.azimuthDeg ?? azimuth
            elevation = position.elevationDeg ?? elevation
            return "Command executed: AZ=\(Int(azimuth)) EL=\(Int(elevation))"
        }
        return "Invalid command format"
    }
}

@MainActor
private func linkedController() async -> (RotatorController, FakeRotatorTransport) {
    let fake = FakeRotatorTransport()
    let defaults = UserDefaults(suiteName: "RotatorControllerTests-\(UUID().uuidString)")!
    let controller = RotatorController(defaults: defaults)
    controller.pollInterval = .seconds(3_600) // keep polling out of the way
    controller.transportFactory = { _ in fake }
    await controller.connect(to: TrackerEndpoint(kind: .psr100, host: "192.0.2.10"))
    return (controller, fake)
}

@MainActor
@Test func jogsAccumulateFromTheLastCommandedTarget() async {
    let (controller, fake) = await linkedController()
    #expect(controller.isConnected)
    await controller.nudge(azimuthBy: -5)
    await controller.nudge(azimuthBy: -5)
    await controller.nudge(azimuthBy: -5)
    await controller.nudge(elevationBy: 15)
    let moves = await fake.sent.filter { $0.hasPrefix("AZ") }
    #expect(moves == ["AZ355EL0", "AZ350EL0", "AZ345EL0", "AZ345EL15"])
    #expect(controller.commandedTarget == RotatorPosition(azimuthDeg: 345, elevationDeg: 15))
    #expect(controller.lastCommand == "AZ345EL15")
    #expect(controller.lastReply == "Command executed: AZ=345 EL=15")
    #expect(controller.lastError == nil)
}

@MainActor
@Test func jogStartsFromReportedPositionWhenNothingCommanded() async {
    let (controller, fake) = await linkedController()
    await fake.setPosition(azimuth: 120, elevation: 30)
    // Simulate one poll having happened.
    await controller.pollOnceForTesting()
    #expect(controller.position == RotatorPosition(azimuthDeg: 120, elevationDeg: 30))
    await controller.nudge(azimuthBy: 5)
    #expect(controller.lastCommand == "AZ125EL30")
}

@MainActor
@Test func stopResetsTheManualBaseToTheReportedPosition() async {
    let (controller, fake) = await linkedController()
    await controller.nudge(azimuthBy: 10)
    #expect(controller.commandedTarget?.azimuthDeg == 10)
    await controller.stop()
    #expect(controller.commandedTarget == nil)
    #expect(controller.lastCommand == "STOP")
    await fake.setPosition(azimuth: 7, elevation: 0)
    await controller.pollOnceForTesting()
    await controller.nudge(azimuthBy: 1)
    #expect(controller.lastCommand == "AZ8EL0")
}

private extension FakeRotatorTransport {
    func setPosition(azimuth: Double, elevation: Double) {
        self.azimuth = azimuth
        self.elevation = elevation
    }
}

@MainActor
@Test func moveSurvivesCallerCancellation() async {
    let (controller, fake) = await linkedController()
    let jog = Task { await controller.nudge(azimuthBy: 5) }
    jog.cancel() // finger lifted before the request completed
    await jog.value
    // Give the detached send a moment to land.
    try? await Task.sleep(for: .milliseconds(50))
    let moves = await fake.sent.filter { $0.hasPrefix("AZ") }
    #expect(moves == ["AZ5EL0"])
    #expect(controller.lastError == nil || controller.lastError?.contains("cancelled") == false)
}
