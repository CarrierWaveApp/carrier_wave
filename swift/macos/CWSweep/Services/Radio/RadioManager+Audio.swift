import Foundation

// MARK: - RadioManager+Audio

//
// Wires the local Mac player into the radio audio broadcaster. Listener
// management is split out of `RadioManager.swift` so the main file stays
// inside SwiftLint's `file_length` cap; the broadcaster fan-out makes this
// a natural seam.
//

extension RadioManager {
    /// Start the local Mac player and route the broadcaster's frames into it.
    /// Idempotent — safe to call repeatedly while connected.
    func attachLocalAudioPlayer() {
        if sculan10AudioListenerID == nil {
            let player = sculan10AudioPlayer
            sculan10AudioListenerID = radioAudioBroadcaster.addListener { data in
                player.feed(data)
            }
        }
        sculan10AudioPlayer.start()
    }

    /// Detach the local player from the broadcaster and tear down the engine.
    func detachLocalAudioPlayer() {
        if let id = sculan10AudioListenerID {
            radioAudioBroadcaster.removeListener(id: id)
            sculan10AudioListenerID = nil
        }
        sculan10AudioPlayer.stop()
    }

    /// Route Mac speaker audio to the given slot. Today only one
    /// SCU-LAN10 stream produces audio at a time so this is largely a
    /// state flip + log entry; once per-slot SCU-LAN10 sessions land
    /// (multi-radio waterfall follow-up) the routing here will detach
    /// the prior slot's listener and attach the new one.
    func setAudioRoutedSlot(_ slot: RadioSlot) {
        guard slot != audioRoutedSlot else {
            return
        }
        audioRoutedSlot = slot
        commandLog.append(direction: .status, text: "Audio → \(slot.label)")
    }

    /// Whether the audio-routed slot should follow `focusedSlot`. Read
    /// from UserDefaults each call so changes in the preferences popover
    /// take effect immediately. Defaults to `false` to avoid stealing
    /// audio mid-QSO when the operator just glances at the other slot.
    var audioFollowsFocus: Bool {
        UserDefaults.standard.bool(forKey: "radio.audioFollowsFocus")
    }
}
