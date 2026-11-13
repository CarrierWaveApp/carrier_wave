import CarrierWaveCore
import Foundation

// MARK: - FfiQso minimal helper

extension FfiQso {
    // swiftlint:disable:next function_body_length
    static func minimal(id: String) -> FfiQso {
        FfiQso(
            id: id,
            callsign: "W1AW",
            band: nil,
            mode: nil,
            freqKhz: nil,
            qsoDate: 1_000,
            myGrid: nil,
            theirGrid: nil,
            rstSent: nil,
            rstRcvd: nil,
            myCallsign: nil,
            park: nil,
            theirPark: nil,
            notes: nil,
            notesUserAuthored: false,
            spotCommentsData: nil,
            callsignChangeNote: nil,
            originalCallsign: nil,
            importSourceRawValue: "logger",
            importedAt: 1_000,
            modifiedAt: nil,
            rawAdif: nil,
            name: nil,
            qth: nil,
            state: nil,
            country: nil,
            power: nil,
            myRig: nil,
            stationProfileName: nil,
            sotaRef: nil,
            wwffRef: nil,
            aoaCode: nil,
            qrzLogId: nil,
            qrzConfirmed: false,
            lotwConfirmedDate: nil,
            lotwConfirmed: false,
            dxcc: nil,
            theirLicenseClass: nil,
            contestName: nil,
            contestSerialSent: nil,
            contestSerialReceived: nil,
            contestExchangeSent: nil,
            contestExchangeReceived: nil,
            isHidden: false,
            isActivityLogQso: false,
            stationCallsign: nil,
            loggingSessionId: nil,
            dirty: true,
            satName: nil,
            propMode: nil,
            presence: []
        )
    }
}

// MARK: - Entry point

let args = CommandLine.arguments
guard args.count == 4 else {
    fputs("usage: LogDurabilityCrasher <db> <key> <id>\n", stderr)
    exit(2)
}

let dbPath = args[1]
let key = args[2]
let qsoId = args[3]

do {
    let store = try FieldStore.open(path: dbPath, key: key)
    try store.upsertQso(qso: FfiQso.minimal(id: qsoId))
} catch {
    fputs("LogDurabilityCrasher: \(error)\n", stderr)
    exit(1)
}

print("ACK \(qsoId)")
fflush(stdout)
abort()
