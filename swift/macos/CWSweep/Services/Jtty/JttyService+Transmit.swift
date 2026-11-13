import Foundation

/// Transmit side of `JttyService`: macro expansion, rendering through the
/// helper, PTT via the active radio, and gapless chaining of queued messages.
extension JttyService {
    // MARK: Internal

    /// How long PTT is asserted before audio starts, so the radio's TX
    /// switching settles. JTTY frames carry sync, so a little lead is cheap.
    static let pttLeadTime: Duration = .milliseconds(120)

    /// The F-key template expanded against the current operator fields.
    func macroText(slot: Int) -> String {
        guard macros.indices.contains(slot) else {
            return ""
        }
        return JttyMacroExpander.expand(macros[slot], context: macroContext)
    }

    /// Send F-key `slot` (0-based). A template with an empty required field
    /// is reported in the terminal instead of going on the air.
    func sendMacro(slot: Int) {
        guard macros.indices.contains(slot) else {
            return
        }
        let missing = JttyMacroExpander.missingFields(macros[slot], context: macroContext)
        guard missing.isEmpty else {
            note(.error, "F\(slot + 1) needs \(missing.joined(separator: ", "))")
            return
        }
        send(macroText(slot: slot))
    }

    /// Queue free text. Returns immediately; the message plays after whatever
    /// is already on the air (the helper chains frames without a gap).
    func send(_ raw: String) {
        let text = JttyMacroExpander.normalize(raw)
        guard !text.isEmpty else {
            return
        }
        guard isRunning, let client else {
            note(.error, "JTTY modem is not running")
            return
        }
        guard audio.isRunning else {
            note(.error, "Audio is not running — check the JTTY audio devices in Settings")
            return
        }
        setPendingTransmissions(pendingTransmissions + 1)
        let chained = isTransmitting || pendingTransmissions > 1
        let profile = profile
        let f0 = Float(toneFrequency)
        let previous = transmitChain
        transmitChain = Task { [weak self] in
            await previous?.value
            guard let self else {
                return
            }
            do {
                let rendering = try await client.transmit(
                    text: text,
                    profile: profile,
                    sampleRate: Int(JttyAudioEngine.playbackSampleRate),
                    f0: f0,
                    chained: chained
                )
                await transmit(rendering)
            } catch {
                setPendingTransmissions(pendingTransmissions - 1)
                note(.error, "TX rejected: \(error.localizedDescription)")
                await finishIfIdle()
            }
        }
    }

    /// Stop the message on the air, drop the queue, release PTT.
    func abortTransmit() {
        transmitChain?.cancel()
        transmitChain = nil
        audio.stopPlayback()
        setPendingTransmissions(0)
        if isTransmitting {
            note(.info, "TX aborted")
        }
        Task { await self.finishIfIdle(force: true) }
    }

    // MARK: Private

    private func transmit(_ rendering: JttyTxRendering) async {
        if !isTransmitting {
            setTransmitting(true)
            await keyPTT(true)
            try? await Task.sleep(for: Self.pttLeadTime)
        }
        append(JttyTerminalEntry(kind: .sent, frequency: Float(toneFrequency), text: rendering.canonicalText))
        let played = await audio.play(samples: rendering.samples, sampleRate: Double(rendering.sampleRate))
        setPendingTransmissions(pendingTransmissions - 1)
        if !played || pendingTransmissions == 0 {
            await finishIfIdle()
        }
    }

    private func finishIfIdle(force: Bool = false) async {
        guard force || pendingTransmissions == 0 else {
            return
        }
        guard isTransmitting || pttEngaged else {
            return
        }
        await keyPTT(false)
        setTransmitting(false)
    }

    private func keyPTT(_ on: Bool) async {
        guard autoPTT, let radioManager, radioManager.isConnected else {
            setPTTEngaged(false)
            return
        }
        let ok = await radioManager.setPTT(on)
        setPTTEngaged(on && ok)
        if on, !ok {
            note(.error, "Radio refused PTT — transmitting on audio only")
        }
    }
}
