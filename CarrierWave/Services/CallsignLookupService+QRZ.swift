import Foundation

// MARK: - QRZ XML API

extension CallsignLookupService {
    /// QRZ XML callbook API base URL
    private static let qrzXMLURL = "https://xmldata.qrz.com/xml/current/"

    /// Look up a callsign in QRZ XML callbook
    /// Uses the logbook API key which also works for XML callbook lookups
    func lookupInQRZ(_ callsign: String) async -> CallsignInfo? {
        let result = await lookupInQRZWithResult(callsign)
        return result.info
    }

    /// Look up a callsign in QRZ with detailed result/error information
    func lookupInQRZWithResult(_ callsign: String) async -> CallsignLookupResult {
        // Get Callbook credentials from keychain
        guard
            let username = try? KeychainHelper.shared.readString(
                for: KeychainHelper.Keys.qrzCallbookUsername
            ),
            let password = try? KeychainHelper.shared.readString(
                for: KeychainHelper.Keys.qrzCallbookPassword
            )
        else {
            return .error(.noQRZApiKey)
        }

        // First, get a session key using username/password
        let sessionResult = await getQRZSessionKeyWithCredentials(
            username: username, password: password
        )
        guard let sessionKey = sessionResult.sessionKey else {
            return .error(sessionResult.error ?? .qrzAuthFailed, qrzAttempted: true)
        }

        // Then look up the callsign
        return await performQRZLookupWithResult(callsign: callsign, sessionKey: sessionKey)
    }

    /// Result from QRZ session key request
    private struct QRZSessionResult {
        let sessionKey: String?
        let error: CallsignLookupError?
    }

