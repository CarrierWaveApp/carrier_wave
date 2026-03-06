import Foundation
import os

private let logger = Logger(subsystem: "com.jsvana.CWSweep", category: "WinKeyerManager")

// MARK: - WinKeyerManager

/// Manages WinKeyer connection and publishes state to the UI.
@MainActor
@Observable
final class WinKeyerManager {
    // MARK: Internal

    /// Whether a WinKeyer is currently connected.
    private(set) var isConnected = false

    /// Current CW speed in WPM.
    var speed: UInt8 = 25

    /// Current status flags from the WinKeyer.
    private(set) var status: WinKeyerStatus = []

    /// Firmware revision (0 = unknown).
    private(set) var firmwareVersion: UInt8 = 0

    /// Port path of the currently connected WinKeyer.
    private(set) var connectedPortPath: String?

    /// Last error message for display.
    private(set) var lastError: String?

    /// Whether the WinKeyer is actively sending CW.
    var isSending: Bool {
        status.contains(.busy)
    }

    /// Whether the send buffer is full (XOFF).
    var isBufferFull: Bool {
        status.contains(.xoff)
    }

    /// Whether paddle break-in was detected.
    var isBreakIn: Bool {
        status.contains(.breakin)
    }

    /// Device fingerprint of the last connected WinKeyer (for auto-reconnect).
    private(set) var lastDeviceFingerprint: String? {
        get { UserDefaults.standard.string(forKey: "winkeyer.lastDeviceFingerprint") }
        set { UserDefaults.standard.set(newValue, forKey: "winkeyer.lastDeviceFingerprint") }
    }

    /// Speed pot minimum WPM (used to compute actual speed from pot bytes).
    var speedPotMin: UInt8 {
        let stored = UserDefaults.standard.integer(forKey: "winkeyer.speedPotMin")
        return UInt8(clamping: max(5, min(50, stored == 0 ? 10 : stored)))
    }

    /// Speed pot range in WPM. Set to 0 to disable pot and use software speed only.
    var speedPotRange: UInt8 {
        let stored = UserDefaults.standard.integer(forKey: "winkeyer.speedPotRange")
        // Default to 35 if never set; allow 0 for disabling pot
        if UserDefaults.standard.object(forKey: "winkeyer.speedPotRange") == nil {
            return 35
        }
        return UInt8(clamping: max(0, min(60, stored)))
    }

    /// Connect to a WinKeyer using a discovered port (saves fingerprint for auto-reconnect).
    func connect(port: SerialPortMonitor.SerialPortInfo, baudRate: Int = 1_200) async {
        lastDeviceFingerprint = port.deviceFingerprint
        await connect(portPath: port.path, baudRate: baudRate)
    }

    /// Auto-connect to the last-used WinKeyer if the device is present.
    func autoConnect(ports: [SerialPortMonitor.SerialPortInfo]) async {
        guard !isConnected,
              UserDefaults.standard.bool(forKey: "winkeyer.autoConnect"),
              let fingerprint = lastDeviceFingerprint,
              let match = ports.first(where: { $0.deviceFingerprint == fingerprint })
        else {
            return
        }
        logger.info("Auto-connecting WinKeyer to \(match.path) (fingerprint match)")
        await connect(port: match)
    }

    /// Connect to a WinKeyer on the given serial port.
    func connect(portPath: String, baudRate: Int = 1_200) async {
        // Disconnect any existing session first
        if isConnected {
            await disconnect()
        }

        logger.info("Connecting to WinKeyer on \(portPath)")
        lastError = nil

        let newSession = WinKeyerSession(portPath: portPath, baudRate: baudRate)
        session = newSession

        do {
            try await newSession.start()
            connectedPortPath = portPath
            startEventConsumer(for: newSession)

            // Set initial speed BEFORE configuring pot — setSpeed locks the speed
            // register, so setSpeedPot must come last to re-enable pot reporting.
            try await newSession.setSpeed(speed)

            // Configure speed pot parameters (range=0 disables pot for pure software control)
            try await newSession.setSpeedPot(min: speedPotMin, range: speedPotRange)
        } catch {
            logger.error("Failed to connect: \(error)")
            lastError = error.localizedDescription
            session = nil
        }
    }

    /// Disconnect from the WinKeyer.
    func disconnect() async {
        eventTask?.cancel()
        eventTask = nil

        if let session {
            await session.stop()
        }
        session = nil

        isConnected = false
        connectedPortPath = nil
        status = []
        firmwareVersion = 0
        logger.info("WinKeyer disconnected")
    }

    /// Set CW speed in WPM.
    func setSpeed(_ wpm: UInt8) async {
        speed = wpm
        guard let session else {
            return
        }
        do {
            try await session.setSpeed(wpm)
        } catch {
            logger.error("Failed to set speed: \(error)")
            lastError = error.localizedDescription
        }
    }

    /// Send text as CW via the WinKeyer buffer.
    func sendText(_ text: String) async {
        guard let session else {
            return
        }
        do {
            try await session.sendText(text)
        } catch {
            logger.error("Failed to send text: \(error)")
            lastError = error.localizedDescription
        }
    }

    /// Cancel any in-progress sending and clear the buffer.
    func cancelSending() async {
        guard let session else {
            return
        }
        do {
            try await session.cancelSending()
        } catch {
            logger.error("Failed to cancel sending: \(error)")
            lastError = error.localizedDescription
        }
    }

    // MARK: Private

    private var session: WinKeyerSession?
    private var eventTask: Task<Void, Never>?

    private func startEventConsumer(for session: WinKeyerSession) {
        eventTask = Task { [weak self] in
            for await event in session.eventStream {
                guard let self, !Task.isCancelled else {
                    break
                }
                handleEvent(event)
            }
        }
    }

    private func handleEvent(_ event: WinKeyerEvent) {
        switch event {
        case let .connected(firmwareVersion):
            isConnected = true
            self.firmwareVersion = firmwareVersion
            logger.info("WinKeyer connected, firmware v\(firmwareVersion)")

        case .disconnected:
            isConnected = false
            connectedPortPath = nil
            status = []

        case let .statusChanged(newStatus):
            status = newStatus

        case let .speedPotChanged(wpm):
            // Speed pot byte is offset from minimum
            let potSpeed = speedPotMin + wpm
            speed = potSpeed
            // A prior Set Speed command locks the speed register, so relay
            // the pot-derived speed back to the WinKeyer to actually apply it.
            // Re-send setSpeedPot afterward to keep pot reporting active.
            if let session {
                Task {
                    try? await session.setSpeed(potSpeed)
                    try? await session.setSpeedPot(
                        min: self.speedPotMin, range: self.speedPotRange
                    )
                }
            }

        case .echoCharacter:
            // Could track sent characters for display; ignored for now
            break

        case let .error(message):
            lastError = message
        }
    }
}
