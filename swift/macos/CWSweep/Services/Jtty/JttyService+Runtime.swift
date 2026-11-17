import CarrierWaveData
import Foundation
import OSLog

private let logger = Logger(subsystem: "com.jsvana.CWSweep", category: "JttyService")

/// Runtime side of `JttyService`: audio start-up, decode polling, health
/// checks and helper-process log/exit handling.
extension JttyService {
    // MARK: Internal

    func startAudio() {
        guard let client else {
            return
        }
        audio.stop()
        audio.onLevel = { [weak self] level in
            Task { @MainActor in self?.inputLevel = level }
        }
        streamEpoch = Date().addingTimeInterval(
            -Double(client.totalSamplesWritten) / Double(JttyShmLayout.sampleRate)
        )
        do {
            try audio.start(inputDeviceUID: inputDeviceUID, outputDeviceUID: outputDeviceUID) { samples in
                client.writeReceiveAudio(samples)
            }
            audioError = nil
        } catch {
            audioError = error.localizedDescription
            note(.error, "Audio: \(error.localizedDescription)")
        }
    }

    func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            var ticks = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))
                guard let self, !Task.isCancelled else {
                    return
                }
                poll()
                ticks += 1
                if ticks.isMultiple(of: 20) {
                    checkHealth()
                }
            }
        }
    }

    func poll() {
        guard let client else {
            return
        }
        for result in client.drainResults() {
            merge(result)
        }
    }

    func merge(_ result: JttyDecodeResult) {
        let date = streamEpoch.addingTimeInterval(Double(result.startSample) / Double(JttyShmLayout.sampleRate))
        if let index = entries.lastIndex(where: { $0.kind == .received(messageId: result.messageId) }) {
            entries[index].text = result.text
            entries[index].frequency = result.frequency
            entries[index].isComplete = result.isComplete
            entries[index].date = date
        } else {
            append(JttyTerminalEntry(
                kind: .received(messageId: result.messageId),
                date: date,
                frequency: result.frequency,
                text: result.text,
                isComplete: result.isComplete
            ))
        }
    }

    func checkHealth() {
        guard let client else {
            return
        }
        decoderRestarts = client.decoderRestarts
        droppedSamples = client.droppedSamples
        if client.serverState == .quitting || process?.isRunning == false {
            helperExited(-1)
        }
    }

    func waitForSegment(named name: String) async -> JttySidecarClient? {
        for _ in 0 ..< 100 {
            if let client = try? JttySidecarClient.open(name: name), client.isReady {
                return client
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return nil
    }

    func appendHelperLog(_ line: String) {
        helperLog.append(line)
        if helperLog.count > Self.maxHelperLog {
            helperLog.removeFirst(helperLog.count - Self.maxHelperLog)
        }
    }

    func helperExited(_ status: Int32) {
        guard isRunning else {
            return
        }
        pollTask?.cancel()
        pollTask = nil
        abortTransmit()
        audio.stop()
        client?.close()
        client = nil
        process = nil
        isRunning = false
        inputLevel = 0
        let tail = helperLog.suffix(3).joined(separator: " · ")
        sidecarStatus = .failed("Helper exited (\(status))\(tail.isEmpty ? "" : ": \(tail)")")
        note(.error, "JTTY helper exited unexpectedly")
    }
}
