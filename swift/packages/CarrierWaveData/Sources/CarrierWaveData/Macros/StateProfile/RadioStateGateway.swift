import Foundation

// MARK: - RadioStateTransport

/// Raw request/response seam for radios where the codec layer (not the radio
/// session) owns parsing — a test mock, or a future raw-CAT path. `query`
/// sends a CAT command and returns the radio's reply line; `send` issues a
/// fire-and-forget SET.
public protocol RadioStateTransport: Sendable {
    func query(_ command: String) async throws -> String
    func send(_ command: String) async throws
}

// MARK: - RadioStateGateway

/// What the planner needs from a radio: read a setting's current canonical
/// value, and drive a setting to a canonical value. This seam lets the same
/// plan/diff/verify loop run against a mock, a raw-CAT transport, or a live
/// `RadioSession` (see `RadioSessionStateGateway`).
public protocol RadioStateGateway: Sendable {
    /// Current canonical value for `key`, or nil if unreadable / unknown.
    func currentValue(forKey key: String) async throws -> String?
    /// Drive `key` to `value`. Returns false if the write failed or the
    /// setting isn't writable on this radio over its current link.
    func apply(key: String, value: String) async throws -> Bool
}

// MARK: - CatalogStateGateway

/// Gateway backed by `RadioStateField` codecs over a raw `RadioStateTransport`.
/// Reads issue the field's query and parse the response; writes encode the
/// field's SET command. Used by tests and any future raw-CAT path where the
/// app — not the radio session — owns response parsing.
public struct CatalogStateGateway: RadioStateGateway {
    // MARK: Lifecycle

    public init(transport: RadioStateTransport, fields: [RadioStateField]) {
        self.transport = transport
        fieldsByKey = Dictionary(uniqueKeysWithValues: fields.map { ($0.key, $0) })
    }

    // MARK: Public

    public func currentValue(forKey key: String) async throws -> String? {
        guard let field = fieldsByKey[key], field.readable else {
            return nil
        }
        let response = try await transport.query(field.readCommand)
        return field.parse(response: response)
    }

    public func apply(key: String, value: String) async throws -> Bool {
        guard let field = fieldsByKey[key], let command = field.setCommand(for: value) else {
            return false
        }
        try await transport.send(command)
        return true
    }

    // MARK: Private

    private let transport: RadioStateTransport
    private let fieldsByKey: [String: RadioStateField]
}
