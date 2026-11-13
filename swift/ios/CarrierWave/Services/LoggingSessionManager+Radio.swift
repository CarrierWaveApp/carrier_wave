import CarrierWaveCore
import CarrierWaveData
import Foundation
import SwiftData

// MARK: - Radio Integration

extension LoggingSessionManager {
    /// Connect radio if configured, start polling, wire callbacks.
    ///
    /// Prefers the session's `radioItemID` profile when present so the
    /// per-session radio choice wins over the global singleton state.
    /// Falls back to the legacy `RadioService.connectToSavedDevice()`
    /// path when the session has no FK or the item has no profile yet.
    func connectRadio() {
        let service = RadioService.shared

        // Wire up radio -> app callbacks once, regardless of path
        service.onRadioFrequencyChanged = { [weak self] freq in
            self?.handleRadioFrequencyChange(freq)
        }
        service.onRadioModeChanged = { [weak self] mode in
            self?.handleRadioModeChange(mode)
        }

        // Fast path: the item is in SwiftData (existing inventory).
        if let snapshot = sessionRadioItemSnapshot(),
           let profile = snapshot.connectionProfile,
           profile.isConfigured
        {
            service.connect(toItem: snapshot)
            return
        }

        // Rust fallback: items added via the new Rust-first gear picker live
        // only in cw-store, so resolve the profile from there before falling
        // back to the legacy global-config path.
        if let itemID = activeSession?.radioItemID {
            Task { [weak self] in
                if let snapshot = await self?.sessionRadioItemSnapshotFromRust(itemID),
                   let profile = snapshot.connectionProfile,
                   profile.isConfigured
                {
                    service.connect(toItem: snapshot)
                } else {
                    self?.connectLegacyRadio()
                }
            }
            return
        }

        connectLegacyRadio()
    }

    /// Global-config connect path — no per-session radio FK / profile available.
    private func connectLegacyRadio() {
        let service = RadioService.shared
        guard service.isConfigured else {
            return
        }
        service.setProtocolFromRig(activeSession?.myRig)
        service.connectToSavedDevice()
    }

    /// Snapshot for the active session's selected radio item from SwiftData.
    private func sessionRadioItemSnapshot() -> EquipmentInventorySnapshot? {
        guard let itemID = activeSession?.radioItemID else {
            return nil
        }
        var descriptor = FetchDescriptor<EquipmentItem>()
        descriptor.fetchLimit = 1
        descriptor.predicate = #Predicate<EquipmentItem> { $0.id == itemID }
        guard let item = try? modelContext.fetch(descriptor).first else {
            return nil
        }
        return EquipmentInventorySnapshot(item: item)
    }

    /// Snapshot for the active session's selected radio item from cw-store —
    /// resolves radios that exist only in Rust (added via the new picker).
    nonisolated private func sessionRadioItemSnapshotFromRust(
        _ itemID: UUID
    ) async -> EquipmentInventorySnapshot? {
        guard let store = try? await CwStoreProvider.shared.store() else {
            return nil
        }
        let idString = SwiftDataStoreImporter.uuid(itemID)
        guard let ffi = (try? store.fetchEquipmentItem(id: idString)).flatMap({ $0 }) else {
            return nil
        }
        return EquipmentInventorySnapshot(ffi: ffi)
    }

    /// Disconnect radio and clear callbacks
    func disconnectRadio() {
        let service = RadioService.shared
        service.onRadioFrequencyChanged = nil
        service.onRadioModeChanged = nil
        service.disconnect()
    }

    /// Handle frequency change from the physical radio
    func handleRadioFrequencyChange(_ frequencyMHz: Double) {
        guard let session = activeSession else {
            return
        }

        // Only update if delta > 100 Hz (0.0001 MHz)
        if let current = session.frequency,
           abs(current - frequencyMHz) < 0.0001
        {
            return
        }

        _ = updateFrequency(frequencyMHz)
    }

    /// Handle mode change from the physical radio
    func handleRadioModeChange(_ mode: String) {
        guard let session = activeSession else {
            return
        }

        guard session.mode != mode else {
            return
        }
        updateMode(mode)
    }

    /// Send frequency to the physical radio (app -> radio direction)
    func sendFrequencyToRadio(_ frequencyMHz: Double) {
        let service = RadioService.shared
        guard service.isConnected else {
            return
        }
        service.setFrequency(frequencyMHz)
    }

    /// Send mode to the physical radio (app -> radio direction)
    func sendModeToRadio(_ mode: String) {
        let service = RadioService.shared
        guard service.isConnected else {
            return
        }
        service.setMode(mode)
    }
}
