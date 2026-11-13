import Foundation

// MARK: - RegistryEndpoint

/// Server endpoints exposed by the macros registry (CAR-271 server work).
/// All paths are appended to the configured `baseURL/v1`.
enum RegistryEndpoint {
    case list(maxFormat: Int, tag: String?, appliesTo: String?, search: String?, limit: Int, offset: Int)
    case get(slug: String)
    case versions(slugs: [String])
    case tombstones(since: Date?)
    case runEvent(slug: String)

    // MARK: Internal

    var method: String {
        switch self {
        case .runEvent: "POST"
        default: "GET"
        }
    }

    var requiresAuth: Bool {
        switch self {
        case .runEvent: true
        default: false
        }
    }

    func url(relativeTo base: URL) -> URL? {
        var components = URLComponents()
        components.path = path
        components.queryItems = queryItems
        return components.url(relativeTo: base)
    }

    // MARK: Private

    private var path: String {
        switch self {
        case .list: "/v1/macros"
        case let .get(slug): "/v1/macros/\(slug)"
        case .versions: "/v1/macros/versions"
        case .tombstones: "/v1/macros/tombstones"
        case let .runEvent(slug): "/v1/macros/\(slug)/run-event"
        }
    }

    private var queryItems: [URLQueryItem]? {
        switch self {
        case let .list(maxFormat, tag, appliesTo, search, limit, offset):
            var items: [URLQueryItem] = [
                .init(name: "max_format", value: String(maxFormat)),
                .init(name: "limit", value: String(limit)),
                .init(name: "offset", value: String(offset)),
            ]
            if let tag, !tag.isEmpty {
                items.append(.init(name: "tag", value: tag))
            }
            if let appliesTo, !appliesTo.isEmpty {
                items.append(.init(name: "applies_to", value: appliesTo))
            }
            if let search, !search.isEmpty {
                items.append(.init(name: "search", value: search))
            }
            return items
        case let .versions(slugs):
            return [.init(name: "slugs", value: slugs.joined(separator: ","))]
        case let .tombstones(since):
            guard let since else {
                return nil
            }
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return [.init(name: "since", value: iso.string(from: since))]
        case .get,
             .runEvent:
            return nil
        }
    }
}
