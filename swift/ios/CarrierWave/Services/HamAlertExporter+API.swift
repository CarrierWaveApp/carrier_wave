// HamAlert Exporter — API Operations
//
// Network layer for HamAlert trigger management: fetch, create,
// delete triggers via the HamAlert web API.

import Foundation

extension HamAlertExporter {
    // MARK: Internal

    static let baseURL = "https://hamalert.org"
    static let cwTriggerPrefix = "[CW]"

    func login(
        session: URLSession,
        username: String,
        password: String
    ) async throws {
        guard let url = URL(string: "\(Self.baseURL)/login") else {
            throw HamAlertError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(
            "application/x-www-form-urlencoded",
            forHTTPHeaderField: "Content-Type"
        )

        let body = "username=\(formEncode(username))"
            + "&password=\(formEncode(password))"
        request.httpBody = body.data(using: .utf8)

        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200 ... 399).contains(http.statusCode)
        else {
            throw HamAlertError.loginFailed
        }
    }

    func fetchAllTriggers(
        session: URLSession
    ) async throws -> [[String: Any]] {
        guard let url = URL(
            string: "\(Self.baseURL)/ajax/triggers"
        ) else {
            throw HamAlertError.invalidURL
        }

        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse,
              http.statusCode == 200,
              let triggers = try? JSONSerialization.jsonObject(
                  with: data
              ) as? [[String: Any]]
        else {
            return []
        }

        return triggers
    }

    func createTrigger(
        _ trigger: HamAlertTrigger,
        session: URLSession
    ) async throws {
        guard let url = URL(
            string: "\(Self.baseURL)/ajax/trigger_update"
        ) else {
            throw HamAlertError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(
            "application/json", forHTTPHeaderField: "Content-Type"
        )
        request.httpBody = try JSONEncoder().encode(trigger)

        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200 ... 299).contains(http.statusCode)
        else {
            throw HamAlertError.createFailed
        }
    }

    func createRawTrigger(
        _ trigger: [String: Any],
        session: URLSession
    ) async throws {
        guard let url = URL(
            string: "\(Self.baseURL)/ajax/trigger_update"
        ) else {
            throw HamAlertError.invalidURL
        }

        // Strip the _id field so HamAlert creates a new trigger
        var payload = trigger
        payload.removeValue(forKey: "_id")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(
            "application/json", forHTTPHeaderField: "Content-Type"
        )
        request.httpBody = try JSONSerialization.data(
            withJSONObject: payload
        )

        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200 ... 299).contains(http.statusCode)
        else {
            throw HamAlertError.createFailed
        }
    }

    func deleteTriggerByID(
        _ triggerID: String,
        session: URLSession
    ) async throws -> Bool {
        guard let deleteURL = URL(
            string: "\(Self.baseURL)/ajax/trigger_delete"
        ) else {
            return false
        }
        var deleteReq = URLRequest(url: deleteURL)
        deleteReq.httpMethod = "POST"
        deleteReq.setValue(
            "application/x-www-form-urlencoded",
            forHTTPHeaderField: "Content-Type"
        )
        deleteReq.httpBody = Data("id=\(triggerID)".utf8)

        if let (_, resp) = try? await session.data(for: deleteReq),
           let httpResp = resp as? HTTPURLResponse,
           (200 ... 299).contains(httpResp.statusCode)
        {
            return true
        }
        return false
    }

    func deleteExistingCWTriggers(
        session: URLSession
    ) async throws -> Int {
        guard let url = URL(
            string: "\(Self.baseURL)/ajax/triggers"
        ) else {
            throw HamAlertError.invalidURL
        }

        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse,
              http.statusCode == 200
        else {
            return 0
        }

        let triggers = (try? JSONDecoder().decode(
            [TriggerEntry].self, from: data
        )) ?? []

        var deleted = 0
        for trigger in triggers
            where trigger.name.hasPrefix(Self.cwTriggerPrefix)
        {
            if try await deleteTriggerByID(trigger.id, session: session) {
                deleted += 1
            }
        }

        return deleted
    }

    func deleteAllTriggers(
        session: URLSession
    ) async throws -> Int {
        let triggers = try await fetchAllTriggers(session: session)
        var deleted = 0
        for trigger in triggers {
            guard let triggerID = trigger["_id"] as? String else {
                continue
            }
            if try await deleteTriggerByID(triggerID, session: session) {
                deleted += 1
            }
        }
        return deleted
    }

    // MARK: Private

    private func formEncode(_ value: String) -> String {
        value.addingPercentEncoding(
            withAllowedCharacters: .urlQueryAllowed
        ) ?? value
    }
}
