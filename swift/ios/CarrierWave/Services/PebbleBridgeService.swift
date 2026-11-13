import Foundation
import Network
import OSLog

// MARK: - PebbleBridgeService

/// Localhost HTTP bridge that exposes session/solar/spots snapshots and a
/// `POST /v1/qso` endpoint to the Pebble companion. PebbleKit JS, running in
/// the Pebble iOS app on the same device, hits `http://127.0.0.1:47373` —
/// iOS exempts localhost from ATS, so no entitlements are required.
///
/// The bridge is lightweight: it reads the existing widget app-group
/// snapshots written by `WidgetDataWriter` for GETs, and posts
/// `didReceivePebbleLogQSO` for the active LoggerView to handle on POST.
/// Background suspension by iOS is acceptable — the listener resumes when
/// Field returns to the foreground (handled in `CarrierWaveApp`).
nonisolated final class PebbleBridgeService: @unchecked Sendable {
    // MARK: Lifecycle

    private init() {}

    // MARK: Internal

    static let shared = PebbleBridgeService()

    /// 47373 → "73" twice with the prefix that fits the high-port range.
    static let port: UInt16 = 47_373

    /// Starts the listener on the loopback interface. Idempotent.
    func start() {
        queue.async { self.startLocked() }
    }

    /// Stops the listener and tears down active connections.
    func stop() {
        queue.async { self.stopLocked() }
    }

    // MARK: Private

    private let log = Logger(
        subsystem: "app.carrierwave.field", category: "pebble-bridge"
    )
    private let queue = DispatchQueue(
        label: "app.carrierwave.field.pebble-bridge", qos: .utility
    )
    private var listener: NWListener?

    private func startLocked() {
        guard listener == nil, let port = NWEndpoint.Port(rawValue: Self.port) else {
            return
        }
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            params.requiredInterfaceType = .loopback
            params.includePeerToPeer = false

            let listener = try NWListener(using: params, on: port)
            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection)
            }
            listener.stateUpdateHandler = { [weak self] state in
                self?.handleListener(state: state)
            }
            listener.start(queue: queue)
            self.listener = listener
        } catch {
            log.error("Failed to bind 127.0.0.1:\(Self.port): \(error.localizedDescription)")
        }
    }

    private func stopLocked() {
        listener?.cancel()
        listener = nil
    }

    private func handleListener(state: NWListener.State) {
        switch state {
        case .ready:
            log.info("Pebble bridge ready on 127.0.0.1:\(Self.port)")
        case let .failed(error):
            log.error("Pebble bridge failed: \(error.localizedDescription)")
            stopLocked()
        case .cancelled:
            log.info("Pebble bridge cancelled")
        default:
            break
        }
    }

    private func handle(_ connection: NWConnection) {
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let connection else {
                return
            }
            if case let .failed(error) = state {
                self?.log.warning("Connection failed: \(error.localizedDescription)")
                connection.cancel()
            }
        }
        connection.start(queue: queue)
        receive(connection, buffer: Data())
    }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(
            minimumIncompleteLength: 1,
            maximumLength: 8_192
        ) { [weak self] data, _, isComplete, error in
            guard let self else {
                return
            }
            var next = buffer
            if let chunk = data {
                next.append(chunk)
            }

            if let request = HTTPRequest.parse(next) {
                Task { @MainActor in
                    let response = PebbleBridgeRoutes.handle(request)
                    connection.send(
                        content: response,
                        completion: .contentProcessed { _ in connection.cancel() }
                    )
                }
                return
            }

            if error != nil || isComplete {
                connection.cancel()
                return
            }

            // Cap unparseable buffer growth to avoid leaking memory if a
            // misbehaving client opens a connection and never sends EOF.
            if next.count > 16 * 1_024 {
                connection.cancel()
                return
            }

            receive(connection, buffer: next)
        }
    }
}