    /// Get a QRZ session key with error details using username/password credentials
    private func getQRZSessionKeyWithCredentials(
        username: String, password: String
    ) async -> QRZSessionResult {
        guard var urlComponents = URLComponents(string: Self.qrzXMLURL) else {
            return QRZSessionResult(sessionKey: nil, error: .qrzAuthFailed)
        }

        // QRZ XML API uses username/password authentication
        urlComponents.queryItems = [
            URLQueryItem(name: "username", value: username),
            URLQueryItem(name: "password", value: password),
            URLQueryItem(name: "agent", value: "CarrierWave"),
        ]

        guard let url = urlComponents.url else {
            return QRZSessionResult(sessionKey: nil, error: .qrzAuthFailed)
        }

        do {
            var request = URLRequest(url: url)
            request.setValue("CarrierWave/1.0", forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = 30

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200
            else {
                return QRZSessionResult(sessionKey: nil, error: .qrzAuthFailed)
            }

            guard let xmlString = String(data: data, encoding: .utf8) else {
                return QRZSessionResult(sessionKey: nil, error: .qrzAuthFailed)
            }

            // Check for error in response
            if let errorMsg = parseXMLValue(from: xmlString, tag: "Error") {
                if errorMsg.lowercased().contains("invalid")
                    || errorMsg.lowercased().contains("password")
                    || errorMsg.lowercased().contains("username")
                {
                    return QRZSessionResult(sessionKey: nil, error: .qrzAuthFailed)
                }
                return QRZSessionResult(
                    sessionKey: nil, error: .networkError(errorMsg)
                )
            }

            // Parse session key from XML response
            if let key = parseXMLValue(from: xmlString, tag: "Key") {
                return QRZSessionResult(sessionKey: key, error: nil)
            }

            return QRZSessionResult(sessionKey: nil, error: .qrzAuthFailed)
        } catch {
            return QRZSessionResult(
                sessionKey: nil,
                error: .networkError(error.localizedDescription)
            )
        }
    }

    /// Perform the actual callsign lookup with detailed result
    private func performQRZLookupWithResult(
        callsign: String,
        sessionKey: String
    ) async -> CallsignLookupResult {
        guard let url = buildQRZLookupURL(sessionKey: sessionKey, callsign: callsign) else {
            return .error(.networkError("Invalid URL"), qrzAttempted: true)
        }

        do {
            let xmlString = try await fetchQRZResponse(url: url)

            // Check for error
            if let errorMsg = parseXMLValue(from: xmlString, tag: "Error") {
                if errorMsg.lowercased().contains("not found") {
                    return .notFound(qrzAttempted: true, poloNotesChecked: true)
                }
                return .error(.networkError(errorMsg), qrzAttempted: true)
            }

            guard let info = parseCallsignInfoFromXML(xmlString, callsign: callsign) else {
                return .notFound(qrzAttempted: true, poloNotesChecked: true)
            }
            return .fromQRZ(info)
        } catch {
            return .error(.networkError(error.localizedDescription), qrzAttempted: true)
        }
    }

    private func buildQRZLookupURL(sessionKey: String, callsign: String) -> URL? {
        guard var urlComponents = URLComponents(string: Self.qrzXMLURL) else {
            return nil
        }
        urlComponents.queryItems = [
            URLQueryItem(name: "s", value: sessionKey),
            URLQueryItem(name: "callsign", value: callsign),
        ]
        return urlComponents.url
    }

    private func fetchQRZResponse(url: URL) async throws -> String {
        var request = URLRequest(url: url)
        request.setValue("CarrierWave/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw QRZLookupError.httpError
        }

        guard let xmlString = String(data: data, encoding: .utf8) else {
            throw QRZLookupError.invalidResponse
        }

        return xmlString
    }

    private func parseCallsignInfoFromXML(_ xmlString: String, callsign: String) -> CallsignInfo? {
        let firstName = parseXMLValue(from: xmlString, tag: "fname")
        let lastName = parseXMLValue(from: xmlString, tag: "name")
        let nickname = parseXMLValue(from: xmlString, tag: "nickname")
        let name = combineNames(first: firstName, last: lastName)
        let grid = parseXMLValue(from: xmlString, tag: "grid")
        let qth = parseXMLValue(from: xmlString, tag: "addr2")
        let state = parseXMLValue(from: xmlString, tag: "state")
        let country = parseXMLValue(from: xmlString, tag: "country")
        let licenseClass = parseXMLValue(from: xmlString, tag: "class")
        let previousCallsign = parseXMLValue(from: xmlString, tag: "p_call")
            ?? previousCallFromAliases(xmlString, callsign: callsign)

        guard name != nil || grid != nil || qth != nil else {
            return nil
        }

        return CallsignInfo(
            callsign: callsign,
            name: name,
            firstName: firstName,
            nickname: nickname,
            qth: qth,
            state: state,
            country: country,
            grid: grid,
            licenseClass: licenseClass,
            previousCallsign: previousCallsign,
            source: .qrz
        )
    }

    /// Extract a previous callsign from the QRZ `aliases` field.
    /// Aliases is a comma-separated list of other callsigns that resolve to this record.
    /// We pick the first alias that isn't the current callsign or a portable variant (e.g., DL/AA7BQ).
    private func previousCallFromAliases(_ xml: String, callsign: String) -> String? {
        guard let aliasesStr = parseXMLValue(from: xml, tag: "aliases") else {
            return nil
        }
        let upper = callsign.uppercased()
        let candidates = aliasesStr
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).uppercased() }
            .filter { !$0.isEmpty && $0 != upper && !$0.contains("/") }
        return candidates.first
    }

    private enum QRZLookupError: Error {
        case httpError
        case invalidResponse
    }

    /// Get a QRZ session key using username/password credentials
    func getQRZSessionKey(username: String, password: String) async -> String? {
        guard var urlComponents = URLComponents(string: Self.qrzXMLURL) else {
            return nil
        }

        // QRZ XML API uses username/password authentication
        urlComponents.queryItems = [
            URLQueryItem(name: "username", value: username),
            URLQueryItem(name: "password", value: password),
        ]

        guard let url = urlComponents.url else {
            return nil
        }

        do {
            var request = URLRequest(url: url)
            request.setValue("CarrierWave/1.0", forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = 30

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200
            else {
                return nil
            }

            guard let xmlString = String(data: data, encoding: .utf8) else {
                return nil
            }

            // Parse session key from XML response
            // Format: <Key>SESSION_KEY</Key>
            return parseXMLValue(from: xmlString, tag: "Key")
        } catch {
            return nil
        }
    }

    /// Perform the actual callsign lookup with a session key
    func performQRZLookup(callsign: String, sessionKey: String) async -> CallsignInfo? {
        guard let url = buildQRZLookupURL(sessionKey: sessionKey, callsign: callsign) else {
            return nil
        }

        do {
            let xmlString = try await fetchQRZResponse(url: url)

            // Check for error
            if xmlString.contains("<Error>") {
                return nil
            }

            return parseCallsignInfoFromXML(xmlString, callsign: callsign)
        } catch {
            return nil
        }
    }

    /// Parse a value from XML by tag name
    func parseXMLValue(from xml: String, tag: String) -> String? {
        let openTag = "<\(tag)>"
        let closeTag = "</\(tag)>"

        guard let startRange = xml.range(of: openTag),
              let endRange = xml.range(of: closeTag, range: startRange.upperBound ..< xml.endIndex)
        else {
            return nil
        }

        let value = String(xml[startRange.upperBound ..< endRange.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return value.isEmpty ? nil : value
    }

    /// Combine first and last name
    func combineNames(first: String?, last: String?) -> String? {
        if let first, let last {
            "\(first) \(last)"
        } else if let first {
            first
        } else if let last {
            last
        } else {
            nil
        }
    }
}
