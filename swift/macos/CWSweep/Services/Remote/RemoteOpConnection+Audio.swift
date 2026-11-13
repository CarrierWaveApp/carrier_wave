import CarrierWaveCore
import Foundation

// MARK: - RemoteOpConnection + Audio

//
// Per-connection helpers for the `radio.audio` topic. Sends the current
// `AudioFormatEvent` so a freshly subscribed client knows how to interpret
// frame payloads. Frame events themselves are pushed by RemoteOpPublishers
// in response to the broadcaster firing.
//

extension RemoteOpConnection {
    func sendCurrentAudioFormatIfAvailable() async {
        guard let service else {
            return
        }
        let event: AudioFormatEvent? = await MainActor.run {
            service.currentAudioFormatEvent()
        }
        guard let event else {
            return
        }
        await sendFrame(.eventAudioFormat(event))
    }
}
