import CarrierWaveCore
import CarrierWaveData
import Foundation
import Observation
import OSLog

private let logger = Logger(subsystem: "com.jsvana.CWSweep", category: "RemoteOpPublishers")

// MARK: - RemoteOpPublishers

//
// Bridges the @Observable Sweep state types to the RemoteOpService broadcast
// surface. Watches RadioManager (radio.state) and SpotAggregator (spots.feed)
// and re-emits when either changes. v1 uses Observation re-arm tracking — no
// timers, no polling. Meters topic is unwired in v1 (publisher arrives later).

@MainActor
final class RemoteOpPublishers {
    // MARK: Lifecycle

    init(service: RemoteOpService) {
        self.service = service
    }

    // MARK: Internal

    func start() {
        guard !started else {
            return
        }
        started = true
        observeRadioState()
        observeSpots()
        observeCWStatus()
        observeWaterfall()
        observeAudio()
    }

    func stop() {
        started = false
        detachAudioListener()
    }

    // MARK: Private

    /// Throttle so we don't flood the LAN at the producer's native rate
    /// (SCU-LAN10 emits ~25 lines/sec; iOS doesn't need that).
    private static let waterfallMinInterval: TimeInterval = 0.1

    /// UserDefaults key controlling whether the audio publisher encodes
    /// outbound `radio.audio` frames as Opus instead of raw PCM16. Default
    /// is `false` while we're shaking the codec out — flip via the
    /// "Remote → Audio codec" Settings toggle. The feature only engages
    /// when `OpusCodec.isEncoderAvailable()` also returns true on this OS.
    private static let opusEnabledKey = "remoteAudio.opusEnabled"

    private weak var service: RemoteOpService?
    private var started = false
    private var lastRadioState: RadioStateEvent?
    private var lastSpotsVersion = -1
    private var lastCWStatus: CWStatusEvent?
    private var lastWaterfallSequence: UInt64 = 0
    private var lastWaterfallSource: WaterfallStore.Source = .none
    private var lastWaterfallEmittedAt: Date?
    private var audioListenerID: UUID?
    private var audioFrameSeq: UInt32 = 0
    private var lastAnnouncedAudioFormat: RadioAudioFormat?

    /// Lazy-built Opus encoder, rebuilt whenever the source format changes.
    /// Nil when Opus is disabled, the OS lacks an encoder, or the source
    /// rate isn't one Opus supports (8/12/16/24/48 kHz).
    private var opusEncoder: OpusEncoder?
    private var opusEncoderForFormat: RadioAudioFormat?

    private func observeRadioState() {
        guard started, let service else {
            return
        }
        // Touch the @Observable fields we want to track. They are read inside
        // `currentRadioStateSnapshot()` indirectly via RadioManager — but
        // `withObservationTracking` only re-arms based on what's read inside
        // the apply block, so we read them explicitly here.
        let snapshot: RadioStateEvent? = withObservationTracking {
            guard let manager = service.radioManager else {
                return nil
            }
            // Read every field we care about so they're tracked.
            _ = manager.frequency
            _ = manager.mode
            _ = manager.isTransmitting
            _ = manager.connectedRadioName
            _ = manager.activeRadioId
            _ = manager.isConnected
            return service.currentRadioStateSnapshot()
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.observeRadioState()
            }
        }

