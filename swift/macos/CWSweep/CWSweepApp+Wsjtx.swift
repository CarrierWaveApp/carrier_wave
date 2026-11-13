import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - CWSweepApp + WSJT-X

extension CWSweepApp {
    /// Attach the shared `WsjtxIngestService` to this app's log and start the
    /// UDP listener if the user left it enabled (CAR-282). Inserted QSOs use
    /// the same follow-ups as the manual logger: mirror into the query engine
    /// and surface the row in the QSO log table.
    func configureWsjtxIngest() async {
        let env = SharedEnvironment.shared
        let service = env.wsjtxIngest
        service.configure(container: modelContainer)
        service.onQSOLogged = { qso in
            QueryFacade.mirrorQSO(qso)
            env.selectionState.logInsertedQSORow = QSOTableRow(from: qso)
        }
        await service.startIfEnabled()
    }
}
