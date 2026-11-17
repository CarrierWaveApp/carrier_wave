import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - DashboardView K-Index Repair

extension DashboardView {
    private static let kIndexRepairKey = "kIndexRepairCompleted"

    /// One-time repair: clear corrupted K-index data (always 0) from before
    /// the HamQSL XML whitespace parsing fix (Feb 14, 2026).
    func repairKIndexIfNeeded() async {
        guard !UserDefaults.standard.bool(forKey: Self.kIndexRepairKey) else {
            return
        }

        let service = KIndexRepairService(container: modelContext.container)
        do {
            let result = try await service.repair()
            if result.sessionsRepaired > 0 || result.metadataRepaired > 0 {
                let msg = "K-index repair: sessions=\(result.sessionsRepaired)"
                    + ", metadata=\(result.metadataRepaired)"
                print(msg)
            }
            UserDefaults.standard.set(true, forKey: Self.kIndexRepairKey)
        } catch {
            print("K-index repair failed: \(error)")
        }
    }
}
