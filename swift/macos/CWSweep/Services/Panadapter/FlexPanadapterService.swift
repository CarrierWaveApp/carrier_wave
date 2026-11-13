import CarrierWaveData
import Foundation
import Network
import OSLog

private let logger = Logger(subsystem: "com.jsvana.CWSweep", category: "FlexPanadapter")

// MARK: - FlexPanadapterService

/// Bridge between SmartSDR's panadapter UDP stream and the shared
/// `WaterfallStore`. Lifecycle:
///
/// 1. `start(...)` binds a UDP listener on a free local port and
///    captures a geometry provider (so center / span come from the
///    radio's slice frequency without coupling the service to RadioManager).
/// 2. `attach(session:handler:)` sends `client udpport` and
///    `display pan create`. The first VITA-49 stream we see becomes the
///    "live" panadapter handle.
/// 3. Incoming datagrams are parsed and converted to normalized 0..1
///    lines; each line is pushed into the store.
/// 4. `stop()` removes the panadapter stream and tears down the listener.
///
/// SmartSDR amplitudes are Float32 dB. We map a fixed dB window into 0..1
/// so the renderer doesn't need to know the source.
@MainActor
final class FlexPanadapterService {
    // MARK: Lifecycle

    init(store: WaterfallStore) {
        self.store = store
    }

    // MARK: Internal

    /// Default panadapter parameters. Bin count chosen to roughly match the
    /// SCU-LAN10 effective bin count so the UI feels consistent across radios.
    static let defaultBinCount = 1_024
    static let defaultBandwidthMHz = 0.1
    static let defaultFps = 10

    /// dB floor / ceiling for amplitude normalization. The window matches
    /// SmartSDR's typical waterfall coloring range.
    static let dbFloor: Float = -120
    static let dbCeiling: Float = -20

    private(set) var streamHandle: UInt32?
    private(set) var localPort: UInt16 = 0
    private(set) var isRunning = false

    /// Bind a UDP listener and remember how to look up the radio's current
    /// frequency / bandwidth. `geometryProvider` is invoked on the main
    /// actor every time a frame arrives so the panel stays accurate as the
    /// operator retunes.
    func start(
        radioHost: String,
        geometryProvider: @escaping @MainActor () -> (centerMHz: Double, spanKHz: Double)
    ) {
        guard !isRunning else {
            return
        }
        self.radioHost = radioHost
        self.geometryProvider = geometryProvider
        bindListener()
        isRunning = true
    }

    /// Tear down the panadapter stream, UDP listener, and clear the store.
    func stop() {
        if let handle = streamHandle, let session = attachedSession,
           let handler = attachedHandler
        {
            let cmd = handler.encodePanadapterRemove(handle: handle)
            Task { try? await session.sendRaw(cmd) }
        }
        streamHandle = nil
        listener?.cancel()
        listener = nil
        attachedSession = nil
        attachedHandler = nil
        store.setReceiving(false, source: .flex)
        if store.source == .flex {
            store.clear(producer: .flex)
        }
        isRunning = false
        localPort = 0
    }

    /// Send the panadapter create commands once the radio session is up.
    /// We don't try to correlate the response back to a handle — instead we
    /// latch onto the first VITA-49 stream we see, which matches FlexLib's
    /// reference fire-and-forget pattern.
    func attach(session: RadioSession, handler: FlexProtocolHandler) async {
        guard isRunning, localPort > 0 else {
            logger.warning("attach called before listener bound")
            return
        }
        attachedSession = session
        attachedHandler = handler

        try? await session.sendRaw(handler.encodeClientUdpPort(localPort))

        let geometry = geometryProvider?() ?? (
            centerMHz: Self.defaultCenterFallback,
            spanKHz: Self.defaultBandwidthMHz * 1_000
        )
        let createCmd = handler.encodePanadapterCreate(
            binCount: Self.defaultBinCount,
            centerMHz: geometry.centerMHz > 0 ? geometry.centerMHz : Self.defaultCenterFallback,
            bandwidthMHz: max(Self.defaultBandwidthMHz, geometry.spanKHz / 1_000),
            fps: Self.defaultFps
        )
        try? await session.sendRaw(createCmd)
    }

    // MARK: Private

    private static let defaultCenterFallback: Double = 14.0

