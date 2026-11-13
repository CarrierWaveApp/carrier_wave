import CarrierWaveCore
import CarrierWaveData
import Foundation

// MARK: - MacroAppSafetyEnvironment

/// Production `MacroSafetyEnvironment` for CW Sweep. Reads the connected
/// radio protocol from `SharedEnvironment.shared.radioManager` and the
/// region from a UserDefaults override. The macOS app doesn't carry the
/// iOS `UserRegionProfile` (callsign-derived region) yet — Region 2 is
/// the default until the user overrides it.
struct MacroAppSafetyEnvironment: MacroSafetyEnvironment {
    // MARK: Internal

    var connectedProtocol: RadioCommandProtocol? {
        get async {
            await MainActor.run {
                let manager = SharedEnvironment.shared.radioManager
                guard manager.isConnected else {
                    return nil
                }
                guard let slot = activeSlot(manager: manager),
                      let state = manager.slotStates[slot]
                else {
                    return nil
                }
                return Self.toRadioCommandProtocol(state.profile.protocolType)
            }
        }
    }

    var sessionAllowsTx: Bool {
        get async { true }
    }

    var globalInhibitTx: Bool {
        get async {
            await MainActor.run {
                UserDefaults.standard.bool(forKey: "macroGlobalInhibitTx")
            }
        }
    }

    var deviceRegion: String {
        get async {
            await MainActor.run {
                let raw = UserDefaults.standard.integer(forKey: "userIARURegionOverride")
                switch raw {
                case 1: return "R1"
                case 3: return "R3"
                default: return "R2"
                }
            }
        }
    }

    // MARK: Private

    private static func toRadioCommandProtocol(_ ptype: RadioProtocolType) -> RadioCommandProtocol? {
        switch ptype {
        case .civ,
             .icomWiFi: .civ
        case .kenwood,
             .elecraft: .kenwood
        case .yaesu,
             .scuLan10: .yaesu
        case .flex: .flex
        case .cwBridge: nil
        }
    }

    @MainActor
    private func activeSlot(manager: RadioManager) -> RadioSlot? {
        guard let id = manager.activeRadioId else {
            return nil
        }
        return manager.slots.first(where: { $1 == id })?.key ?? manager.focusedSlot
    }
}
