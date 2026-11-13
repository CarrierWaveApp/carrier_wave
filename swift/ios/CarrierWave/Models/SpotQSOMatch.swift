import CarrierWaveData

/// Cross-references session QSOs and spots for display linking.
/// Matches on callsign (case-insensitive) + band within a session.
///
/// For POTA spots, `callsign` is the activator (you) and `spotter` is the
/// hunter who spotted you — so we match `spotter` against QSO callsigns.
struct SpotQSOMatch {
    // MARK: Lifecycle

    init(qsos: [QSO], spots: [SessionSpot]) {
        loggedCallsignBands = Set(qsos.map {
            "\($0.callsign.uppercased())|\($0.band)"
        })
        spottedCallsignBands = Set(
            spots.filter { !$0.isRBN }
                .compactMap { spot in
                    guard let band = spot.band else {
                        return nil
                    }
                    let call = Self.matchCallsign(for: spot)
                    return "\(call.uppercased())|\(band)"
                }
        )
    }

    // MARK: Internal

    /// "CALLSIGN|BAND" keys from session QSOs
    let loggedCallsignBands: Set<String>
    /// "CALLSIGN|BAND" keys from human (non-RBN) spots
    let spottedCallsignBands: Set<String>

    func qsoWasSpotted(_ qso: QSO) -> Bool {
        spottedCallsignBands.contains(
            "\(qso.callsign.uppercased())|\(qso.band)"
        )
    }

    func spotWasLogged(_ spot: SessionSpot) -> Bool {
        guard let band = spot.band else {
            return false
        }
        let call = Self.matchCallsign(for: spot)
        return loggedCallsignBands.contains("\(call.uppercased())|\(band)")
    }

    // MARK: Private

    /// POTA spots: spotter is the hunter (matches QSO callsign).
    /// Other spots: callsign is the station heard.
    private static func matchCallsign(for spot: SessionSpot) -> String {
        if spot.isPOTA, let spotter = spot.spotter {
            return spotter
        }
        return spot.callsign
    }
}
