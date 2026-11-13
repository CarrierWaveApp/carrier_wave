import CarrierWaveCwFfi
import CarrierWaveData
import SwiftData
import UIKit

// MARK: - SpotQueryQsoMirror

/// Feeds the spot engine's in-memory `qsos` table from SwiftData so the
/// query editor's starter queries (worked-before lookups, DXCC status,
/// never-seen callsigns) have log data to join against.
///
/// One-shot per launch, capped and batched per the iOS performance rules:
/// newest `maxRows` QSOs, fetched 1K at a time on a background context,
/// pushed through `mirrorQsos` off the main actor. Metadata pseudo-modes
/// (WEATHER / SOLAR / NOTE) are excluded per the shared rule.
@MainActor
@Observable
final class SpotQueryQsoMirror {
    // MARK: Internal

    static let shared = SpotQueryQsoMirror()

    /// Error from the most recent mirror attempt, for display in the
    /// editor footer. nil = mirrored fine (or not attempted yet).
    private(set) var lastError: String?

    /// Mirror the newest QSOs into the engine's `qsos` table. Safe to
    /// call repeatedly — subsequent calls while mirrored/running no-op.
    func mirrorIfNeeded(container: ModelContainer) {
        guard !hasMirrored, !isMirroring else {
            return
        }
        guard let engine = SpotEngineProvider.shared.engineIfBuilt else {
            return
        }
        isMirroring = true
        Task.detached(priority: .utility) { [maxRows = self.maxRows, batchSize = self.batchSize] in
            let outcome = Self.mirror(
                engine: engine,
                container: container,
                maxRows: maxRows,
                batchSize: batchSize
            )
            await MainActor.run {
                let mirror = SpotQueryQsoMirror.shared
                mirror.isMirroring = false
                switch outcome {
                case .success:
                    mirror.hasMirrored = true
                    mirror.lastError = nil
                case let .failure(message):
                    // Delegation failed — leave `hasMirrored` false so a
                    // later visit retries, and surface the reason.
                    mirror.lastError = message
                }
            }
        }
    }

    // MARK: Private

    private enum Outcome {
        case success
        case failure(String)
    }

    private let maxRows = 5_000
    private let batchSize = 1_000

    private var hasMirrored = false
    private var isMirroring = false

    nonisolated private static func mirror(
        engine: SpotEngineApi,
        container: ModelContainer,
        maxRows: Int,
        batchSize: Int
    ) -> Outcome {
        var offset = 0
        while offset < maxRows {
            // Fresh context per batch keeps peak memory bounded.
            let context = ModelContext(container)
            var descriptor = FetchDescriptor<QSO>(
                sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
            )
            descriptor.fetchLimit = batchSize
            descriptor.fetchOffset = offset
            let batch: [QSO]
            do {
                batch = try context.fetch(descriptor)
            } catch {
                // Surface the fetch failure so the mirror retries next run
                // instead of reporting an empty mirror as success.
                return .failure(error.localizedDescription)
            }
            guard !batch.isEmpty else {
                break
            }
            let rows = batch
                .filter { !QSOMode.isMetadata($0.mode) }
                .map(Self.scopeRow(from:))
            if !rows.isEmpty {
                do {
                    try engine.mirrorQsos(rows: rows)
                } catch let SpotQueryError.Query(reason, _, _) {
                    return .failure(reason)
                } catch {
                    return .failure(error.localizedDescription)
                }
            }
            if batch.count < batchSize {
                break
            }
            offset += batchSize
        }
        return .success
    }

    nonisolated private static func scopeRow(from qso: QSO) -> FfiScopeQso {
        FfiScopeQso(
            // Rust-side ids are lowercase everywhere ([[cwstore-lowercase-ids]]).
            id: qso.id.uuidString.lowercased(),
            callsign: qso.callsign,
            band: qso.band,
            mode: qso.mode,
            frequency: qso.frequency,
            timestamp: qso.timestamp.timeIntervalSince1970,
            myCallsign: qso.myCallsign,
            theirGrid: qso.theirGrid,
            myGrid: qso.myGrid,
            parkRef: qso.parkReference,
            theirParkRef: qso.theirParkReference,
            dxcc: qso.dxcc.map(Int64.init),
            modifiedAt: qso.modifiedAt?.timeIntervalSince1970,
            isHidden: qso.isHidden,
            isActivityLog: qso.isActivityLogQSO
        )
    }
}
