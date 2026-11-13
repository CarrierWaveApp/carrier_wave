import CarrierWaveCore
import CarrierWaveData
import Foundation
import OSLog

private let logger = Logger(subsystem: "com.jsvana.CWSweep", category: "RadioManager+Duplex")

// MARK: - RadioManager+Duplex

/// IC-9700 satellite-mode duplex: one radio, Main = downlink, Sub = uplink.
/// The satellite CAT controller calls these once per tick; the Sub tune is
/// the `07 D1` → `05` → `07 D0` sequence in `RadioSession.tuneSubBand`.
///
/// Satellite mode is a radio-global setting, so it is read before it is
/// changed and put back on disarm or disconnect, like the scope state
/// (`CIVScopeRestorePlan`).
extension RadioManager {
    /// True when the slot's radio has independent Main/Sub receivers and a
    /// satellite mode we know how to drive (IC-9700 over USB or LAN).
    func supportsSubBandDuplex(slot: RadioSlot) -> Bool {
        guard let profile = slotStates[slot]?.profile else {
            return false
        }
        guard profile.protocolType == .civ || profile.protocolType == .icomWiFi else {
            return false
        }
        if let modelId = profile.modelId, modelId.hasPrefix("ic9700") {
            return true
        }
        return profile.civAddress == 0xA2
    }

    /// Turn satellite mode on for the slot's radio, remembering what it was.
    /// Returns false when the slot has no CI-V session or the radio refuses.
    func enterSatelliteMode(slot: RadioSlot) async -> Bool {
        guard let civ = civSession(for: slot) else {
            return false
        }
        let session = civ.session
        let address = civ.address
        let sessionId = civ.sessionId
        if satelliteModeRestore[sessionId] != nil {
            return true
        }
        let found = await session.readSatelliteMode(address: address)
        guard let found else {
            commandLog.append(direction: .status, text: "Satellite mode read (16 5A) got no reply")
            return false
        }
        satelliteModeRestore[sessionId] = found
        commandLog.append(direction: .status, text: "Satellite mode on connect: \(found ? "on" : "off")")
        if found {
            return true
        }
        commandLog.append(direction: .tx, text: "16 5A 01 (satellite mode on)")
        let ok = await session.setSatelliteMode(true, address: address)
        if !ok {
            satelliteModeRestore[sessionId] = nil
            commandLog.append(direction: .status, text: "Satellite mode on refused")
        }
        return ok
    }

    /// Put satellite mode back the way `enterSatelliteMode` found it.
    func restoreSatelliteMode(slot: RadioSlot) async {
        guard let civ = civSession(for: slot) else {
            return
        }
        await restoreSatelliteMode(session: civ.session, address: civ.address, sessionId: civ.sessionId)
    }

    /// Disconnect-path variant: the slot may already be unregistered.
    func restoreSatelliteModeIfNeeded(session: RadioSession, sessionId: UUID, address: UInt8) async {
        guard satelliteModeRestore[sessionId] != nil else {
            return
        }
        await restoreSatelliteMode(session: session, address: address, sessionId: sessionId)
    }

    /// Tune the Sub band (uplink). `mode` is only sent when non-nil.
    func tuneSubBand(frequencyHz: Double, mode: String?, slot: RadioSlot) async -> Bool {
        guard let civ = civSession(for: slot) else {
            return false
        }
        let hz = UInt64(max(0, frequencyHz).rounded())
        let ok = await civ.session.tuneSubBand(frequencyHz: hz, mode: mode, address: civ.address)
        if !ok {
            logger.warning("Sub band tune to \(hz) Hz failed")
            commandLog.append(direction: .status, text: "Sub band tune failed (\(hz) Hz)")
        }
        return ok
    }

    // MARK: Private

    /// The CI-V session behind a slot, with the address to talk to.
    private struct CIVSlotSession {
        let session: RadioSession
        let address: UInt8
        let sessionId: UUID
    }

    private func civSession(for slot: RadioSlot) -> CIVSlotSession? {
        guard let sessionId = slots[slot],
              let session = sessions[sessionId],
              let profile = slotStates[slot]?.profile,
              profile.protocolType == .civ || profile.protocolType == .icomWiFi
        else {
            return nil
        }
        return CIVSlotSession(session: session, address: profile.civAddress ?? 0xA4, sessionId: sessionId)
    }

    private func restoreSatelliteMode(session: RadioSession, address: UInt8, sessionId: UUID) async {
        guard let found = satelliteModeRestore.removeValue(forKey: sessionId) else {
            return
        }
        guard !found else {
            return // It was already on; leave it.
        }
        commandLog.append(direction: .tx, text: "16 5A 00 (satellite mode off, restore)")
        if await !session.setSatelliteMode(false, address: address) {
            commandLog.append(direction: .status, text: "Satellite mode restore failed")
        }
    }
}
