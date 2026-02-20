import Foundation
import SwiftData

// MARK: - Club

@Model
nonisolated final class Club {
    // MARK: Lifecycle

    init(
        id: UUID = UUID(),
        name: String,
        poloNotesListURL: String,
        descriptionText: String? = nil,
        memberCallsignsData: Data = Data(),
        lastSyncedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.poloNotesListURL = poloNotesListURL
        self.descriptionText = descriptionText
        self.memberCallsignsData = memberCallsignsData
        self.lastSyncedAt = lastSyncedAt
    }

    // MARK: Internal

    var id = UUID()
    var name = ""
    var poloNotesListURL = ""
    var descriptionText: String?
    var memberCallsignsData = Data()
    var lastSyncedAt = Date()

    var memberCallsigns: [String] {
        get {
            (try? JSONDecoder().decode([String].self, from: memberCallsignsData)) ?? []
        }
        set {
            memberCallsignsData = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }

    var memberCount: Int {
        memberCallsigns.count
    }

    func isMember(callsign: String) -> Bool {
        memberCallsigns.contains { $0.uppercased() == callsign.uppercased() }
    }
}
