import CarrierWaveCore
import CoreLocation
import SwiftUI

// MARK: - SatBridgeController

/// Drives the CW Sat Bridge: builds a doppler schedule for one pass via the
/// shared Rust `SatelliteApi`, uploads it over BLE (stop-and-wait chunks),
/// and arms the pass. Live executor state arrives as `.satStatus` bridge
/// events on `RadioService.satBridgeStatus` — the bridge runs the pass on
/// its own clock even if BLE drops afterwards.
@MainActor
@Observable
final class SatBridgeController {
    // MARK: Internal

    enum Phase: Equatable {
        case idle
        case building
        case uploading(sent: Int, total: Int)
        case starting
        /// Schedule armed on the bridge; live state is `RadioService.satBridgeStatus`.
        case sent
        case failed(String)
    }

    static let shared = SatBridgeController()

    private(set) var phase: Phase = .idle

    /// Which VFO the operator last selected via the app (false = downlink).
    private(set) var uplinkSelected = false

    /// Whether a connected bridge advertises the sat doppler capability.
    var bridgeAvailable: Bool {
        RadioService.shared.bridgeHasSatDoppler && RadioService.shared.bridgeProtocol != nil
    }

    /// Build, upload, and arm the schedule for one upcoming pass.
    func send(pass item: UpcomingSatellitePass, model: SatelliteTrackerModel) async {
        guard let bridge = RadioService.shared.bridgeProtocol else {
            phase = .failed("No bridge connected")
            return
        }
        guard let observer = model.observerCoordinate else {
            phase = .failed("QTH not set")
            return
        }
        guard let plan = Self.transponderPlan(
            noradID: item.noradID,
            transmitters: model.transmitters(for: item.noradID)
        ) else {
            phase = .failed("No usable transmitter")
            return
        }

        // The radio state-poll loop hammers the BLE link with CAT writes
        // (~16/sec), which delays the bridge's ack notifications past the
        // upload timeout. Nothing needs live radio state during a schedule
        // upload — pause polling for the duration and resume after.
        RadioService.shared.stopStatePolling()
        defer { RadioService.shared.startStatePolling() }

        phase = .building
        do {
            let schedule = try await Self.buildSchedule(pass: item, observer: observer, plan: plan)
            try await upload(schedule: schedule, pass: item, plan: plan, bridge: bridge)
        } catch {
            phase = .failed(error.localizedDescription)
            RadioService.shared.addLog(.error, "Sat bridge: \(error.localizedDescription)")
        }
    }

    /// Cancel the armed/running pass on the bridge.
    func abort() {
        guard let bridge = RadioService.shared.bridgeProtocol else {
            return
        }
        phase = .idle
        Task {
            try? await bridge.sendSatAbort()
        }
    }

    /// Flip the radio's active VFO (false = downlink A, true = uplink B).
    func selectVfo(uplink: Bool) {
        guard let bridge = RadioService.shared.bridgeProtocol else {
            return
        }
        uplinkSelected = uplink
        Task {
            try? await bridge.sendSatSetVfo(uplink: uplink)
        }
    }

    func reset() {
        phase = .idle
    }

    // MARK: Private

    /// What to program: link frequencies, modes, tone, and direction.
    private struct TransponderPlan {
        let downlinkHz: UInt64
        let uplinkHz: UInt64?
        let downlinkMode: BridgeFrame.UniversalMode
        let uplinkMode: BridgeFrame.UniversalMode
        let uplinkToneDHz: UInt32
        let direction: Cwbp_SatLinkDirection
        let downlinkStepHz: UInt32
        let uplinkStepHz: UInt32
    }

    private struct SatBridgeError: LocalizedError {
        let message: String

        var errorDescription: String? {
            message
        }
    }

    /// Uplink CTCSS by NORAD id, in tenths of Hz — SatNOGS transmitter rows
    /// don't carry tones. In-pass access tones only (SO-50's 74.4 Hz arming
    /// tone stays a manual step).
    private static let uplinkTonesDHz: [Int: UInt32] = [
        27_607: 670, // SO-50
        43_017: 670, // AO-91
        43_678: 1_413, // PO-101 (Diwata-2)
    ]

    private static func ackLabel(_ result: Cwbp_SatAckResult) -> String {
        switch result {
        case .satAckOk: "ok"
        case .satAckBadSeq: "chunk out of order"
        case .satAckOverflow: "schedule too large"
        case .satAckUnknownID: "unknown schedule id"
        case .satAckBusy: "pass already armed"
        case .satAckBadData: "malformed step data"
        default: "error \(result.rawValue)"
        }
    }

    /// Pick the transmitter to fly: an active FM transponder with both links
    /// (full doppler tracking), else any active downlink for RX-only.
    private static func transponderPlan(
        noradID: Int,
        transmitters: [SatNOGSTransmitter]
    ) -> TransponderPlan? {
        let active = transmitters.filter { $0.isActive && $0.downlinkLow != nil }
        let candidates = active.isEmpty
            ? transmitters.filter { $0.downlinkLow != nil }
            : active

        let fmTransponder = candidates.first {
            SatelliteModeCategory.category(for: $0) == .voiceFM && $0.uplinkLow != nil
        }
        if let fm = fmTransponder, let down = fm.downlinkLow, let up = fm.uplinkLow {
            return TransponderPlan(
                downlinkHz: UInt64(down),
                uplinkHz: UInt64(up),
                downlinkMode: .fm,
                uplinkMode: .fm,
                uplinkToneDHz: uplinkTonesDHz[noradID] ?? 0,
                direction: up > down ? .satDirUV : .satDirVU,
                downlinkStepHz: 2_500,
                uplinkStepHz: 2_500
            )
        }

        // Downlink-only: track a linear/CW/telemetry downlink in USB.
        guard let rx = candidates.first, let down = rx.downlinkLow else {
            return nil
        }
        return TransponderPlan(
            downlinkHz: UInt64(down),
            uplinkHz: nil,
            downlinkMode: .usb,
            uplinkMode: .usb,
            uplinkToneDHz: 0,
            direction: .satDirDownlinkOnly,
            downlinkStepHz: 100,
            uplinkStepHz: 100
        )
    }

