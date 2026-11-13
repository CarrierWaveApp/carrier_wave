import Foundation

public enum SavedQueryURL {
    public enum URLError: Error, Equatable {
        case wrongScheme
        case wrongHost
        case missingData
        case decodeFailed
    }

    public static let scheme = "cwquery"
    public static let importHost = "import"

    public static func encode(_ query: SavedQuery) throws -> URL {
        let json = try SavedQueryCoder.encode(query)
        let base64 = json.base64EncodedString()
        let encoded = base64.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? base64
        guard let url = URL(string: "\(scheme)://\(importHost)?data=\(encoded)") else {
            throw URLError.decodeFailed
        }
        return url
    }

    public static func decode(_ url: URL) throws -> SavedQuery {
        guard url.scheme == scheme else {
            throw URLError.wrongScheme
        }
        guard url.host == importHost else {
            throw URLError.wrongHost
        }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        guard let dataParam = components?.queryItems?.first(where: { $0.name == "data" })?.value else {
            throw URLError.missingData
        }
        guard let bytes = Data(base64Encoded: dataParam) else {
            throw URLError.decodeFailed
        }
        return try SavedQueryCoder.decode(bytes)
    }
}
