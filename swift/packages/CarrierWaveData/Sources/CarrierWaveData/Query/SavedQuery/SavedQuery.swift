import Foundation

// MARK: - SavedQuery

public struct SavedQuery: Codable, Equatable, Sendable, Identifiable {
    // MARK: Lifecycle

    public init(
        id: UUID = UUID(),
        name: String,
        description: String = "",
        sql: String,
        schemaVersion: Int = QuerySchemaVersion.current,
        createdAt: Date = Date(),
        columnHints: [String: String]? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.sql = sql
        self.schemaVersion = schemaVersion
        self.createdAt = createdAt
        self.columnHints = columnHints
    }

    // MARK: Public

    public var id: UUID
    public var name: String
    public var description: String
    public var sql: String
    public var schemaVersion: Int
    public var createdAt: Date
    public var columnHints: [String: String]?
}

// MARK: - SavedQueryCoder

public enum SavedQueryCoder {
    public static func encode(_ query: SavedQuery) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(query)
    }

    public static func decode(_ data: Data) throws -> SavedQuery {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(SavedQuery.self, from: data)
    }
}
