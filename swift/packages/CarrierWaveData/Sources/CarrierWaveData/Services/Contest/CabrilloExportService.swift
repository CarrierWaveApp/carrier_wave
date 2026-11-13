import CarrierWaveCore
import Foundation

// MARK: - CabrilloExportService

/// Cabrillo 3.0 log generator driven by a contest definition's `cabrillo`
/// block. Facade over `cw_domain::contest::cabrillo` — output is
/// byte-identical to the original Swift generator (see
/// `CabrilloGoldenTests`).
public struct CabrilloExportService: Sendable {
    // MARK: Lifecycle

    public init() {}

    // MARK: Public

    /// Context needed to produce Cabrillo header values that are not
    /// directly available from the contest definition or the session.
    public struct Context: Sendable {
        // MARK: Lifecycle

        public init(
            categoryID: String?,
            overlayCategoryID: String? = nil,
            powerClass: String? = nil,
            assisted: Bool? = nil,
            location: String? = nil,
            operators: [String] = [],
            clubName: String? = nil,
            email: String? = nil
        ) {
            self.categoryID = categoryID
            self.overlayCategoryID = overlayCategoryID
            self.powerClass = powerClass
            self.assisted = assisted
            self.location = location
            self.operators = operators
            self.clubName = clubName
            self.email = email
        }

        // MARK: Public

        public var categoryID: String?
        public var overlayCategoryID: String?
        public var powerClass: String?
        public var assisted: Bool?
        public var location: String?
        public var operators: [String]
        public var clubName: String?
        public var email: String?
    }

    /// Generate Cabrillo 3.0 log text from a contest session.
    public func generate(
        session: LoggingSession,
        qsos: [QSO],
        definition: ContestDefinition,
        score: ContestScoreSnapshot,
        context: Context
    ) -> String {
        let ffiSession = FfiCabrilloSession(
            myCallsign: session.myCallsign,
            contestOperator: session.contestOperator,
            contestBands: session.contestBands,
            contestPower: session.contestPower
        )
        let ffiQsos = qsos.map { qso in
            FfiCabrilloQso(
                callsign: qso.callsign,
                frequencyMhz: qso.frequency,
                mode: qso.mode,
                timestamp: Int64(qso.timestamp.timeIntervalSince1970),
                rstSent: qso.rstSent,
                rstReceived: qso.rstReceived,
                contestExchangeSent: qso.contestExchangeSent,
                contestExchangeReceived: qso.contestExchangeReceived,
                isContestQso: qso.isContestQSO,
                isHidden: qso.isHidden
            )
        }
        let ffiContext = FfiCabrilloContext(
            categoryId: context.categoryID,
            overlayCategoryId: context.overlayCategoryID,
            powerClass: context.powerClass,
            assisted: context.assisted,
            location: context.location,
            operators: context.operators,
            clubName: context.clubName,
            email: context.email
        )
        return (try? contestGenerateCabrillo(
            session: ffiSession,
            qsos: ffiQsos,
            definitionJson: definition.rawJson,
            score: score.ffi,
            context: ffiContext
        )) ?? ""
    }
}
