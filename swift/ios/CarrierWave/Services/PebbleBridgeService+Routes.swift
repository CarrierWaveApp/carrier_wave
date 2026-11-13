import Foundation

// MARK: - PebbleBridgeRoutes

/// Stateless route handlers for the Pebble bridge. Reads existing app-group
/// snapshots written by `WidgetDataWriter` for GETs and posts a notification
/// for POST /v1/qso. The active LoggerView observes the notification and
/// performs the actual log via `LoggingSessionManager.logQSO`.
enum PebbleBridgeRoutes {
    // MARK: Internal

    static func handle(_ request: HTTPRequest) -> Data {
        switch (request.method, request.path) {
        case ("GET", "/v1/session"):
            session()
        case ("GET", "/v1/solar"):
            solar()
        case ("GET", "/v1/spots"):
            spots()
        case ("POST", "/v1/qso"):
            logQSO(body: request.body)
        case ("GET", "/v1/memories"):
            memories()
        case ("POST", "/v1/memories/recall"):
            recallMemory(body: request.body)
        case ("GET", "/v1/health"):
            HTTPResponse.json(status: 200, payload: ["ok": true])
        default:
            HTTPResponse.empty(status: 404)
        }
    }

    // MARK: Private

    private static let appGroup = "group.com.jsvana.FullDuplex"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroup)
    }

    private static func session() -> Data {
        guard let snapshot = readSnapshot(
            key: "widget.sessionData", as: WidgetSessionSnapshot.self
        ), snapshot.isActive else {
            return HTTPResponse.json(
                status: 404, payload: ["error": "no_active_session"]
            )
        }
        return HTTPResponse.json(status: 200, payload: snapshot)
    }

    private static func solar() -> Data {
        guard let snapshot = readSnapshot(
            key: "widget.solarData", as: WidgetSolarSnapshot.self
        ) else {
            return HTTPResponse.empty(status: 404)
        }
        return HTTPResponse.json(status: 200, payload: snapshot)
    }

    private static func spots() -> Data {
        guard let snapshot = readSnapshot(
            key: "widget.spotsData", as: SharedSpotSnapshot.self
        ) else {
            return HTTPResponse.empty(status: 404)
        }
        return HTTPResponse.json(status: 200, payload: snapshot)
    }

    private static func logQSO(body: Data) -> Data {
        guard let snapshot = readSnapshot(
            key: "widget.sessionData", as: WidgetSessionSnapshot.self
        ), snapshot.isActive else {
            return HTTPResponse.json(
                status: 404, payload: ["error": "no_active_session"]
            )
        }
        let request = decodeLogRequest(body)
        let userInfo: [String: String] = [
            "rstSent": request.rstSent ?? "599",
            "rstReceived": request.rstReceived ?? "599",
        ]
        // Posted on the bridge queue; observers are expected to hop to main.
        NotificationCenter.default.post(
            name: .didReceivePebbleLogQSO, object: nil, userInfo: userInfo
        )
        Task { @MainActor in
            AchievementSignalService.shared.reportSignal(.pebblePioneer)
        }
        return HTTPResponse.json(
            status: 200, payload: PebbleLogQSOResponse(ok: true, session: snapshot)
        )
    }

    private static func memories() -> Data {
        let keyer = RadioService.shared.cwKeyer
        let payload = keyer.slots
            .filter { !$0.isEmpty }
            .map { slot in
                PebbleCWSlotEntry(
                    id: slot.id,
                    label: slot.displayLabel,
                    text: slot.text
                )
            }
        return HTTPResponse.json(status: 200, payload: payload)
    }

    private static func recallMemory(body: Data) -> Data {
        guard !body.isEmpty,
              let req = try? JSONDecoder().decode(
                  PebbleRecallRequest.self, from: body
              )
        else {
            return HTTPResponse.json(
                status: 400, payload: ["error": "invalid_request"]
            )
        }
        let radio = RadioService.shared
        guard let bridge = radio.bridgeProtocol else {
            return HTTPResponse.json(
                status: 503, payload: ["error": "no_bridge"]
            )
        }
        let slot = UInt8(req.id)
        let context = radio.cwKeyer.buildContext(
            from: CWKeyerContext(
                callsign: "",
                myCall: UserDefaults.standard.string(
                    forKey: "loggerDefaultCallsign"
                ) ?? "",
                myName: UserDefaults.standard.string(
                    forKey: "loggerDefaultName"
                ) ?? "",
                serial: radio.cwSerialNumber,
                rstSent: "599",
                name: "",
                exchange: UserDefaults.standard.string(
                    forKey: "contestExchange"
                ) ?? ""
            )
        )
        radio.cwSendingSlot = req.id
        if bridge.hasDirectWriter {
            bridge.playCWSlotImmediate(slot, context: context)
        } else {
            Task {
                try? await bridge.playCWSlot(slot, context: context)
            }
        }
        return HTTPResponse.json(
            status: 200, payload: ["ok": true]
        )
    }

    private static func readSnapshot<T: Decodable>(
        key: String, as _: T.Type
    ) -> T? {
        guard let data = defaults?.data(forKey: key) else {
            return nil
        }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private static func decodeLogRequest(_ body: Data) -> PebbleLogQSORequest {
        guard !body.isEmpty else {
            return PebbleLogQSORequest(rstSent: nil, rstReceived: nil)
        }
        return (try? JSONDecoder().decode(
            PebbleLogQSORequest.self, from: body
        )) ?? PebbleLogQSORequest(rstSent: nil, rstReceived: nil)
    }
}

// MARK: - PebbleCWSlotEntry

private struct PebbleCWSlotEntry: Encodable {
    let id: Int
    let label: String
    let text: String
}

// MARK: - PebbleRecallRequest

private struct PebbleRecallRequest: Decodable {
    let id: Int
}

// MARK: - PebbleLogQSORequest

private struct PebbleLogQSORequest: Decodable {
    let rstSent: String?
    let rstReceived: String?
}

// MARK: - PebbleLogQSOResponse

private struct PebbleLogQSOResponse: Encodable {
    let ok: Bool
    let session: WidgetSessionSnapshot
}
