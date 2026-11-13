import Foundation

public enum QSOMapper {
    public static func slimRow(from qso: QSO) -> QSORow? {
        if QSOMode.isMetadata(qso.mode) {
            return nil
        }
        return QSORow(
            id: qso.id.uuidString,
            callsign: qso.callsign,
            band: qso.band,
            mode: qso.mode,
            frequency: qso.frequency,
            timestamp: qso.timestamp,
            myCallsign: qso.myCallsign,
            theirGrid: qso.theirGrid,
            myGrid: qso.myGrid,
            parkRef: qso.parkReference,
            theirParkRef: qso.theirParkReference,
            dxcc: qso.dxcc,
            modifiedAt: qso.modifiedAt,
            isHidden: qso.isHidden,
            isActivityLog: qso.isActivityLogQSO
        )
    }
}
