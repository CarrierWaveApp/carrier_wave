import CarrierWaveData
import Foundation

// MARK: - JttyService

/// The JTTY modem for CW Sweep (CAR-351): owns the jtty-sidecar helper
/// process, the shared-memory client, the audio engine and the terminal
/// state the JTTY panel renders. Transmit (PTT, playback, macros) lives in
/// `JttyService+Transmit.swift`.
///
/// JTTY is WSJT-X 3.2's keyboard/contest mode. WSJT-X itself exposes neither
/// received text nor an external transmit path on macOS, so the modem runs
/// in-process-adjacent: the GPL helper decodes and renders, CW Sweep does
/// everything else.
@MainActor
@Observable
final class JttyService {
    // MARK: Lifecycle

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isEnabled = defaults.bool(forKey: DefaultsKey.enabled)
        inputDeviceUID = defaults.string(forKey: DefaultsKey.inputDeviceUID)
        outputDeviceUID = defaults.string(forKey: DefaultsKey.outputDeviceUID)
        let storedTone = defaults.double(forKey: DefaultsKey.toneFrequency)
        toneFrequency = storedTone > 0 ? storedTone : 1_500
        profile = JttyExchangeProfile(rawValue: defaults.integer(forKey: DefaultsKey.profile)) ?? .serial
        let storedMacros = defaults.stringArray(forKey: DefaultsKey.macros) ?? []
        macros = storedMacros.count == JttyMacroExpander.slotCount
            ? storedMacros : JttyMacroExpander.defaultTemplates
        autoPTT = defaults.object(forKey: DefaultsKey.autoPTT) == nil
            ? true : defaults.bool(forKey: DefaultsKey.autoPTT)
        let storedPath = defaults.string(forKey: DefaultsKey.customHelperPath)
        customHelperPath = storedPath
        serial = max(1, defaults.integer(forKey: DefaultsKey.serial))
        exchange = defaults.string(forKey: DefaultsKey.exchange) ?? ""
        sidecarStatus = JttySidecarInstaller.resolve(customPath: storedPath) == nil ? .notInstalled : .stopped
    }

    // MARK: Internal

    enum DefaultsKey {
        static let enabled = "jtty.enabled"
        static let inputDeviceUID = "jtty.audio.inputUID"
        static let outputDeviceUID = "jtty.audio.outputUID"
        static let toneFrequency = "jtty.toneFrequency"
        static let profile = "jtty.exchangeProfile"
        static let macros = "jtty.macros"
        static let autoPTT = "jtty.autoPTT"
        static let customHelperPath = "jtty.helperPath"
        static let serial = "jtty.serial"
        static let exchange = "jtty.exchange"
    }

    static let maxEntries = 400
    static let maxHelperLog = 60

    // MARK: Live state

    var sidecarStatus: JttySidecarStatus
    var isRunning = false
    var audioError: String?
    var inputLevel: Float = 0
    var entries: [JttyTerminalEntry] = []
    var helperLog: [String] = []
    var decoderRestarts: Int32 = 0
    var droppedSamples: Int64 = 0
    private(set) var isTransmitting = false
    private(set) var pttEngaged = false
    /// Messages queued behind the one on the air.
    private(set) var pendingTransmissions = 0

    // MARK: Operator fields (not persisted)

    var hisCall = ""
    var queuedCall = ""

    // MARK: App hooks

    var radioManager: RadioManager?
    /// Operator callsign for `%M`. Default: shared Keychain, then UserDefaults.
    var myCallProvider: @MainActor () -> String = {
        if let keychain = try? KeychainHelper.shared.readString(for: KeychainHelper.Keys.currentCallsign),
           !keychain.isEmpty
        {
            return keychain.uppercased()
        }
        return UserDefaults.standard.string(forKey: "myCallsign")?.uppercased() ?? ""
    }

    var myGridProvider: @MainActor () -> String = {
        UserDefaults.standard.string(forKey: "myGrid") ?? ""
    }

    // MARK: Internal (transmit extension)

    var client: JttySidecarClient?
    let audio = JttyAudioEngine()
    var transmitChain: Task<Void, Never>?

    // MARK: Runtime state (used by the runtime extension)

    let defaults: UserDefaults
    var process: JttySidecarProcess?
    var pollTask: Task<Void, Never>?
    var isStarting = false
    /// Wall-clock time of receive sample 0, for timestamping decodes.
    var streamEpoch = Date()

    // MARK: Persisted settings

    var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: DefaultsKey.enabled) }
    }

    var inputDeviceUID: String? {
        didSet { defaults.set(inputDeviceUID, forKey: DefaultsKey.inputDeviceUID) }
    }

    var outputDeviceUID: String? {
        didSet { defaults.set(outputDeviceUID, forKey: DefaultsKey.outputDeviceUID) }
    }

    /// Lowest tone of the transmitted waveform and the preferred receive channel.
    var toneFrequency: Double {
        didSet {
            defaults.set(toneFrequency, forKey: DefaultsKey.toneFrequency)
            client?.setSearch(f0: Float(toneFrequency))
        }
    }

    var profile: JttyExchangeProfile {
        didSet { defaults.set(profile.rawValue, forKey: DefaultsKey.profile) }
    }

    /// F1…F8 templates, WSJT-X `%M`/`%H`/`%E`/`%Q` syntax.
    var macros: [String] {
        didSet { defaults.set(macros, forKey: DefaultsKey.macros) }
    }

    /// Key the connected radio's PTT around each transmission (else rely on VOX).
    var autoPTT: Bool {
        didSet { defaults.set(autoPTT, forKey: DefaultsKey.autoPTT) }
    }

    /// A user-supplied helper executable instead of the staged download.
    var customHelperPath: String? {
        didSet {
            defaults.set(customHelperPath, forKey: DefaultsKey.customHelperPath)
            if !isRunning {
                sidecarStatus = helperURL == nil ? .notInstalled : .stopped
            }
        }
    }

    var serial: Int {
        didSet { defaults.set(serial, forKey: DefaultsKey.serial) }
    }

    var exchange: String {
        didSet { defaults.set(exchange, forKey: DefaultsKey.exchange) }
    }

    var helperURL: URL? {
        JttySidecarInstaller.resolve(customPath: customHelperPath)
    }

    var isHelperInstalled: Bool {
        helperURL != nil
    }

    var macroContext: JttyMacroContext {
        JttyMacroContext(
            myCall: myCallProvider(),
            hisCall: hisCall,
            queuedCall: queuedCall,
            serial: serial,
            exchange: exchange,
            grid: myGridProvider(),
            profile: profile
        )
    }

    /// Callsign tokens in a received line, for click-to-fill.
    nonisolated static func callsigns(in text: String) -> [String] {
        // Built per call: `Regex` is not Sendable, so it cannot live in a static on a main-actor type.
        let pattern = /[A-Z0-9]{1,3}[0-9][A-Z0-9]{0,3}[A-Z](?:\/[A-Z0-9]{1,4})?/
        return text.split(separator: " ").map(String.init).filter { token in
            token.count >= 3 && token.wholeMatch(of: pattern) != nil
        }
    }

    func startIfEnabled() async {
        guard isEnabled else {
            return
        }
        await start()
    }

    func setEnabled(_ enabled: Bool) async {
        isEnabled = enabled
        if enabled {
            await start()
        } else {
            stop()
        }
    }

    /// Download the pinned helper release. Safe to call again (re-verifies).
    func installHelper() async {
        guard !isRunning else {
            return
        }
        sidecarStatus = .installing(0)
        do {
            let url = try await JttySidecarInstaller.install { [weak self] progress in
                Task { @MainActor in self?.sidecarStatus = .installing(progress) }
            }
            let version = try await JttySidecarInstaller.reportedVersion(of: url)
            sidecarStatus = .stopped
            note(.info, "Installed \(version)")
        } catch {
            sidecarStatus = .notInstalled
            note(.error, "Helper install failed: \(error.localizedDescription)")
        }
    }

    func start() async {
        guard !isRunning, !isStarting else {
            return
        }
        isStarting = true
        defer { isStarting = false }
        audioError = nil
        guard let executable = helperURL else {
            sidecarStatus = .notInstalled
            return
        }
        sidecarStatus = .starting
        let name = "cwsweep-jtty-\(getpid())"
        let process = JttySidecarProcess(executable: executable, segmentName: name)
        process.onLog = { [weak self] line in
            Task { @MainActor in self?.appendHelperLog(line) }
        }
        process.onExit = { [weak self] status in
            Task { @MainActor in self?.helperExited(status) }
        }
        do {
            try process.start()
        } catch {
            sidecarStatus = .failed("Could not launch helper: \(error.localizedDescription)")
            return
        }
        self.process = process

        guard let client = await waitForSegment(named: name) else {
            sidecarStatus = .failed("Helper did not publish its shared memory segment")
            process.terminate()
            self.process = nil
            return
        }
        self.client = client
        client.setSearch(f0: Float(toneFrequency))
        let version = await (try? JttySidecarInstaller.reportedVersion(of: executable)) ?? "jtty-sidecar"
        sidecarStatus = .running(version: version)
        isRunning = true
        startAudio()
        startPolling()
        note(.info, "JTTY modem ready — \(version)")
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        abortTransmit()
        audio.stop()
        client?.send(command: .quit)
        client?.close()
        client = nil
        let process = process
        self.process = nil
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
            process?.terminate()
        }
        if isRunning {
            note(.info, "JTTY modem stopped")
        }
        isRunning = false
        inputLevel = 0
        sidecarStatus = helperURL == nil ? .notInstalled : .stopped
    }

    /// Re-open the audio engine on the currently selected devices.
    func restartAudio() {
        guard isRunning else {
            return
        }
        startAudio()
    }

    /// Forget all receive state in the decoder.
    func resetDecoder() {
        client?.send(command: .reset)
        note(.info, "Decoder reset")
    }

    func clearTerminal() {
        entries.removeAll()
    }

    func nextSerial() {
        serial += 1
    }

    func note(_ kind: JttyTerminalEntry.Kind, _ text: String) {
        append(JttyTerminalEntry(kind: kind, text: text))
    }

    func append(_ entry: JttyTerminalEntry) {
        entries.append(entry)
        if entries.count > Self.maxEntries {
            entries.removeFirst(entries.count - Self.maxEntries)
        }
    }

    func setTransmitting(_ transmitting: Bool) {
        isTransmitting = transmitting
    }

    func setPTTEngaged(_ engaged: Bool) {
        pttEngaged = engaged
    }

    func setPendingTransmissions(_ count: Int) {
        pendingTransmissions = max(0, count)
    }
}
