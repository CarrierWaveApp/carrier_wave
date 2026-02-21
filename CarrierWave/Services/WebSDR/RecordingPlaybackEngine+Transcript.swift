import Foundation

// MARK: - Transcript & QSO Range

extension RecordingPlaybackEngine {
    // MARK: - Transcript Loading

    /// Load transcript from sidecar JSON file
    func loadTranscript(sessionId: UUID) {
        transcript = SDRRecordingTranscript.load(sessionId: sessionId)
        if transcript != nil {
            computeQSORanges()
        }
    }

    /// Set a transcript (e.g., from server response) and recompute ranges
    func setTranscript(_ newTranscript: SDRRecordingTranscript) {
        transcript = newTranscript
        computeQSORanges()
    }

    // MARK: - QSO Range Computation

    func computeQSORanges() {
        // If transcript has detected ranges, prefer those
        if let transcript, !transcript.detectedQSORanges.isEmpty {
            qsoRanges = transcript.detectedQSORanges.map {
                (start: $0.startOffset, end: $0.endOffset)
            }
            return
        }

        // Heuristic: derive ranges from QSO timestamps
        guard !qsoOffsets.isEmpty else {
            qsoRanges = []
            return
        }

        var ranges: [(start: TimeInterval, end: TimeInterval)] = []
        for i in 0 ..< qsoOffsets.count {
            let qsoTime = qsoOffsets[i]
            let start: TimeInterval
            let end: TimeInterval

            if i == 0 {
                start = max(0, qsoTime - activeLeadIn)
            } else {
                let prev = qsoOffsets[i - 1] + activeTrailOut
                let curr = qsoTime - activeLeadIn
                start = max(0, (prev + curr) / 2)
            }

            if i == qsoOffsets.count - 1 {
                end = min(duration, qsoTime + activeTrailOut)
            } else {
                let curr = qsoTime + activeTrailOut
                let next = qsoOffsets[i + 1] - activeLeadIn
                end = min(duration, (curr + next) / 2)
            }

            ranges.append((start: start, end: end))
        }
        qsoRanges = ranges
    }

    // MARK: - Active Transcript Tracking

    func updateActiveTranscript() {
        guard let lines = transcript?.lines, !lines.isEmpty else {
            activeTranscriptLineIndex = nil
            activeTranscriptWordIndex = nil
            return
        }

        // Find the line containing currentTime
        var lineIdx: Int?
        for (i, line) in lines.enumerated() {
            if currentTime >= line.startOffset, currentTime <= line.endOffset {
                lineIdx = i
                break
            }
        }

        // If not in any line, find the most recent past line
        if lineIdx == nil {
            lineIdx = lines.lastIndex { $0.endOffset <= currentTime }
        }

        activeTranscriptLineIndex = lineIdx

        // Find active word within the line
        if let li = lineIdx {
            let words = lines[li].words
            activeTranscriptWordIndex = words.firstIndex {
                currentTime >= $0.startOffset && currentTime <= $0.endOffset
            }
        } else {
            activeTranscriptWordIndex = nil
        }
    }
}
