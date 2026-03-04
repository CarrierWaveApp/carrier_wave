import CarrierWaveData
import Foundation

// MARK: - Audio Processing and Decoding

extension CWTranscriptionService {
    func processAudioStream(_ stream: AsyncStream<CWAudioCapture.AudioBuffer>) async {
        var bufferCount = 0
        for await buffer in stream {
            bufferCount += 1
            if bufferCount.isMultiple(of: 100) {
                print("[CW] Processed \(bufferCount) audio buffers")
            }
            guard !Task.isCancelled else {
                break
            }

            await processAudioBuffer(buffer)
        }
    }

    func processAudioBuffer(_ buffer: CWAudioCapture.AudioBuffer) async {
        // Create signal processor on first buffer using actual sample rate
        if signalProcessor == nil {
            createSignalProcessor(sampleRate: buffer.sampleRate)
        }

        guard let processor = signalProcessor else {
            return
        }

        // Apply pre-amp boost if enabled
        let samples = preAmpEnabled ? buffer.samples.map { $0 * preAmpGain } : buffer.samples
        let result = await processor.process(samples: samples, timestamp: buffer.timestamp)

        lastAudioTimestamp = buffer.timestamp
        updateUIState(from: result)

        // Process key events through decoder
        guard let decoder = morseDecoder else {
            return
        }
        for event in result.keyEvents {
            let outputs = await decoder.processKeyEvent(
                isKeyDown: event.isDown, timestamp: event.timestamp
            )
            await processDecoderOutputs(outputs)
        }

        // Update WPM
        let wpm = await decoder.estimatedWPM
        if estimatedWPM != wpm {
            estimatedWPM = wpm
        }
    }

    func createSignalProcessor(sampleRate: Double) {
        if adaptiveFrequencyEnabled {
            print(
                "[CW] Creating adaptive signal processor: \(Int(minFrequency))-\(Int(maxFrequency)) Hz"
            )
            signalProcessor = GoertzelSignalProcessor(
                sampleRate: sampleRate,
                minFrequency: minFrequency,
                maxFrequency: maxFrequency,
                frequencyStep: 50
            )
        } else {
            print("[CW] Creating fixed signal processor at \(Int(toneFrequency)) Hz")
            signalProcessor = GoertzelSignalProcessor(
                sampleRate: sampleRate, toneFrequency: toneFrequency
            )
        }
    }

    func updateUIState(from result: CWSignalResult) {
        isKeyDown = result.isKeyDown
        peakAmplitude = result.peakAmplitude
        waveformSamples = result.envelopeSamples
        isCalibrating = result.isCalibrating
        noiseFloor = result.noiseFloor
        signalToNoiseRatio = result.signalToNoiseRatio
        detectedFrequency = result.detectedFrequency
    }

    func processDecoderOutputs(_ outputs: [DecodedOutput]) async {
        for output in outputs {
            switch output {
            case let .character(char):
                print("[CW] Service received character: '\(char)'")
                await MainActor.run {
                    appendCharacter(char)
                }
            case .wordSpace:
                print("[CW] Service received word space")
                await MainActor.run {
                    appendWordSpace()
                }
            case .element:
                // Raw elements are for debugging, skip for now
                break
            }
        }
    }

    func appendCharacter(_ char: String) {
        currentLine += char
        print("[CW] currentLine is now: '\(currentLine)'")

        // Check for line wrap
        if currentLine.count >= lineWrapLength {
            flushCurrentLine()
        }
    }

    func appendWordSpace() {
        // Only add space if there's content
        if !currentLine.isEmpty {
            currentLine += " "
        }
    }

    func flushCurrentLine() {
        guard !currentLine.isEmpty else {
            return
        }

        // Find last space for word boundary
        let text: String
        let remainder: String

        if let lastSpace = currentLine.lastIndex(of: " ") {
            // Include trailing space to preserve word boundary
            text = String(currentLine[...lastSpace])
            remainder = String(currentLine[currentLine.index(after: lastSpace)...])
        } else {
            text = currentLine
            remainder = ""
        }

        let entry = CWTranscriptEntry(text: text, suggestionEngine: suggestionEngine)
        transcript.append(entry)
        currentLine = remainder

        // Forward to conversation tracker with current frequency
        conversationTracker.processEntry(entry, frequency: detectedFrequency)

        // Trim old entries
        if transcript.count > maxTranscriptEntries {
            transcript.removeFirst(transcript.count - maxTranscriptEntries)
        }

        // Update detected callsigns
        updateDetectedCallsigns()
    }

    func updateDetectedCallsigns() {
        // Extract all callsigns from current transcript
        let allText = transcript.map(\.text).joined(separator: " ") + " " + currentLine
        let newCallsigns = CallsignDetector.extractCallsigns(from: allText)

        // Update unique callsigns list
        for callsign in newCallsigns where !detectedCallsigns.contains(callsign) {
            detectedCallsigns.append(callsign)
        }

        // Update primary detected callsign
        if let primary = CallsignDetector.detectPrimaryCallsign(from: transcript) {
            detectedCallsign = primary
        }
    }

    func startTimeoutChecker() {
        timeoutTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms

                guard let decoder = morseDecoder else {
                    continue
                }
                // Use audio timestamp + elapsed time for consistent time reference
                // Add 0.1 seconds for each check interval
                let checkTime = lastAudioTimestamp + 0.1
                let outputs = await decoder.checkTimeout(currentTime: checkTime)
                await processDecoderOutputs(outputs)
            }
        }
    }
}
