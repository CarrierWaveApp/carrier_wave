//
//  WsjtxFieldService.swift
//  CarrierWave
//
//  Field's owner of the shared `WsjtxIngestService` (CAR-282). The ingest
//  service (CarrierWaveData) runs the WSJT-X UDP listener and turns
//  `QSOLogged` / `LoggedADIF` broadcasts into log rows exactly once; this
//  adapter gives it Field's conventions:
//
//  - binds `0.0.0.0` by default — WSJT-X never runs on the phone, so the
//    computer or Pi running it has to reach us over the LAN;
//  - commits through `QSOWriteSink` so cw-store stays canonical in `.on` mode;
//  - marks the same upload destinations as the manual logger
//    (`LoggingSessionManager.markForUpload`): QRZ / LoFi / Club Log whenever
//    configured, POTA only inside a POTA activation;
//  - fires the manual logger's post-insert side effects (ledger, `.didLogQSO`).
//
//  Diagnostics go to the ingest service's own live feed (`recentEvents`),
//  shown in Settings → Services → WSJT-X — never `print` / `os_log`.
//

import CarrierWaveData
import SwiftData
import UIKit

// MARK: - WsjtxFieldService

@MainActor
@Observable
final class WsjtxFieldService {
    // MARK: Lifecycle

    init(ingest: WsjtxIngestService = WsjtxIngestService(defaultHost: WsjtxIngestService.anyHost)) {
        self.ingest = ingest
        ingest.commit = { [weak self] qsos, context in
            guard let self else {
                try QSOWriteSink.commitUpsertBatch(qsos, in: context)
                return
            }
            try commit(qsos, in: context)
        }
        ingest.onQSOLogged = { qso in
            QSOLedger.append(qso)
            NotificationCenter.default.post(
                name: .didLogQSO, object: nil, userInfo: ["callsign": qso.callsign]
            )
        }
    }

    // MARK: Internal

    static let shared = WsjtxFieldService()

    /// The shared listener + ingest pipeline; the settings screen observes it.
    let ingest: WsjtxIngestService

    /// Upload destinations a freshly logged WSJT-X QSO is marked for, given the
    /// session it was attached to (if any). Injectable for tests.
    var uploadTargets: @MainActor (LoggingSession?) -> [ServiceType] = WsjtxFieldService.defaultUploadTargets

    /// The experiment gate (Settings → Experiments → WSJT-X Logging).
    var isAvailable: Bool {
        ExperimentalFeature.isEnabled(.wsjtx)
    }

    /// Mirror of `LoggingSessionManager.markForUpload` for an insert that may
    /// have no session: QRZ / LoFi / Club Log when configured, POTA only when
    /// the attached session is a POTA activation.
    static func defaultUploadTargets(for session: LoggingSession?) -> [ServiceType] {
        let configured = CarrierWaveData.ServiceConfiguration.configuredUploadServices()
        var targets: [ServiceType] = []
        if configured.contains(.qrz) {
            targets.append(.qrz)
        }
        if session?.isPOTA == true, configured.contains(.pota) {
            targets.append(.pota)
        }
        if UserDefaults.standard.bool(forKey: "lofi.deviceLinked") {
            targets.append(.lofi)
        }
        if isClubLogConfigured {
            targets.append(.clublog)
        }
        return targets
    }

    func configure(container: ModelContainer) {
        ingest.configure(container: container)
    }

    /// Launch and every return to the foreground: start if the user left the
    /// listener on. iOS suspends the socket with the app; `startIfEnabled` is a
    /// no-op while the listener is already running, so repeating it is safe.
    func startIfEnabled() async {
        guard isAvailable else {
            return
        }
        await ingest.startIfEnabled()
    }

    func stop() {
        ingest.stop()
    }

    /// Mark uploads, then commit through the cw-store seam (or a plain save
    /// when no seam is active). Throws so the ingest service rolls the
    /// context back and reports the failure in its feed.
    func commit(_ qsos: [QSO], in context: ModelContext) throws {
        for qso in qsos where !QSOMode.isMetadata(qso.mode) {
            let session = qso.loggingSessionId.flatMap { Self.session(id: $0, in: context) }
            for target in uploadTargets(session) {
                qso.markNeedsUpload(to: target, context: context)
            }
        }
        try QSOWriteSink.commitUpsertBatch(qsos, in: context)
    }

    // MARK: Private

    private static var isClubLogConfigured: Bool {
        let keychain = KeychainHelper.shared
        return (try? keychain.readString(for: KeychainHelper.Keys.clublogEmail)) != nil
            && (try? keychain.readString(for: KeychainHelper.Keys.clublogPassword)) != nil
            && (try? keychain.readString(for: KeychainHelper.Keys.clublogCallsign)) != nil
    }

    private static func session(id: UUID, in context: ModelContext) -> LoggingSession? {
        var descriptor = FetchDescriptor<LoggingSession>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
}

// MARK: - DeviceIPv4

/// IPv4 addresses a computer running WSJT-X can send to: `en0` (Wi-Fi) first,
/// then any other up, non-loopback, non-tunnel interface.
enum DeviceIPv4 {
    // MARK: Internal

    struct Address: Identifiable, Hashable, Sendable {
        let interface: String
        let address: String

        var id: String {
            "\(interface) \(address)"
        }
    }

    nonisolated static func addresses() -> [Address] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else {
            return []
        }
        defer { freeifaddrs(head) }
        var result: [Address] = []
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = cursor {
            defer { cursor = entry.pointee.ifa_next }
            guard let addr = entry.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) else {
                continue
            }
            let flags = Int32(entry.pointee.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0, flags & IFF_POINTOPOINT == 0 else {
                continue
            }
            let name = String(cString: entry.pointee.ifa_name)
            if isTunnelOrPeerLink(name) {
                continue
            }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let status = getnameinfo(
                addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST
            )
            guard status == 0 else {
                continue
            }
            let text = host.withUnsafeBufferPointer { buffer in
                buffer.baseAddress.map { String(cString: $0) } ?? ""
            }
            if !text.isEmpty, !text.hasPrefix("169.254.") {
                result.append(Address(interface: name, address: text))
            }
        }
        return result.sorted { lhs, rhs in
            (lhs.interface == "en0" ? 0 : 1, lhs.interface) < (rhs.interface == "en0" ? 0 : 1, rhs.interface)
        }
    }

    // MARK: Private

    /// utun*/ipsec* are VPN tunnels; awdl*/llw*/bridge* are not LANs a desktop sits on.
    nonisolated private static func isTunnelOrPeerLink(_ name: String) -> Bool {
        ["utun", "ipsec", "awdl", "llw", "bridge"].contains { name.hasPrefix($0) }
    }
}
