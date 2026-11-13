import CarrierWaveCore
import UIKit

// MARK: - RemoteSweepCoordinator+Audio

//
// Live audio handling — receives `radio.audio` events from Sweep, configures
// the iOS player when the format changes, and gates the subscription on the
// view being on screen so we don't burn LAN bandwidth in the background.
//

extension RemoteSweepCoordinator {
    func applyAudioFormat(_ event: AudioFormatEvent) {
        audioFormat = event
        audioLastSequence = 0
        // Start (or reconfigure for a new format) whenever the user has
        // opted in via the speaker toggle. `start(format:)` is a no-op if
        // the engine is already running with this exact format.
        if audioSubscribed {
            audioPlayer.start(format: event)
        }
    }

    func applyAudioFrame(_ event: AudioFrameEvent) {
        // Drop reordered or stale frames. UInt32 wraps; ignore the wrap
        // boundary by accepting any frame that's "close" after a reset.
        if event.sequence != 0, event.sequence <= audioLastSequence {
            return
        }
        audioLastSequence = event.sequence
        audioPlayer.feed(event.samples)
    }

    /// Called from the speaker toggle. Subscribes to `radio.audio` and (if
    /// a format snapshot has already arrived) starts the player engine.
    func subscribeAudio() async {
        guard let client, !audioSubscribed else {
            return
        }
        audioSubscribed = true
        await client.subscribe(.audio)
        if let format = audioFormat {
            audioPlayer.start(format: format)
        }
    }

    func unsubscribeAudio() async {
        guard let client, audioSubscribed else {
            return
        }
        audioSubscribed = false
        await client.unsubscribe(.audio)
        audioPlayer.stop()
        audioLastSequence = 0
    }
}
