import Foundation
import Testing
@testable import CWSweep

// MARK: - SDR Transcript Model Tests

@Test func transcriptWordCodable() throws {
    let word = SDRTranscriptWord(
        id: UUID(),
        startOffset: 1.0,
        endOffset: 1.5,
        text: "CQ",
        isCallsign: false,
        confidence: 0.95
    )
    let data = try JSONEncoder().encode(word)
    let decoded = try JSONDecoder().decode(SDRTranscriptWord.self, from: data)
    #expect(decoded.text == "CQ")
    #expect(decoded.startOffset == 1.0)
    #expect(decoded.endOffset == 1.5)
    #expect(decoded.confidence == 0.95)
    #expect(decoded.isCallsign == false)
}

@Test func transcriptLineCodable() throws {
    let line = SDRTranscriptLine(
        id: UUID(),
        startOffset: 0,
        endOffset: 1.0,
        words: [
            SDRTranscriptWord(
                id: UUID(),
                startOffset: 0,
                endOffset: 0.5,
                text: "CQ",
                isCallsign: false,
                confidence: 0.9
            ),
            SDRTranscriptWord(
                id: UUID(),
                startOffset: 0.5,
                endOffset: 1.0,
                text: "W1AW",
                isCallsign: true,
                confidence: 0.85
            ),
        ],
        speakerCallsign: "W1AW",
        operatorId: 0,
        toneFreqHz: 700
    )
    let data = try JSONEncoder().encode(line)
    let decoded = try JSONDecoder().decode(SDRTranscriptLine.self, from: data)
    #expect(decoded.words.count == 2)
    #expect(decoded.speakerCallsign == "W1AW")
    #expect(decoded.operatorId == 0)
    #expect(decoded.toneFreqHz == 700)
}

@Test func detectedQSORange() {
    let range = DetectedQSORange(
        callsign: "W1AW",
        startOffset: 10.0,
        endOffset: 30.0,
        loggedQSOId: nil
    )
    #expect(range.startOffset == 10.0)
    #expect(range.endOffset == 30.0)
    #expect(range.callsign == "W1AW")
    #expect(range.loggedQSOId == nil)
}

@Test func transcriptNoiseDetection() {
    let noiseLine = SDRTranscriptLine(
        id: UUID(),
        startOffset: 0,
        endOffset: 1,
        words: [SDRTranscriptWord(
            id: UUID(),
            startOffset: 0,
            endOffset: 1,
            text: "EE",
            isCallsign: false,
            confidence: 0.1
        )],
        speakerCallsign: nil,
        operatorId: nil,
        toneFreqHz: nil
    )
    #expect(SDRRecordingTranscript.isNoiseLine(noiseLine) == true)

    let signalLine = SDRTranscriptLine(
        id: UUID(),
        startOffset: 0,
        endOffset: 1,
        words: [SDRTranscriptWord(
            id: UUID(),
            startOffset: 0,
            endOffset: 1,
            text: "W1AW",
            isCallsign: true,
            confidence: 0.9
        )],
        speakerCallsign: "W1AW",
        operatorId: 0,
        toneFreqHz: 700
    )
    #expect(SDRRecordingTranscript.isNoiseLine(signalLine) == false)
}

@Test func transcriptCodableRoundTrip() throws {
    let recordingId = UUID()
    let transcript = SDRRecordingTranscript(
        recordingId: recordingId,
        lines: [
            SDRTranscriptLine(
                id: UUID(),
                startOffset: 0,
                endOffset: 2.0,
                words: [
                    SDRTranscriptWord(
                        id: UUID(),
                        startOffset: 0,
                        endOffset: 0.5,
                        text: "CQ",
                        isCallsign: false,
                        confidence: 0.95
                    ),
                    SDRTranscriptWord(
                        id: UUID(),
                        startOffset: 0.5,
                        endOffset: 1.0,
                        text: "CQ",
                        isCallsign: false,
                        confidence: 0.90
                    ),
                    SDRTranscriptWord(
                        id: UUID(),
                        startOffset: 1.0,
                        endOffset: 1.3,
                        text: "DE",
                        isCallsign: false,
                        confidence: 0.88
                    ),
                    SDRTranscriptWord(
                        id: UUID(),
                        startOffset: 1.3,
                        endOffset: 2.0,
                        text: "W1AW",
                        isCallsign: true,
                        confidence: 0.92
                    ),
                ],
                speakerCallsign: "W1AW",
                operatorId: 0,
                toneFreqHz: 700
            ),
        ],
        detectedQSORanges: [DetectedQSORange(callsign: "W1AW", startOffset: 0, endOffset: 30, loggedQSOId: nil)],
        generatedAt: Date(),
        decoderVersion: "1.0",
        averageWPM: 18,
        averageConfidence: 0.91
    )

    let data = try JSONEncoder().encode(transcript)
    let decoded = try JSONDecoder().decode(SDRRecordingTranscript.self, from: data)

    #expect(decoded.lines.count == 1)
    #expect(decoded.lines.first?.words.count == 4)
    #expect(decoded.detectedQSORanges.count == 1)
    #expect(decoded.averageWPM == 18)
    #expect(decoded.recordingId == recordingId)
}
