import CarrierWaveData
import Foundation

enum StatCategoryType: String, CaseIterable, Identifiable {
    case qsls
    case entities
    case grids
    case bands
    case parks
    case frequencies
    case bestFriends
    case bestHunters

    // MARK: Internal

    var id: String {
        rawValue
    }

    nonisolated var title: String {
        switch self {
        case .qsls: "QSLs"
        case .entities: "DXCC Entities"
        case .grids: "Grids"
        case .bands: "Bands"
        case .parks: "Activations"
        case .frequencies: "Favorite Frequencies"
        case .bestFriends: "Best Friends"
        case .bestHunters: "Best Hunters"
        }
    }

    var icon: String {
        switch self {
        case .qsls: "checkmark.seal"
        case .entities: "globe"
        case .grids: "square.grid.3x3"
        case .bands: "waveform"
        case .parks: "leaf"
        case .frequencies: "dial.medium.fill"
        case .bestFriends: "person.2.fill"
        case .bestHunters: "scope"
        }
    }

    nonisolated var explanation: String {
        detailedExplanation.summary
    }

    nonisolated var detailedExplanation: StatMethodology {
        switch self {
        case .qsls:
            StatMethodology(
                title: "QSLs (Confirmed QSOs)",
                summary: "QSOs confirmed by LoTW or QRZ. "
                    + "A QSL means both stations logged the contact.",
                included: [
                    "QSOs confirmed via Logbook of the World (LoTW)",
                    "QSOs confirmed via QRZ.com logbook",
                    "A single QSO confirmed by both services counts once",
                ],
                excluded: [
                    "Metadata pseudo-modes (WEATHER, SOLAR, NOTE)",
                    "Hidden/deleted QSOs",
                    "Unconfirmed QSOs (logged but not yet confirmed)",
                    "eQSL, paper QSL, or other confirmation methods",
                ],
                edgeCases: [
                    "Confirmation status depends on your last sync — "
                        + "new confirmations appear after syncing with LoTW/QRZ",
                    "Drilldown groups confirmed QSOs by DXCC entity",
                    "QSOs without a DXCC entity match are confirmed but "
                        + "won't appear in the entity drilldown",
                ],
                methodology: "Counts QSOs where lotwConfirmed OR qrzConfirmed is true"
            )
        case .entities:
            StatMethodology(
                title: "DXCC Entities",
                summary: "Unique countries/territories you've contacted, "
                    + "based on callsign prefix lookup.",
                included: [
                    "All non-hidden QSOs with a recognized callsign prefix",
                    "Each unique DXCC entity number counted once",
                ],
                excluded: [
                    "Metadata pseudo-modes (WEATHER, SOLAR, NOTE)",
                    "Hidden/deleted QSOs",
                    "QSOs with unrecognized callsign prefixes",
                ],
                edgeCases: [
                    "Entity lookup uses the callsign prefix table — "
                        + "special-event or vanity callsigns may map to "
                        + "an unexpected entity",
                    "Portable operations (e.g. W1ABC/VP9) are detected "
                        + "by prefix, not the /portable suffix",
                    "Multiple QSOs to the same entity count once for the total "
                        + "but all appear in the drilldown",
                ],
                methodology: "Groups QSOs by DXCC entity number, "
                    + "counts unique entity numbers"
            )
        case .grids:
            StatMethodology(
                title: "Grid Squares",
                summary: "Unique Maidenhead grid squares you've contacted. "
                    + "Each grid covers ~100×200 km.",
                included: [
                    "QSOs where the other station reported a grid square",
                    "Each unique grid counted once",
                ],
                excluded: [
                    "Metadata pseudo-modes (WEATHER, SOLAR, NOTE)",
                    "Hidden/deleted QSOs",
                    "QSOs with no grid square reported",
                ],
                edgeCases: [
                    "Grid squares are only as accurate as what "
                        + "the other station reports",
                    "4-character grids (e.g. FN31) and 6-character grids "
                        + "(e.g. FN31pr) are treated as different entries",
                    "Empty grid fields are ignored",
                ],
                methodology: "Collects unique non-empty grid values from QSOs"
            )
        case .bands:
            StatMethodology(
                title: "Bands",
                summary: "Unique amateur radio bands you've operated on.",
                included: [
                    "All non-hidden QSOs grouped by band (e.g. 20m, 40m, 2m)",
                    "Band is determined from QSO metadata, not frequency",
                ],
                excluded: [
                    "Metadata pseudo-modes (WEATHER, SOLAR, NOTE)",
                    "Hidden/deleted QSOs",
                ],
                edgeCases: [
                    "Band names are normalized to lowercase for grouping "
                        + "(\"20M\" and \"20m\" are the same band)",
                    "Out-of-band or unusual band labels are included as-is",
                    "The count shows unique bands; drilldown shows all QSOs per band",
                ],
                methodology: "Groups QSOs by lowercased band field, "
                    + "counts unique bands"
            )
        case .parks:
            StatMethodology(
                title: "POTA Activations",
                summary: "Successful activations: 10+ QSOs from a park "
                    + "in one UTC day.",
                included: [
                    "QSOs with a park reference that you were activating from",
                    "Grouped by park + UTC date — each day at a park "
                        + "is a separate activation",
                    "Only groups with 10+ QSOs count as successful",
                ],
                excluded: [
                    "Metadata pseudo-modes (WEATHER, SOLAR, NOTE)",
                    "Hidden/deleted QSOs",
                    "QSOs without a park reference",
                    "Activations with fewer than 10 QSOs (shown separately "
                        + "as attempts)",
                ],
                edgeCases: [
                    "UTC day boundaries matter — a park session spanning "
                        + "midnight UTC splits into two activations",
                    "Two-fer activations (two parks at once) create separate "
                        + "activation entries for each park",
                    "The \"Activations\" count on the dashboard is successful "
                        + "activations only (10+ QSOs)",
                ],
                methodology: "Groups QSOs by parkReference + UTC date, "
                    + "counts groups with ≥10 QSOs"
            )
        case .frequencies:
            StatMethodology(
                title: "Favorite Frequencies",
                summary: "Your most-used frequencies, "
                    + "rounded to the nearest 100 Hz.",
                included: [
                    "QSOs with a recorded frequency",
                    "Frequencies rounded to nearest 0.0001 MHz (100 Hz) "
                        + "for grouping",
                ],
                excluded: [
                    "Metadata pseudo-modes (WEATHER, SOLAR, NOTE)",
                    "Hidden/deleted QSOs",
                    "QSOs with no frequency data or frequency of 0",
                ],
                edgeCases: [
                    "Frequencies very close together (within 50 Hz) "
                        + "may group into the same entry",
                    "The band label shown is taken from the first QSO "
                        + "in each frequency group",
                    "Sorted by QSO count — most-used frequency appears first",
                ],
                methodology: "Groups QSOs by frequency rounded to 100 Hz, "
                    + "sorted by count descending"
            )
        case .bestFriends:
            StatMethodology(
                title: "Best Friends",
                summary: "Callsigns you contact most often.",
                included: [
                    "All non-hidden QSOs",
                    "Grouped by the other station's callsign (uppercased)",
                ],
                excluded: [
                    "Metadata pseudo-modes (WEATHER, SOLAR, NOTE)",
                    "Hidden/deleted QSOs",
                ],
                edgeCases: [
                    "Callsign variants (e.g. W1ABC and W1ABC/P) "
                        + "are counted separately",
                    "If you use callsign aliases, QSOs under all your "
                        + "callsigns are combined",
                    "Sorted by QSO count — your most frequent contact appears first",
                ],
                methodology: "Groups all QSOs by callsign, sorted by count descending"
            )
        case .bestHunters:
            StatMethodology(
                title: "Best Hunters",
                summary: "Callsigns that hunt you most often during "
                    + "POTA activations.",
                included: [
                    "QSOs where you had a park reference (you were activating)",
                    "Grouped by the hunter's callsign (uppercased)",
                ],
                excluded: [
                    "Metadata pseudo-modes (WEATHER, SOLAR, NOTE)",
                    "Hidden/deleted QSOs",
                    "QSOs without a park reference (non-activation contacts)",
                ],
                edgeCases: [
                    "Only counts contacts made while you were activating a park",
                    "Same hunter contacting you on multiple bands/modes "
                        + "during one activation counts multiple times",
                    "Sorted by QSO count — your most frequent hunter appears first",
                ],
                methodology: "Filters to QSOs with a park reference, "
                    + "groups by callsign, sorted by count descending"
            )
        }
    }
}
