import CarrierWaveData
import Foundation
import Testing

// MARK: - MacrosRegistryClientTests

@MainActor
@Suite(.serialized)
struct MacrosRegistryClientTests {
    // MARK: Internal

    @Test func listSerializesQueryAndDecodesEntries() async throws {
        StubURLProtocol.handler = { request in
            #expect(request.url?.path == "/v1/macros")
            let query = request.url?.query ?? ""
            #expect(query.contains("max_format=2"))
            #expect(query.contains("limit=20"))
            #expect(query.contains("offset=10"))
            #expect(query.contains("tag=cw"))
            #expect(query.contains("applies_to=civ"))
            #expect(query.contains("search=tune"))
            return Self.successJSON("""
            {"entries":[{"slug":"tune-1","name":"Tune","icon":null,"description":null,\
            "tags":["cw"],"applies_to":["civ"],"format":2,"version":3,\
            "author_callsign":"W6JY","published_at":"2026-05-01T12:00:00Z"}]}
            """)
        }

        let client = makeClient()
        let response = try await client.list(
            maxFormat: 2,
            tag: "cw",
            appliesTo: "civ",
            search: "tune",
            limit: 20,
            offset: 10
        )
        #expect(response.entries.count == 1)
        #expect(response.entries[0].slug == "tune-1")
        #expect(response.entries[0].version == 3)
        #expect(response.entries[0].authorCallsign == "W6JY")
    }

    @Test func getReturnsServerShapedDocument() async throws {
        StubURLProtocol.handler = { request in
            #expect(request.url?.path == "/v1/macros/tune-pota")
            return Self.successJSON("""
            {"slug":"tune-pota","spec":{"name":"Tune POTA","icon":null,"description":null,\
            "tags":[],"applies_to":["civ"],\
            "capabilities":{"transmits":true,"changesFrequency":true,\
            "changesMode":false,"changesPower":false,"usesRawBytes":false},\
            "args":[],"steps":[]},"format":2,"version":5,\
            "published_at":"2026-05-01T12:00:00Z","updated_at":"2026-05-02T12:00:00Z",\
            "author_callsign":"W6JY"}
            """)
        }

        let client = makeClient()
        let doc = try await client.get(slug: "tune-pota")
        #expect(doc.slug == "tune-pota")
        #expect(doc.version == 5)
        #expect(doc.spec.capabilities.transmits == true)

        let adapted = doc.toRadioMacroDocument()
        #expect(adapted.macro.name == "Tune POTA")
        #expect(adapted.macro.registry?.slug == "tune-pota")
        #expect(adapted.macro.registry?.registryVersion == 5)
        #expect(adapted.macro.appliesTo == [.civ])
    }

    @Test func versionsReturnsMap() async throws {
        StubURLProtocol.handler = { request in
            #expect(request.url?.path == "/v1/macros/versions")
            #expect(request.url?.query?.contains("slugs=a,b") == true)
            return Self.successJSON(#"{"a":{"version":2,"format":2},"b":{"version":7,"format":2}}"#)
        }

        let client = makeClient()
        let versions = try await client.versions(slugs: ["a", "b"])
        #expect(versions.count == 2)
        #expect(versions["a"] == RegistryVersionInfo(version: 2, format: 2))
        #expect(versions["b"] == RegistryVersionInfo(version: 7, format: 2))
    }

    @Test func versionsShortCircuitsEmptyInput() async throws {
        StubURLProtocol.handler = { _ in
            Issue.record("network shouldn't be hit for empty slugs")
            return Self.successJSON("{}")
        }
        let client = makeClient()
        let versions = try await client.versions(slugs: [])
        #expect(versions.isEmpty)
    }

    @Test func tombstonesIncludesSinceQuery() async throws {
        let since = Date(timeIntervalSince1970: 1_700_000_000)
        StubURLProtocol.handler = { request in
            let query = request.url?.query ?? ""
            #expect(query.contains("since="))
            return Self.successJSON("""
            {"entries":[{"slug":"banned-1","reason":"admin_removed",\
            "tombstoned_at":"2026-05-10T08:00:00Z"}]}
            """)
        }

        let client = makeClient()
        let response = try await client.tombstones(since: since)
        #expect(response.entries.count == 1)
        #expect(response.entries[0].slug == "banned-1")
        #expect(response.entries[0].reason == "admin_removed")
    }

    @Test func runEventRequiresAuth() async throws {
        StubURLProtocol.handler = { _ in
            Issue.record("network shouldn't be hit when token missing")
            return Self.successJSON("{}")
        }
        let client = try MacrosRegistryClient(
            baseURL: #require(URL(string: "https://test.example")),
            session: Self.stubbedSession(),
            authTokenProvider: { nil }
        )
        do {
            try await client.reportRunEvent(
                slug: "tune-pota",
                body: RegistryRunEventBody(success: true, failedStepIndex: nil, errorCode: nil)
            )
            Issue.record("expected notAuthenticated")
        } catch MacrosRegistryClientError.notAuthenticated {
            // Expected
        }
    }

    @Test func runEventSendsAuthHeader() async throws {
        StubURLProtocol.handler = { request in
            #expect(request.httpMethod == "POST")
            #expect(request.url?.path == "/v1/macros/tune-pota/run-event")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer abc-123")
            return (
                HTTPURLResponse(url: request.url!, statusCode: 204, httpVersion: nil, headerFields: nil)!,
                Data()
            )
        }
        let client = try MacrosRegistryClient(
            baseURL: #require(URL(string: "https://test.example")),
            session: Self.stubbedSession(),
            authTokenProvider: { "abc-123" }
        )
        try await client.reportRunEvent(
            slug: "tune-pota",
            body: RegistryRunEventBody(success: false, failedStepIndex: 2, errorCode: "ptt-stuck")
        )
    }

    @Test func serverErrorSurfacesStatus() async throws {
        StubURLProtocol.handler = { request in
            (
                HTTPURLResponse(url: request.url!, statusCode: 503, httpVersion: nil, headerFields: nil)!,
                Data("nope".utf8)
            )
        }
        let client = makeClient()
        do {
            _ = try await client.list()
            Issue.record("expected server error")
        } catch let MacrosRegistryClientError.server(status, body) {
            #expect(status == 503)
            #expect(body == "nope")
        }
    }

    // MARK: Private

    nonisolated private static func successJSON(_ raw: String) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: URL(string: "https://test.example")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        return (response, Data(raw.utf8))
    }

    nonisolated private static func stubbedSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }

    private func makeClient() -> MacrosRegistryClient {
        MacrosRegistryClient(
            baseURL: URL(string: "https://test.example")!,
            session: Self.stubbedSession()
        )
    }
}

// MARK: - StubURLProtocol

final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) -> (HTTPURLResponse, Data)

    nonisolated(unsafe) static var handler: Handler?

    override static func canInit(with _: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = StubURLProtocol.handler else {
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
