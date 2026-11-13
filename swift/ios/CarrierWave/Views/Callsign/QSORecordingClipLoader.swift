import CarrierWaveData
import Foundation
import SwiftData

// MARK: - QSORecordingClip

/// A recording segment matching a specific QSO — for inline playback.
struct QSORecordingClip {
    /// The recording's persistent ID
    let recordingId: UUID
    /// File URL for the recording audio
    let fileURL: URL?
    /// Start offset in seconds from recording start
    let startOffset: TimeInterval
    /// End offset in seconds from recording start
    let endOffset: TimeInterval
    /// Logging session ID the recording belongs to
    let sessionId: UUID
}

// MARK: - QSORecordingClipLoader

/// Finds recording clips for QSOs by matching DetectedQSORange entries in transcripts.
enum QSORecordingClipLoader {
    // MARK: Internal

    /// Load clips for all QSOs with a given callsign.
    ///
    /// For each QSO that has a `loggingSessionId`, checks if a completed recording
    /// exists for that session and whether the transcript contains a `DetectedQSORange`
    /// matching either the QSO's ID or the callsign + time proximity.
    static func loadClips(
        for callsign: String,
        qsos: [QSO],
        modelContext: ModelContext
    ) -> [UUID: QSORecordingClip] {
        let sessionIds = Set(qsos.compactMap(\.loggingSessionId))
        guard !sessionIds.isEmpty else {
            return [:]
        }

        let recordings: [WebSDRRecording]
        do {
            recordings = try WebSDRRecording.findRecordings(
                forSessionIds: Array(sessionIds),
                in: modelContext
            )
        } catch {
            return [:]
        }

        let recordingsBySession = Dictionary(
            grouping: recordings,
            by: \.loggingSessionId
        )

        var result: [UUID: QSORecordingClip] = [:]
        let upperCallsign = callsign.uppercased()

        for qso in qsos {
            guard let sessionId = qso.loggingSessionId,
                  let recording = recordingsBySession[sessionId]?.first
            else {
                continue
            }

            guard let transcript = SDRRecordingTranscript.load(sessionId: sessionId) else {
                continue
            }

            let matchingRange = findMatchingRange(
                callsign: upperCallsign,
                qsoId: qso.id,
                ranges: transcript.detectedQSORanges
            )

            if let range = matchingRange {
                result[qso.id] = QSORecordingClip(
                    recordingId: recording.id,
                    fileURL: recording.fileURL,
                    startOffset: range.startOffset,
                    endOffset: range.endOffset,
                    sessionId: sessionId
                )
            }
        }

        return result
    }

    // MARK: Private

    private static func findMatchingRange(
        callsign: String,
        qsoId: UUID,
        ranges: [DetectedQSORange]
    ) -> DetectedQSORange? {
        // Prefer exact QSO ID match
        if let exact = ranges.first(where: { $0.loggedQSOId == qsoId }) {
            return exact
        }
        // Fall back to callsign match (first one)
        return ranges.first { $0.callsign.uppercased() == callsign }
    }
}
