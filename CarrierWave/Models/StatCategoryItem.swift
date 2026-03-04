import CarrierWaveData
import Foundation

struct StatCategoryItem: Identifiable {
    // MARK: Lifecycle

    init(
        identifier: String,
        description: String,
        qsos: [QSO],
        date: Date? = nil,
        parkReference: String? = nil
    ) {
        id = identifier
        self.identifier = identifier
        self.description = description
        count = qsos.count
        self.qsos = qsos.sorted { $0.timestamp > $1.timestamp }
        self.date = date
        self.parkReference = parkReference
    }

    // MARK: Internal

    let id: String
    let identifier: String
    let description: String
    let count: Int
    let qsos: [QSO]
    /// Optional date for date-based sorting (e.g., park activations)
    let date: Date?
    /// Park reference for looking up park name (e.g., "K-1234")
    let parkReference: String?
}