    private let store: WaterfallStore
    private var listener: NWListener?
    private var radioHost: String?
    private var geometryProvider: (@MainActor () -> (centerMHz: Double, spanKHz: Double))?
    private var attachedSession: RadioSession?
    private var attachedHandler: FlexProtocolHandler?

    /// Static + weak ref so the UDP receive loop can recurse without
    /// crossing actor boundaries at every callback. Hops to the main actor
    /// only when there's a payload to deliver.
    private static func receiveNext(on connection: NWConnection, service: FlexPanadapterService?) {
        connection.receiveMessage { [weak service] data, _, _, error in
            if let error {
                logger.warning("UDP receive error: \(error.localizedDescription)")
                return
            }
            if let data, !data.isEmpty {
                Task { @MainActor [weak service] in
                    service?.handleDatagram(data)
                }
            }
            FlexPanadapterService.receiveNext(on: connection, service: service)
        }
    }

    private func bindListener() {
        do {
            let parameters = NWParameters.udp
            parameters.allowLocalEndpointReuse = true
            let newListener = try NWListener(using: parameters, on: .any)
            listener = newListener

            newListener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor [weak self] in
                    self?.handleListenerState(state)
                }
            }
            newListener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor [weak self] in
                    self?.acceptConnection(connection)
                }
            }
            newListener.start(queue: .global(qos: .userInitiated))
        } catch {
            logger.error("Failed to bind panadapter UDP listener: \(error.localizedDescription)")
            listener = nil
        }
    }

    private func handleListenerState(_ state: NWListener.State) {
        switch state {
        case .ready:
            if let port = listener?.port?.rawValue {
                localPort = port
                logger.info("Panadapter UDP listener ready on port \(port)")
            }
        case let .failed(error):
            logger.error("Panadapter UDP listener failed: \(error.localizedDescription)")
            stop()
        default:
            break
        }
    }

    private func acceptConnection(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .userInitiated))
        Self.receiveNext(on: connection, service: self)
    }

    private func handleDatagram(_ data: Data) {
        let frame: Vita49.Frame
        do {
            frame = try Vita49.parse(data)
        } catch {
            return
        }

        if streamHandle == nil {
            streamHandle = frame.streamID
            store.setReceiving(true, source: .flex)
            logger.info("Panadapter stream \(String(format: "0x%08X", frame.streamID)) acquired")
        }
        guard frame.streamID == streamHandle else {
            return
        }
        guard let line = decodePanadapterPayload(frame.payload) else {
            return
        }
        let geometry = geometryProvider?() ?? (
            centerMHz: Self.defaultCenterFallback,
            spanKHz: Self.defaultBandwidthMHz * 1_000
        )
        store.append(
            line: line,
            centerMHz: geometry.centerMHz,
            spanKHz: geometry.spanKHz > 0 ? geometry.spanKHz : Self.defaultBandwidthMHz * 1_000,
            source: .flex
        )
    }

    /// Convert SmartSDR's panadapter payload to a normalized 0..1 line.
    ///
    /// Per the FlexLib data format, the payload is a header followed by
    /// `numBins` Float32 dB values (big-endian). The header is:
    /// ```
    ///   start_bin_index (UInt16)
    ///   num_bins        (UInt16)
    ///   bin_size_hz     (UInt32)
    ///   total_bins      (UInt16)
    ///   frame_index     (UInt16)
    /// ```
    /// We only consume `numBins` here.
    private func decodePanadapterPayload(_ payload: Data) -> [Float]? {
        let headerSize = 12
        guard payload.count >= headerSize + 4 else {
            return nil
        }
        let numBins = Int(UInt16(payload[2]) << 8 | UInt16(payload[3]))
        let availableFloats = (payload.count - headerSize) / MemoryLayout<Float32>.size
        let count = min(numBins, availableFloats)
        guard count > 0 else {
            return nil
        }

        var line = [Float](repeating: 0, count: count)
        let span = Self.dbCeiling - Self.dbFloor
        payload.withUnsafeBytes { raw in
            guard let base = raw.baseAddress?.advanced(by: headerSize) else {
                return
            }
            for idx in 0 ..< count {
                let bytes = base.advanced(by: idx * 4)
                let raw32 = bytes.load(as: UInt32.self).bigEndian
                let dbValue = Float(bitPattern: raw32)
                let clamped = max(Self.dbFloor, min(Self.dbCeiling, dbValue))
                line[idx] = (clamped - Self.dbFloor) / span
            }
        }
        return line
    }
}
