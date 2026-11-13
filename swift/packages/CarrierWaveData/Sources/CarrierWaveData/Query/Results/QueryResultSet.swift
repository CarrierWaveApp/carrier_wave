import Foundation

// MARK: - QueryValue

public enum QueryValue: Sendable, Equatable {
    case text(String)
    case integer(Int64)
    case double(Double)
    case blob(Data)
    case null
}

// MARK: - QueryColumn

public struct QueryColumn: Sendable, Equatable {
    // MARK: Lifecycle

    public init(name: String, declaredType: String?) {
        self.name = name
        self.declaredType = declaredType
    }

    // MARK: Public

    public let name: String
    public let declaredType: String?
}

// MARK: - QueryResultSet

public struct QueryResultSet: Sendable {
    // MARK: Lifecycle

    public init(columns: [QueryColumn], rows: [[QueryValue]], rowCount: Int, truncated: Bool) {
        self.columns = columns
        self.rows = rows
        self.rowCount = rowCount
        self.truncated = truncated
    }

    // MARK: Public

    public let columns: [QueryColumn]
    public let rows: [[QueryValue]]
    public let rowCount: Int
    public let truncated: Bool
}
