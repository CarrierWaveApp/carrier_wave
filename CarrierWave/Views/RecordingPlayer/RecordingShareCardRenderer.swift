import SwiftUI

// MARK: - ShareCardInput

/// Input parameters for rendering a share card
struct ShareCardInput {
    let recording: WebSDRRecording
    let clipStart: TimeInterval
    let clipEnd: TimeInterval
    let qsos: [QSO]
    let transcriptSnippet: String?
    let amplitudes: [Float]
    let duration: TimeInterval
}

// MARK: - RecordingShareCardRenderer

/// Renders RecordingShareCardView to UIImage for sharing.
@MainActor
enum RecordingShareCardRenderer {
    // MARK: Internal

    /// Render a recording share card to UIImage
    static func render(_ input: ShareCardInput) async -> RecordingShareCardData? {
        let recording = input.recording
        let clipStart = input.clipStart
        let clipEnd = input.clipEnd
        let transcriptSnippet = input.transcriptSnippet
        let amplitudes = input.amplitudes
        let duration = input.duration
        // Filter QSOs to those within clip range
        let clipQSOs = input.qsos.filter { qso in
            let offset = qso.timestamp.timeIntervalSince(recording.startedAt)
            return offset >= clipStart - 90 && offset <= clipEnd + 15
        }

        let cardView = RecordingShareCardView(
            recording: recording,
            clipStart: clipStart,
            clipEnd: clipEnd,
            qsos: clipQSOs,
            transcriptSnippet: transcriptSnippet,
            amplitudes: amplitudes,
            duration: duration
        )

        let height = computeHeight(
            qsoCount: clipQSOs.count,
            hasTranscript: transcriptSnippet != nil
        )
        let wrappedView = cardView.frame(width: 400, height: height)

        let renderer = ImageRenderer(content: wrappedView)
        renderer.scale = 2.0
        renderer.isOpaque = true

        guard let image = renderer.uiImage else {
            return nil
        }

        return RecordingShareCardData(
            image: image,
            recording: recording,
            clipStart: clipStart,
            clipEnd: clipEnd,
            qsoCount: clipQSOs.count
        )
    }

    // MARK: Private

    private static func computeHeight(
        qsoCount: Int, hasTranscript: Bool
    ) -> CGFloat {
        let base: CGFloat = 340
        let transcriptHeight: CGFloat = hasTranscript ? 80 : 0
        let qsoHeight: CGFloat = min(CGFloat(qsoCount), 4) * 22
        let overflow: CGFloat = qsoCount > 4 ? 18 : 0
        return base + transcriptHeight + qsoHeight + overflow
    }
}
