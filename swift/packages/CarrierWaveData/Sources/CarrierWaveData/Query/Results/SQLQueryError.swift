import Foundation

public struct SQLQueryError: Error, Sendable, Equatable {
    // MARK: Lifecycle

    public init(message: String, sql: String, errorOffset: Int?) {
        self.message = message
        self.sql = sql
        self.errorOffset = errorOffset
    }

    // MARK: Public

    public let message: String
    public let sql: String
    public let errorOffset: Int?
}
