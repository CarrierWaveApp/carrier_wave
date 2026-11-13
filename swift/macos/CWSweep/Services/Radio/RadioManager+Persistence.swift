import Foundation

// MARK: - Saved profile persistence

extension RadioManager {
    /// Persist the resolved profile under `radio.savedProfile.<fingerprint>`.
    /// Used by `connect(profile:port:)` so a subsequent launch can skip the
    /// autodetect probe and reconnect directly with the same protocol/baud.
    func saveProfile(_ profile: RadioProfile, for fingerprint: String) {
        guard let data = try? JSONEncoder().encode(profile) else {
            return
        }
        UserDefaults.standard.set(data, forKey: "radio.savedProfile.\(fingerprint)")
    }

    /// Load a previously saved profile, or nil if none exists for this device.
    func loadProfile(for fingerprint: String) -> RadioProfile? {
        guard let data = UserDefaults.standard.data(forKey: "radio.savedProfile.\(fingerprint)") else {
            return nil
        }
        return try? JSONDecoder().decode(RadioProfile.self, from: data)
    }

    // MARK: - Per-slot fingerprint tracking

    /// UserDefaults key for the last-connected device fingerprint in `slot`.
    private func lastFingerprintKey(for slot: RadioSlot) -> String {
        "radio.slot.\(slot.rawValue).lastDeviceFingerprint"
    }

    /// Read the last-connected device fingerprint for the given slot.
    /// Falls back to the legacy single-radio key for slot A so existing
    /// installations continue auto-connecting without a re-pair.
    func lastFingerprint(for slot: RadioSlot) -> String? {
        let defaults = UserDefaults.standard
        if let value = defaults.string(forKey: lastFingerprintKey(for: slot)) {
            return value
        }
        // Legacy migration: old installs only stored slot A's fingerprint
        // under "radio.lastDeviceFingerprint". Read it once for slot A and
        // copy forward.
        if slot == .a, let legacy = defaults.string(forKey: "radio.lastDeviceFingerprint") {
            defaults.set(legacy, forKey: lastFingerprintKey(for: slot))
            defaults.removeObject(forKey: "radio.lastDeviceFingerprint")
            return legacy
        }
        return nil
    }

    /// Persist the fingerprint of the radio newly connected in `slot`.
    func setLastFingerprint(_ fingerprint: String?, for slot: RadioSlot) {
        let key = lastFingerprintKey(for: slot)
        if let fingerprint {
            UserDefaults.standard.set(fingerprint, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
        // Keep the legacy single-radio key in sync with slot A so any not-
        // yet-migrated reader (e.g. iOS handoff or backups) still works.
        if slot == .a {
            if let fingerprint {
                UserDefaults.standard.set(fingerprint, forKey: "radio.lastDeviceFingerprint")
            } else {
                UserDefaults.standard.removeObject(forKey: "radio.lastDeviceFingerprint")
            }
        }
    }

    // MARK: - Per-slot contest role

    private func contestRoleKey(for slot: RadioSlot) -> String {
        "radio.slot.\(slot.rawValue).contestRole"
    }

    /// Read the saved contest role for `slot`, defaulting to `.none`.
    func contestRole(for slot: RadioSlot) -> ContestSlotRole {
        guard let raw = UserDefaults.standard.string(forKey: contestRoleKey(for: slot)),
              let role = ContestSlotRole(rawValue: raw)
        else {
            return .none
        }
        return role
    }

    /// Persist the contest role for `slot` and update its live state if the
    /// slot is connected.
    func setContestRole(_ role: ContestSlotRole, for slot: RadioSlot) {
        UserDefaults.standard.set(role.rawValue, forKey: contestRoleKey(for: slot))
        slotStates[slot]?.contestRole = role
    }

    /// Try to auto-connect every slot that has a saved fingerprint matching
    /// a currently-attached USB port. Failures on one slot do not block the
    /// others.
    func autoConnectAllSlots(ports: [SerialPortMonitor.SerialPortInfo]) async {
        guard UserDefaults.standard.bool(forKey: "autoConnect") else {
            return
        }
        for slot in RadioSlot.allCases {
            // Skip if the slot already has a session (e.g. user reconnected
            // manually before auto-connect ran).
            if slots[slot] != nil {
                continue
            }
            guard let fingerprint = lastFingerprint(for: slot),
                  let match = ports.first(where: { $0.deviceFingerprint == fingerprint }),
                  var profile = loadProfile(for: fingerprint),
                  slotForPortPath(match.path) == nil
            else {
                continue
            }
            profile.serialPortPath = match.path
            do {
                _ = try await connect(profile: profile, port: match, slot: slot)
            } catch {
                // Best-effort; surface failure via the command log only.
                commandLog.append(
                    direction: .status,
                    text: "Auto-connect \(slot.label) failed: \(error.localizedDescription)"
                )
            }
        }
    }
}
