import CarrierWaveData
import Foundation

// MARK: - QRZCallbookResult

/// Result from a QRZ XML callbook lookup with operator details.
struct QRZCallbookResult {
    let callsign: String
    let name: String?
    let firstName: String?
    let nickname: String?
    let grid: String?
    let city: String?
    let state: String?
    let country: String?
    let licenseClass: String?
    let previousCallsign: String?
    /// When QRZ redirects to a different canonical callsign
    let callsignChangeNote: String?
}

// MARK: - QRZCallbookClient

/// Actor for looking up callsign information from the QRZ XML callbook API.
/// Requires QRZ Callbook credentials stored in Keychain (shared with iOS app).
actor QRZCallbookClient {
    // MARK: Internal

    /// Last error for debugging — set on each lookup attempt.
    var lastError: String?

    /// Look up a callsign in the QRZ XML callbook.
    /// Returns nil if credentials are not configured or lookup fails.
    func lookup(callsign: String) async -> QRZCallbookResult? {
        lastError = nil

        guard let credentials = readCredentials() else {
            lastError = "no keychain credentials"
            return nil
        }

        guard let sessionKey = await getSessionKey(credentials: credentials) else {
            // lastError already set by getSessionKey
            return nil
        }

        return await performLookup(callsign: callsign, sessionKey: sessionKey)
    }

    // MARK: Private

    private struct Credentials {
        let username: String
        let password: String
    }

    private static let qrzXMLURL = "https://xmldata.qrz.com/xml/current/"

    private static let lookupSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 15
        return URLSession(configuration: config)
    }()

    /// Cached session key with expiration
    private var cachedSessionKey: String?
    private var sessionKeyTimestamp: Date?
    private let sessionKeyTTL: TimeInterval = 3_600

    private func readCredentials() -> Credentials? {
        guard
            let username = try? KeychainHelper.shared.readString(
                for: KeychainHelper.Keys.qrzCallbookUsername
            ),
            let password = try? KeychainHelper.shared.readString(
                for: KeychainHelper.Keys.qrzCallbookPassword
            )
        else {
            return nil
        }
        return Credentials(username: username, password: password)
    }

    private func getSessionKey(credentials: Credentials) async -> String? {
        // Use cached session key if still valid
        if let cached = cachedSessionKey,
           let ts = sessionKeyTimestamp,
           Date().timeIntervalSince(ts) < sessionKeyTTL
        {
            return cached
        }

        guard var components = URLComponents(string: Self.qrzXMLURL) else {
            return nil
        }

        components.queryItems = [
            URLQueryItem(name: "username", value: credentials.username),
            URLQueryItem(name: "password", value: credentials.password),
            URLQueryItem(name: "agent", value: "CWSweep"),
        ]

        guard let url = components.url else {
            return nil
        }

        do {
            var request = URLRequest(url: url)
            request.setValue("CWSweep/1.0", forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = 15

            let (data, response) = try await Self.lookupSession.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200,
                  let xml = String(data: data, encoding: .utf8)
            else {
                return nil
            }

            // Check for auth errors
            if let err = parseXMLValue(from: xml, tag: "Error") {
                lastError = "session auth: \(err)"
                return nil
            }

            if let key = parseXMLValue(from: xml, tag: "Key") {
                cachedSessionKey = key
                sessionKeyTimestamp = Date()
                return key
            }
            lastError = "session: no Key in response"
            return nil
        } catch {
            lastError = "session: \(error.localizedDescription)"
            return nil
        }
    }

    private func performLookup(
        callsign: String,
        sessionKey: String
    ) async -> QRZCallbookResult? {
        guard var components = URLComponents(string: Self.qrzXMLURL) else {
            return nil
        }

        components.queryItems = [
            URLQueryItem(name: "s", value: sessionKey),
            URLQueryItem(name: "callsign", value: callsign),
        ]

        guard let url = components.url else {
            return nil
        }

        do {
            var request = URLRequest(url: url)
            request.setValue("CWSweep/1.0", forHTTPHeaderField: "User-Agent")

            let (data, response) = try await Self.lookupSession.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200,
                  let xml = String(data: data, encoding: .utf8)
            else {
                lastError = "lookup: bad HTTP response"
                return nil
            }

            if let err = parseXMLValue(from: xml, tag: "Error") {
                lastError = "lookup: \(err)"
                // Session may have expired — clear cache for next attempt
                if xml.contains("Session Timeout") || xml.contains("Invalid session") {
                    cachedSessionKey = nil
                    sessionKeyTimestamp = nil
                }
                return nil
            }

            return parseResult(from: xml, queriedCallsign: callsign)
        } catch {
            return nil
        }
    }

    private func parseResult(
        from xml: String,
        queriedCallsign: String
    ) -> QRZCallbookResult? {
        let qrzCall = parseXMLValue(from: xml, tag: "call")
        let canonicalCall = (qrzCall ?? queriedCallsign).uppercased()
        let isRedirected = canonicalCall != queriedCallsign.uppercased()

        let firstName = parseXMLValue(from: xml, tag: "fname")
        let lastName = parseXMLValue(from: xml, tag: "name")
        let nickname = parseXMLValue(from: xml, tag: "nickname")
        let fullName = combineNames(first: firstName, last: lastName)
        let grid = parseXMLValue(from: xml, tag: "grid")
        let city = parseXMLValue(from: xml, tag: "addr2")
        let state = parseXMLValue(from: xml, tag: "state")
        let country = parseXMLValue(from: xml, tag: "country")
        let licenseClass = parseXMLValue(from: xml, tag: "class")
        let previousCallsign = parseXMLValue(from: xml, tag: "p_call")
            ?? previousCallFromAliases(xml, callsign: canonicalCall)

        guard fullName != nil || grid != nil || city != nil else {
            return nil
        }

        return QRZCallbookResult(
            callsign: canonicalCall,
            name: fullName,
            firstName: firstName,
            nickname: nickname,
            grid: grid,
            city: city,
            state: state,
            country: country,
            licenseClass: licenseClass,
            previousCallsign: previousCallsign,
            callsignChangeNote: isRedirected
                ? "Looked up as \(queriedCallsign.uppercased())" : nil
        )
    }

    private func previousCallFromAliases(
        _ xml: String,
        callsign: String
    ) -> String? {
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

    private func combineNames(first: String?, last: String?) -> String? {
        let parts = [first, last]
            .compactMap { $0?.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    private func parseXMLValue(from xml: String, tag: String) -> String? {
        let openTag = "<\(tag)>"
        let closeTag = "</\(tag)>"

        guard let startRange = xml.range(of: openTag),
              let endRange = xml.range(
                  of: closeTag,
                  range: startRange.upperBound ..< xml.endIndex
              )
        else {
            return nil
        }

        let value = String(xml[startRange.upperBound ..< endRange.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return value.isEmpty ? nil : value
    }
}
