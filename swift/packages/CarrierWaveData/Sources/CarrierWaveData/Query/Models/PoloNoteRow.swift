import Foundation
import GRDB

public struct PoloNoteRow: Codable, Equatable, Sendable, FetchableRecord, PersistableRecord {
    // MARK: Lifecycle

    public init(callsign: String, tag: String?, body: String?) {
        self.callsign = callsign
        self.tag = tag
        self.body = body
    }

    // MARK: Public

    public static let databaseTableName = "polo_notes"

    public var callsign: String
    public var tag: String?
    public var body: String?
}
