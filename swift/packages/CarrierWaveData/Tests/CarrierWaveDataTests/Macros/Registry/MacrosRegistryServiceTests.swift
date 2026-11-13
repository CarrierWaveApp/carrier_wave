import CarrierWaveData
import Foundation
import SwiftData
import Testing

// MARK: - MacrosRegistryServiceTests

@MainActor
@Suite(.serialized)
struct MacrosRegistryServiceTests {
    // MARK: Internal

    @Test func pollWithNoInstalledMacrosShortCircuits() async throws {
        let container = try makeContainer()
        ServiceStubURLProtocol.handler = { _ in
            Issue.record("network shouldn't be hit when nothing is installed")
            return (
                HTTPURLResponse(
                    url: URL(string: "https://t.example")!,
                    statusCode: 204,
                    httpVersion: nil,
                    headerFields: nil
                )!,
                Data()
            )
        }
        let service = MacrosRegistryService(
            client: makeClient(),
            container: container,
            tombstoneStore: InMemoryTombstoneStore()
        )
        let snapshot = try await service.pollIfStale()
        #expect(snapshot.pendingUpdates.isEmpty)
    }

    @Test func surfacesNewerServerVersion() async throws {
        let container = try makeContainer()
        try insertInstalled(container: container, slug: "tune-pota", version: 3)
        ServiceStubURLProtocol.handler = { request in
            switch request.url?.path {
            case "/v1/macros/versions":
                return Self.json(#"{"tune-pota":{"version":7,"format":2}}"#)
            case "/v1/macros/tombstones":
                return Self.json(#"{"entries":[]}"#)
            default:
                Issue.record("unexpected path: \(request.url?.path ?? "<nil>")")
                return Self.json("{}")
            }
        }
        let service = MacrosRegistryService(
            client: makeClient(),
            container: container,
            tombstoneStore: InMemoryTombstoneStore()
        )
        let snapshot = try await service.pollIfStale()
        #expect(snapshot.pendingUpdates["tune-pota"]?.version == 7)
    }

    @Test func skipsUpdatesWhenVersionMatches() async throws {
        let container = try makeContainer()
        try insertInstalled(container: container, slug: "tune-pota", version: 5)
        ServiceStubURLProtocol.handler = { request in
            switch request.url?.path {
            case "/v1/macros/versions":
                Self.json(#"{"tune-pota":{"version":5,"format":2}}"#)
            case "/v1/macros/tombstones":
                Self.json(#"{"entries":[]}"#)
            default:
                Self.json("{}")
            }
        }
        let service = MacrosRegistryService(
            client: makeClient(),
            container: container,
            tombstoneStore: InMemoryTombstoneStore()
        )
        let snapshot = try await service.pollIfStale()
        #expect(snapshot.pendingUpdates.isEmpty)
    }

    @Test func appliesTombstonesToInstalledMacro() async throws {
        let container = try makeContainer()
        try insertInstalled(container: container, slug: "evil-macro", version: 1)
        ServiceStubURLProtocol.handler = { request in
            switch request.url?.path {
            case "/v1/macros/versions":
                Self.json(#"{"evil-macro":{"version":1,"format":2}}"#)
            case "/v1/macros/tombstones":
                Self.json("""
                {"entries":[{"slug":"evil-macro","reason":"admin_removed",\
                "tombstoned_at":"2026-05-10T08:00:00Z"}]}
                """)
            default:
                Self.json("{}")
            }
        }
        let tombstones = InMemoryTombstoneStore()
        let service = MacrosRegistryService(
            client: makeClient(),
            container: container,
            tombstoneStore: tombstones
        )
        _ = try await service.pollIfStale()

        let macros = try await MainActor.run {
            try container.mainContext.fetch(FetchDescriptor<RadioMacro>())
        }
        let target = try #require(macros.first(where: { $0.registry?.slug == "evil-macro" }))
        #expect(target.tombstoned == true)
        #expect(target.tombstoneReason == "admin_removed")
        #expect(tombstones.lastSeen != nil)
    }

    @Test func respectsDebounceWindow() async throws {
        let container = try makeContainer()
        try insertInstalled(container: container, slug: "tune-pota", version: 1)
        var calls = 0
        ServiceStubURLProtocol.handler = { request in
            calls += 1
            switch request.url?.path {
            case "/v1/macros/versions":
                return Self.json(#"{"tune-pota":{"version":1,"format":2}}"#)
            case "/v1/macros/tombstones":
                return Self.json(#"{"entries":[]}"#)
            default:
                return Self.json("{}")
            }
        }
        let service = MacrosRegistryService(
            client: makeClient(),
            container: container,
            tombstoneStore: InMemoryTombstoneStore(),
            pollInterval: 30 * 60
        )
        _ = try await service.pollIfStale()
        let firstCalls = calls
        _ = try await service.pollIfStale()
        #expect(calls == firstCalls)

        await service.invalidateDebounce()
        _ = try await service.pollIfStale()
        #expect(calls > firstCalls)
    }

    // MARK: Private

    nonisolated private static func json(_ raw: String) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: URL(string: "https://t.example")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        return (response, Data(raw.utf8))
    }

    nonisolated private static func stubbedSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ServiceStubURLProtocol.self]
        return URLSession(configuration: config)
    }

    private func makeClient() -> MacrosRegistryClient {
        MacrosRegistryClient(
            baseURL: URL(string: "https://t.example")!,
            session: Self.stubbedSession()
        )
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([RadioMacro.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func insertInstalled(
        container: ModelContainer,
        slug: String,
        version: Int
    ) throws {
        let context = container.mainContext
        let macro = RadioMacro(name: "Tune", appliesToCSV: "civ")
        macro.registry = RegistryRef(slug: slug, registryVersion: version, publishedAt: Date())
        context.insert(macro)
        try context.save()
    }
}

// MARK: - ServiceStubURLProtocol

/// Separate URLProtocol subclass for `MacrosRegistryServiceTests` so its
/// per-test handler doesn't collide with the client suite's
/// `StubURLProtocol` when the package test runner schedules both suites
/// in parallel.
final class ServiceStubURLProtocol: URLProtocol, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) -> (HTTPURLResponse, Data)

    nonisolated(unsafe) static var handler: Handler?

    override static func canInit(with _: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = ServiceStubURLProtocol.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        let (response, data) = handler(request)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
