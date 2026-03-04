//
//  FT8AudioEngine+InputSelection.swift
//  CarrierWave
//

import AVFoundation
import CarrierWaveData

// MARK: - AudioInputInfo

/// Describes an available audio input port.
struct AudioInputInfo: Sendable, Identifiable {
    let portName: String
    let portType: AVAudioSession.Port
    let uid: String
    let isSelected: Bool

    var id: String {
        uid
    }
}

// MARK: - FT8AudioEngine + Input Selection

extension FT8AudioEngine {
    /// Returns all available audio inputs with selection state.
    func availableInputs() -> [AudioInputInfo] {
        let session = AVAudioSession.sharedInstance()
        let preferred = session.preferredInput
        guard let ports = session.availableInputs else {
            return []
        }
        return ports.map { port in
            AudioInputInfo(
                portName: port.portName,
                portType: port.portType,
                uid: port.uid,
                isSelected: port.uid == preferred?.uid
            )
        }
    }

    /// Select an audio input by UID.
    func selectInput(uid: String) throws {
        let session = AVAudioSession.sharedInstance()
        guard let ports = session.availableInputs,
              let port = ports.first(where: { $0.uid == uid })
        else {
            return
        }
        try session.setPreferredInput(port)
    }
}
