// FullADIFExportActor+AppContestFields.swift
//
// App-specific and contest ADIF field builders, plus shared field formatter.

import Foundation

extension FullADIFExportActor {
    func appendAppFields(
        to fields: inout [String],
        snapshot: FullExportQSOSnapshot
    ) {
        fields.append(formatField(
            "\(config.appFieldPrefix)_IMPORT_SOURCE",
            snapshot.importSourceRawValue
        ))

        if snapshot.isActivityLogQSO {
            fields.append(formatField(
                "\(config.appFieldPrefix)_ACTIVITY_LOG_QSO",
                "Y"
            ))
        }

        if let aoaCode = snapshot.aoaCode, !aoaCode.isEmpty {
            fields.append(formatField(
                "\(config.appFieldPrefix)_AOA_CODE", aoaCode
            ))
        }

        if let profile = snapshot.stationProfileName, !profile.isEmpty {
            fields.append(formatField(
                "\(config.appFieldPrefix)_STATION_PROFILE",
                profile
            ))
        }

        if let sessionId = snapshot.loggingSessionId {
            fields.append(formatField(
                "\(config.appFieldPrefix)_LOGGING_SESSION_ID",
                sessionId.uuidString
            ))
        }
    }

    func appendContestFields(
        to fields: inout [String],
        snapshot: FullExportQSOSnapshot
    ) {
        if let contestId = snapshot.contestName, !contestId.isEmpty {
            fields.append(formatField("CONTEST_ID", contestId))
        }
        if let stx = snapshot.contestSerialSent {
            fields.append(formatField("STX", String(stx)))
        }
        if let srx = snapshot.contestSerialReceived {
            fields.append(formatField("SRX", String(srx)))
        }
        if let stxStr = snapshot.contestExchangeSent,
           !stxStr.isEmpty
        {
            fields.append(formatField("STX_STRING", stxStr))
        }
        if let srxStr = snapshot.contestExchangeReceived,
           !srxStr.isEmpty
        {
            fields.append(formatField("SRX_STRING", srxStr))
        }
    }

    /// Format a single ADIF field: <NAME:length>value
    func formatField(_ name: String, _ value: String) -> String {
        "<\(name.uppercased()):\(value.utf8.count)>\(value)"
    }
}