        if let snapshot, snapshot != lastRadioState {
            lastRadioState = snapshot
            service.broadcast(.eventRadioState(snapshot), topic: .radioState)
        }
    }

    private func observeSpots() {
        guard started, let service else {
            return
        }
        let version: Int = withObservationTracking {
            guard let aggregator = service.spotAggregator else {
                return -1
            }
            // Read the spots array + version counter so any mutation re-arms.
            _ = aggregator.spotsVersion
            _ = aggregator.spots.count
            return aggregator.spotsVersion
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.observeSpots()
            }
        }

        if version != lastSpotsVersion {
            lastSpotsVersion = version
            broadcastSpots()
        }
    }

    private func observeCWStatus() {
        guard started, let service else {
            return
        }
        let snapshot: CWStatusEvent? = withObservationTracking {
            guard let manager = service.radioManager else {
                return nil
            }
            // Touch every bridge field that contributes to the snapshot so
            // the tracker re-arms on any change.
            _ = manager.activeBridge != nil
            _ = manager.bridgeIsFramed
            _ = manager.bridgeHasCWKeyer
            _ = manager.bridgeCWSpeed
            _ = manager.bridgeCWFlags
            _ = manager.bridgeCWBufferDepth
            _ = manager.bridgeCWSendingSlot
            _ = manager.activeRadioId
            return service.currentCWStatusSnapshot()
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.observeCWStatus()
            }
        }

        guard let snapshot else {
            return
        }
        if cwStatusEqualIgnoringTimestamp(snapshot, lastCWStatus) {
            return
        }
        lastCWStatus = snapshot
        service.broadcast(.eventCWStatus(snapshot), topic: .cwKeyer)
    }

    /// `CWStatusEvent`'s `timestamp` would change on every snapshot and
    /// re-broadcast even when the meaningful state is identical. Compare
    /// every field except `timestamp`.
    private func cwStatusEqualIgnoringTimestamp(_ lhs: CWStatusEvent, _ rhs: CWStatusEvent?) -> Bool {
        guard let rhs else {
            return false
        }
        return lhs.radioID == rhs.radioID
            && lhs.keyerAvailable == rhs.keyerAvailable
            && lhs.wpm == rhs.wpm
            && lhs.bufferDepth == rhs.bufferDepth
            && lhs.sendingSlot == rhs.sendingSlot
            && lhs.isSending == rhs.isSending
    }

    private func observeWaterfall() {
        guard started, let service else {
            return
        }
        let snapshot: (sequence: UInt64, source: WaterfallStore.Source)? = withObservationTracking {
            guard let manager = service.radioManager else {
                return nil
            }
            let store = manager.waterfallStore
            // Touch all the fields whose changes should re-arm the tracker.
            _ = store.lineSequence
            _ = store.source
            _ = store.magnitudes.first?.count
            return (store.lineSequence, store.source)
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.observeWaterfall()
            }
        }

        guard let snapshot else {
            return
        }

        // Source switched (radio swapped, disconnected, etc.) — tell every
        // subscriber to flush their buffer.
        if snapshot.source != lastWaterfallSource {
            lastWaterfallSource = snapshot.source
            broadcastWaterfallCleared()
            lastWaterfallEmittedAt = nil
        }
        guard snapshot.sequence != lastWaterfallSequence else {
            return
        }
        // Throttle to ~10 fps regardless of producer rate.
        let now = Date()
        if let last = lastWaterfallEmittedAt,
           now.timeIntervalSince(last) < Self.waterfallMinInterval
        {
            return
        }
        lastWaterfallSequence = snapshot.sequence
        lastWaterfallEmittedAt = now
        broadcastWaterfallLine()
    }

    private func broadcastWaterfallCleared() {
        guard let service, let manager = service.radioManager else {
            return
        }
        let event = WaterfallClearedEvent(
            radioID: manager.activeRadioId?.uuidString ?? "active",
            timestamp: Date()
        )
        service.broadcast(.eventWaterfallCleared(event), topic: .waterfall)
    }

    private func broadcastWaterfallLine() {
        guard let service, let manager = service.radioManager,
              let line = manager.waterfallStore.magnitudes.first
        else {
            return
        }
        let store = manager.waterfallStore
        let event = WaterfallLineEvent(
            radioID: manager.activeRadioId?.uuidString ?? "active",
            source: store.source.label,
            centerHz: UInt64((store.centerFrequencyMHz * 1_000_000).rounded()),
            spanHz: UInt64((store.spanKHz * 1_000).rounded()),
            binCount: UInt16(min(line.count, Int(UInt16.max))),
            bins: WaterfallLineEvent.quantize(line),
            sequence: store.lineSequence,
            timestamp: store.lastLineTimestamp ?? Date()
        )
        service.broadcast(.eventWaterfallLine(event), topic: .waterfall)
    }

    private func broadcastSpots() {
        guard let service, let aggregator = service.spotAggregator else {
            return
        }
        // Naive v1: send the whole list. Real diffing is a follow-up.
        let snapshot = aggregator.remoteSpots(filter: nil)
        for spot in snapshot {
            service.broadcast(.eventSpot(.init(spot: spot)), topic: .spotsFeed)
        }
    }
}

// MARK: - Audio publisher

//
// Audio observation and broadcast — split into a same-file extension so
// the main class body stays under SwiftLint's type_body_length cap. Lives
// in this file (not a separate one) so it keeps access to the private
// state on `RemoteOpPublishers` without exporting it.
//

extension RemoteOpPublishers {
    /// Called by Settings when the operator flips the "Use Opus" toggle.
    /// Rebuilds the encoder against the current upstream format and
    /// re-broadcasts an `AudioFormatEvent` so subscribed Field clients
    /// reset their decoder pipeline.
    func audioCodecPreferenceChanged() {
        rebuildOpusEncoder(for: lastAnnouncedAudioFormat)
        broadcastAudioFormatIfPossible()
    }

    /// True iff the publisher will currently emit Opus packets on
    /// `radio.audio`. Used by `RemoteOpService.currentAudioFormatEvent`
    /// so the announced codec matches what's about to flow on the wire.
    var isEmittingOpus: Bool {
        opusEncoder != nil
    }

