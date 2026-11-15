import CarrierWaveData
import Foundation

extension SessionsView {
    func findSession(for activation: POTAActivation) -> LoggingSession? {
        guard let sessionId = activation.qsos.compactMap(\.loggingSessionId).first else {
            return nil
        }
        return sessions.first { $0.id == sessionId }
    }

    func engineFor(_ sessionId: UUID) -> RecordingPlaybackEngine {
        engines[sessionId] ?? {
            let eng = RecordingPlaybackEngine(); engines[sessionId] = eng; return eng
        }()
    }
}