    /// Run the blocking FFI schedule build off the main actor.
    private static func buildSchedule(
        pass item: UpcomingSatellitePass,
        observer: CLLocationCoordinate2D,
        plan: TransponderPlan
    ) async throws -> FfiDopplerSchedule {
        let api = try await SatelliteEngine.api()
        let input = FfiDopplerScheduleInput(
            noradId: UInt32(item.noradID),
            observer: FfiObserver(latDeg: observer.latitude, lonDeg: observer.longitude),
            aosEpoch: Int64(item.pass.aos.timeIntervalSince1970),
            losEpoch: Int64(item.pass.los.timeIntervalSince1970),
            downlinkHz: plan.downlinkHz,
            uplinkHz: plan.uplinkHz,
            downlinkStepHz: plan.downlinkStepHz,
            uplinkStepHz: plan.uplinkStepHz
        )
        return try await Task.detached {
            try api.buildDopplerSchedule(input: input)
        }.value
    }

    private static func header(
        scheduleID: UInt32,
        schedule: FfiDopplerSchedule,
        item: UpcomingSatellitePass,
        plan: TransponderPlan
    ) -> BridgeFrame.SatScheduleHeader {
        BridgeFrame.SatScheduleHeader(
            scheduleID: scheduleID,
            satName: item.name,
            direction: plan.direction,
            totalSteps: schedule.totalSteps,
            durationMs: schedule.durationMs,
            downlinkStartHz: schedule.downlinkStartHz,
            uplinkStartHz: schedule.uplinkStartHz,
            downlinkMode: plan.downlinkMode,
            uplinkMode: plan.uplinkMode,
            uplinkToneDHz: plan.uplinkToneDHz
        )
    }

    private func upload(
        schedule: FfiDopplerSchedule,
        pass item: UpcomingSatellitePass,
        plan: TransponderPlan,
        bridge: BridgeProtocol
    ) async throws {
        let scheduleID = UInt32(truncatingIfNeeded: Int(Date().timeIntervalSince1970))
        let header = Self.header(scheduleID: scheduleID, schedule: schedule, item: item, plan: plan)

        phase = .uploading(sent: 0, total: schedule.chunks.count)
        try await sendBegin(header, bridge: bridge)
        try await sendChunks(schedule, scheduleID: scheduleID, bridge: bridge)
        try await arm(scheduleID: scheduleID, item: item, schedule: schedule, bridge: bridge)
    }

    private func sendBegin(_ header: BridgeFrame.SatScheduleHeader, bridge: BridgeProtocol) async throws {
        var beginAck = await bridge.sendSatBegin(header)
        if beginAck?.result == .satAckBusy {
            // A previously armed/running pass (possibly a stale one from an
            // earlier upload) blocks new schedules. Tapping Send to Bridge is
            // an explicit intent to replace it: abort and retry once.
            RadioService.shared.addLog(.info, "Sat bridge busy — aborting old pass and retrying")
            try? await bridge.sendSatAbort()
            try? await Task.sleep(for: .milliseconds(300))
            beginAck = await bridge.sendSatBegin(header)
        }
        guard let beginAck else {
            throw SatBridgeError(message: "No response to schedule upload (bridge connected?)")
        }
        guard beginAck.result == .satAckOk else {
            throw SatBridgeError(message: "Bridge rejected schedule (\(Self.ackLabel(beginAck.result)))")
        }
    }

    private func sendChunks(
        _ schedule: FfiDopplerSchedule,
        scheduleID: UInt32,
        bridge: BridgeProtocol
    ) async throws {
        for (index, chunk) in schedule.chunks.enumerated() {
            let ack = await bridge.sendSatChunk(scheduleID: scheduleID, seq: UInt32(index), steps: Data(chunk))
            guard let ack else {
                throw SatBridgeError(message: "No response to chunk \(index + 1)")
            }
            guard ack.result == .satAckOk else {
                throw SatBridgeError(message: "Chunk \(index + 1) failed (\(Self.ackLabel(ack.result)))")
            }
            phase = .uploading(sent: index + 1, total: schedule.chunks.count)
        }
    }

    private func arm(
        scheduleID: UInt32,
        item: UpcomingSatellitePass,
        schedule: FfiDopplerSchedule,
        bridge: BridgeProtocol
    ) async throws {
        phase = .starting
        let now = Date()
        let aosInMs = UInt64(max(0, item.pass.aos.timeIntervalSince(now)) * 1_000)
        let elapsedMs = aosInMs > 0 ? 0 : UInt64(max(0, now.timeIntervalSince(item.pass.aos)) * 1_000)
        try await bridge.sendSatStart(scheduleID: scheduleID, aosInMs: aosInMs, elapsedMs: elapsedMs)
        uplinkSelected = false
        phase = .sent
        RadioService.shared.addLog(
            .info,
            "Sat bridge armed: \(item.name) id=\(scheduleID) steps=\(schedule.totalSteps)"
        )
    }
}
