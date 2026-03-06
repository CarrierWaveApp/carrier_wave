import CarrierWaveCore
import Foundation

// MARK: - KiwiSDRStatusFetcher

/// Fetches and parses `/status` from individual KiwiSDR receivers.
actor KiwiSDRStatusFetcher {
    // MARK: Internal

    /// Enriched receiver status from `/status` endpoint
    struct ReceiverStatus: Sendable {
        let hostPort: String
        let antenna: String
        let parsedAntenna: ParsedAntenna
        let bandsHz: String?
        let snrAll: Int?
        let snrHF: Int?
        let antConnected: Bool
        let grid: String?
        let asl: Int?
        let users: Int
        let usersMax: Int
        let uptime: Int?
        let softwareVersion: String?
    }

    /// Fetch /status for multiple receivers concurrently (max 5 in flight).
    func fetchStatuses(
        for receivers: [KiwiSDRReceiver]
    ) -> AsyncStream<ReceiverStatus> {
        AsyncStream { continuation in
            Task {
                await withTaskGroup(of: ReceiverStatus?.self) { group in
                    var inFlight = 0
                    var index = 0

                    while index < receivers.count {
                        while inFlight >= Self.maxConcurrent {
                            if let result = await group.next() {
                                inFlight -= 1
                                if let status = result {
                                    continuation.yield(status)
                                }
                            }
                        }

                        let receiver = receivers[index]
                        index += 1
                        inFlight += 1
                        group.addTask {
                            await self.fetchStatus(
                                host: receiver.host, port: receiver.port
                            )
                        }
                    }

                    for await result in group {
                        if let status = result {
                            continuation.yield(status)
                        }
                    }
                }
                continuation.finish()
            }
        }
    }

    /// Fetch single receiver /status (5s timeout)
    func fetchStatus(host: String, port: Int) async -> ReceiverStatus? {
        let urlString = "http://\(host):\(port)/status"
        guard let url = URL(string: urlString) else {
            return nil
        }

        do {
            let (data, _) = try await session.data(from: url)
            guard let text = String(data: data, encoding: .utf8) else {
                return nil
            }
            return parseStatusResponse(text, host: host, port: port)
        } catch {
            return nil
        }
    }

    // MARK: Private

    private static let maxConcurrent = 5

    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 10
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    private func parseStatusResponse(
        _ text: String, host: String, port: Int
    ) -> ReceiverStatus? {
        var fields: [String: String] = [:]
        for line in text.components(separatedBy: .newlines) {
            let parts = line.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else {
                continue
            }
            let key = String(parts[0]).trimmingCharacters(in: .whitespaces)
            let value = String(parts[1]).trimmingCharacters(in: .whitespaces)
            fields[key] = value
        }

        let antenna = fields["antenna"] ?? ""
        let parsedAntenna = AntennaDescriptionParser.parse(antenna)

        let snrParts = (fields["snr"] ?? "").components(separatedBy: ",")
        let snrAll = snrParts.first.flatMap { Int($0) }
        let snrHF = snrParts.count > 1 ? Int(snrParts[1]) : nil

        let antConnected: Bool = if let val = fields["ant_connected"] {
            val == "1" || val.lowercased() == "true" || val.lowercased() == "yes"
        } else {
            true
        }

        return ReceiverStatus(
            hostPort: "\(host):\(port)",
            antenna: antenna,
            parsedAntenna: parsedAntenna,
            bandsHz: fields["bands"],
            snrAll: snrAll, snrHF: snrHF,
            antConnected: antConnected,
            grid: fields["grid"],
            asl: fields["asl"].flatMap { Int($0) },
            users: Int(fields["users"] ?? "") ?? 0,
            usersMax: Int(fields["users_max"] ?? "") ?? 0,
            uptime: fields["uptime"].flatMap { Int($0) },
            softwareVersion: fields["sw_version"]
        )
    }
}