    /// `framesPerPacket` for the active Opus session, mirrored into
    /// `AudioFormatEvent` so decoders can size their output buffers
    /// correctly on the first packet.
    var opusFramesPerPacket: Int? {
        opusEncoder?.config.framesPerPacket
    }

    /// Watch the radio audio broadcaster: re-broadcast the current format
    /// to all subscribed clients whenever it changes, and (once) attach a
    /// listener that emits one `eventAudioFrame` per decrypted PCM packet.
    /// The listener stays attached for the lifetime of `RemoteOpPublishers`
    /// — per-connection topic gating happens inside `service.broadcast`,
    /// so unsubscribed clients pay nothing.
    func observeAudio() {
        guard started, let service else {
            return
        }
        let format: RadioAudioFormat? = withObservationTracking {
            guard let manager = service.radioManager else {
                return nil
            }
            return manager.radioAudioBroadcaster.currentFormat
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.observeAudio()
            }
        }

        if format != lastAnnouncedAudioFormat {
            lastAnnouncedAudioFormat = format
            audioFrameSeq = 0
            rebuildOpusEncoder(for: format)
            broadcastAudioFormatIfPossible()
        }
        attachAudioListenerIfNeeded()
    }

    /// Build (or tear down) the Opus encoder so each upstream PCM packet
    /// can be compressed once and fanned out to every subscribed client.
    /// Falls back silently to PCM if Opus isn't available on this host.
    func rebuildOpusEncoder(for format: RadioAudioFormat?) {
        opusEncoder = nil
        opusEncoderForFormat = nil
        service?.publishedAudioCodec = nil
        service?.publishedAudioFramesPerPacket = nil
        guard let format,
              format.codecTag == "pcm_s16le",
              UserDefaults.standard.bool(forKey: Self.opusEnabledKey)
        else {
            return
        }
        guard OpusCodecConfig.supportedSampleRates.contains(format.sampleRate) else {
            logger.warning("Opus disabled: unsupported source rate \(format.sampleRate) Hz")
            return
        }
        let config = OpusCodecConfig(
            sampleRate: format.sampleRate,
            channels: format.channels
        )
        guard let encoder = OpusEncoder(config: config) else {
            logger.warning("Opus disabled: encoder unavailable on this OS")
            return
        }
        opusEncoder = encoder
        opusEncoderForFormat = format
        service?.publishedAudioCodec = .opus
        service?.publishedAudioFramesPerPacket = config.framesPerPacket
        logger.info("Opus encoder ready: \(format.sampleRate) Hz mono, \(config.framesPerPacket) samples/pkt")
    }

    func attachAudioListenerIfNeeded() {
        guard audioListenerID == nil,
              let manager = service?.radioManager
        else {
            return
        }
        let broadcaster = manager.radioAudioBroadcaster
        audioListenerID = broadcaster.addListener { [weak self] data in
            self?.broadcastAudioFrame(data)
        }
    }

    func detachAudioListener() {
        guard let id = audioListenerID,
              let manager = service?.radioManager
        else {
            audioListenerID = nil
            return
        }
        manager.radioAudioBroadcaster.removeListener(id: id)
        audioListenerID = nil
    }

    func broadcastAudioFormatIfPossible() {
        guard let service, let event = service.currentAudioFormatEvent() else {
            return
        }
        service.broadcast(.eventAudioFormat(event), topic: .audio)
    }

    func broadcastAudioFrame(_ data: Data) {
        guard let service, let manager = service.radioManager else {
            return
        }
        let broadcaster = manager.radioAudioBroadcaster
        // Opus path: feed PCM into the encoder, emit one wire frame per
        // Opus packet. Encoder buffers any trailing partial-frame samples.
        if let encoder = opusEncoder {
            do {
                let packets = try encoder.encode(pcmBytes: data)
                for packet in packets {
                    let event = AudioFrameEvent(
                        radioID: broadcaster.radioID,
                        sequence: audioFrameSeq,
                        samples: packet,
                        timestamp: Date()
                    )
                    audioFrameSeq &+= 1
                    service.broadcast(.eventAudioFrame(event), topic: .audio)
                }
            } catch {
                logger.error("Opus encode failed, dropping frame: \(error.localizedDescription)")
            }
            return
        }
        // PCM passthrough.
        let event = AudioFrameEvent(
            radioID: broadcaster.radioID,
            sequence: audioFrameSeq,
            samples: data,
            timestamp: Date()
        )
        audioFrameSeq &+= 1
        service.broadcast(.eventAudioFrame(event), topic: .audio)
    }
}
