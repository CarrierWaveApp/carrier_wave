import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - LogbookIDBridge

/// Bridges a `QSORowSnapshot.id` (lowercase UUID string, the cw-store convention)
/// back to the live SwiftData `QSO`. The Logbook renders snapshots, but writes
/// (delete, group-into-session) and the detail screen still operate on `QSO`,
/// which remains the system of record.
enum LogbookIDBridge {
    /// Fetch the live QSOs for a set of snapshot ids. Unparseable ids are dropped.
    static func fetchQSOs(ids: Set<String>, in context: ModelContext) -> [QSO] {
        let uuids = Set(ids.compactMap(UUID.init(uuidString:)))
        guard !uuids.isEmpty else {
            return []
        }
        var descriptor = FetchDescriptor<QSO>(
            predicate: #Predicate { uuids.contains($0.id) }
        )
        descriptor.fetchLimit = uuids.count
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Fetch a single live QSO for a snapshot id, or `nil` if absent/unparseable.
    static func fetchQSO(id: String, in context: ModelContext) -> QSO? {
        guard let uuid = UUID(uuidString: id) else {
            return nil
        }
        var descriptor = FetchDescriptor<QSO>(
            predicate: #Predicate { $0.id == uuid }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
}

// MARK: - QSODetailLoader

/// Resolves a snapshot id to the live `QSO` and presents `QSODetailView`. Used as
/// the Logbook row's navigation destination so the whole list need not materialise
/// `QSO` objects — only the tapped row does.
struct QSODetailLoader: View {
    // MARK: Internal

    let snapshotID: String
    let serviceConfig: ServiceConfiguration

    var body: some View {
        Group {
            if let qso {
                QSODetailView(qso: qso, serviceConfig: serviceConfig)
            } else if didLoad {
                ContentUnavailableView(
                    "QSO Unavailable",
                    systemImage: "exclamationmark.triangle",
                    description: Text("This contact could not be found.")
                )
            } else {
                ProgressView()
            }
        }
        .task {
            qso = LogbookIDBridge.fetchQSO(id: snapshotID, in: modelContext)
            didLoad = true
        }
    }

    // MARK: Private

    @Environment(\.modelContext) private var modelContext
    @State private var qso: QSO?
    @State private var didLoad = false
}
