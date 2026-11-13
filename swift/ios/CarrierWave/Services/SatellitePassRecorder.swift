import AVFAudio
import UIKit

// MARK: - SatellitePassRecorder

/// Records pass audio from the mic with tap-to-mark timestamps — the
/// pointing screen's "record now, structure later" capture (P3). Voice-grade
/// AAC mono keeps a 15-minute pass around 3–4 MB; recordings prune after
/// 7 days via `SatellitePassRecordingStore`.
///
/// Foreground-only by design: the app has no background-audio mode, and the
/// pointing screen (which owns the record controls) keeps the screen awake
/// for the whole pass anyway. Recording stops when pointing mode closes.
@MainActor
@Observable
final class SatellitePassRecorder {
    // MARK: Internal

    static let shared = SatellitePassRecorder()

    private(set) var isRecording = false
    private(set) var markCount = 0
    private(set) var recordingStartedAt: Date?

    /// True after a start attempt failed on mic permission — the record
    /// button surfaces an "allow in Settings" hint.
    private(set) var permissionDenied = false

    /// Start recording for the selected bird. Returns false (and records
    /// nothing) when mic permission is denied or the recorder can't start.
    func start(noradID: Int, satelliteName: String) async -> Bool {
        guard !isRecording else {
            return true
        }
        guard await AVAudioApplication.requestRecordPermission() else {
            permissionDenied = true
            return false
        }
        permissionDenied = false
        guard let directory = try? SatellitePassRecordingStore.defaultDirectory() else {
            return false
        }
        SatellitePassRecordingStore.prune(in: directory)

        let id = UUID()
        var recording = SatellitePassRecording(
            id: id,
            noradID: noradID,
            satelliteName: satelliteName,
            startedAt: Date(),
            endedAt: nil,
            markOffsets: [],
            audioFileName: "\(id.uuidString.lowercased()).m4a"
        )
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(
                .playAndRecord, mode: .default,
                options: [.defaultToSpeaker, .allowBluetoothHFP]
            )
            try session.setActive(true)
            let recorder = try AVAudioRecorder(
                url: SatellitePassRecordingStore.audioURL(for: recording, in: directory),
                settings: Self.settings
            )
            guard recorder.record() else {
                deactivateSession()
                return false
            }
            recording.startedAt = Date()
            audioRecorder = recorder
            current = recording
            self.directory = directory
            isRecording = true
            markCount = 0
            recordingStartedAt = recording.startedAt
            return true
        } catch {
            deactivateSession()
            return false
        }
    }

    /// One "I just worked someone" tap.
    func mark() {
        guard isRecording, var recording = current, let started = recordingStartedAt else {
            return
        }
        recording.markOffsets.append(Date().timeIntervalSince(started))
        current = recording
        markCount = recording.markOffsets.count
    }

    /// Stop and persist; returns the finished recording.
    @discardableResult
    func stop() -> SatellitePassRecording? {
        guard isRecording, var recording = current, let directory else {
            return nil
        }
        audioRecorder?.stop()
        audioRecorder = nil
        deactivateSession()
        recording.endedAt = Date()
        try? SatellitePassRecordingStore.save(recording, in: directory)
        current = nil
        isRecording = false
        recordingStartedAt = nil
        return recording
    }

    /// The fresh recording (ended < 45 min ago) to play back in the
    /// post-LOS quick log; stops a still-running recording first.
    func recentRecording(noradID: Int) -> SatellitePassRecording? {
        if isRecording, current?.noradID == noradID {
            return stop()
        }
        guard let directory = try? SatellitePassRecordingStore.defaultDirectory() else {
            return nil
        }
        return SatellitePassRecordingStore.latest(noradID: noradID, in: directory)
    }

    func stopIfRecording() {
        if isRecording {
            stop()
        }
    }

    // MARK: Private

    /// Voice-grade AAC: mono, 22.05 kHz, 32 kbps.
    private static let settings: [String: Any] = [
        AVFormatIDKey: kAudioFormatMPEG4AAC,
        AVSampleRateKey: 22_050.0,
        AVNumberOfChannelsKey: 1,
        AVEncoderBitRateKey: 32_000,
    ]

    private var audioRecorder: AVAudioRecorder?
    private var current: SatellitePassRecording?
    private var directory: URL?

    private func deactivateSession() {
        try? AVAudioSession.sharedInstance().setActive(
            false, options: .notifyOthersOnDeactivation
        )
    }
}
