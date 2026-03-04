import CarrierWaveData
import UIKit

// MARK: - FieldGuideLinker

/// Links Carrier Wave radio names to CW Field Guide deep links
enum FieldGuideLinker {
    // MARK: Internal

    /// Returns the Field Guide radio ID for a user-entered radio name, or nil
    static func fieldGuideID(for radioName: String) -> String? {
        let key = normalize(radioName)
        return lookupTable[key]
    }

    /// Whether Field Guide has a manual for the given radio name
    static func hasManual(for radioName: String) -> Bool {
        fieldGuideID(for: radioName) != nil
    }

    /// Open the radio's manual in CW Field Guide
    static func openManual(for radioName: String) {
        guard let radioID = fieldGuideID(for: radioName) else {
            return
        }
        guard let url = URL(string: "cwfieldguide://radio/\(radioID)") else {
            return
        }
        UIApplication.shared.open(url) { success in
            if !success {
                ToastManager.shared.warning("CW Field Guide is not installed")
            }
        }
    }

    /// Open the outing checklists tab in CW Field Guide, optionally pre-selecting a radio
    static func openChecklists(radioName: String? = nil) {
        var components = URLComponents()
        components.scheme = "cwfieldguide"
        components.host = "checklist"
        if let radioName, let radioID = fieldGuideID(for: radioName) {
            components.queryItems = [URLQueryItem(name: "radio", value: radioID)]
        }
        guard let url = components.url else {
            return
        }
        UIApplication.shared.open(url) { success in
            if !success {
                ToastManager.shared.warning("CW Field Guide is not installed")
            }
        }
    }

    // MARK: Private

    /// Lookup table mapping normalized name variants to Field Guide radio IDs
    private static let lookupTable: [String: String] = {
        var table: [String: String] = [:]
        // BG2FX
        register(&table, manufacturer: "BG2FX", model: "FX-4CR", id: "bg2fx-fx4cr")
        // Elecraft
        register(&table, manufacturer: "Elecraft", model: "K1", id: "elecraft-k1")
        register(&table, manufacturer: "Elecraft", model: "K2", id: "elecraft-k2")
        register(&table, manufacturer: "Elecraft", model: "KH1", id: "elecraft-kh1")
        register(&table, manufacturer: "Elecraft", model: "KX1", id: "elecraft-kx1")
        register(&table, manufacturer: "Elecraft", model: "KX2", id: "elecraft-kx2")
        register(&table, manufacturer: "Elecraft", model: "KX3", id: "elecraft-kx3")
        // HamGadgets
        register(&table, manufacturer: "HamGadgets", model: "CFT1", id: "hamgadgets-cft1")
        // ICOM
        register(&table, manufacturer: "ICOM", model: "IC-705", id: "icom-ic705")
        register(&table, manufacturer: "ICOM", model: "IC-7100", id: "icom-ic7100")
        register(&table, manufacturer: "ICOM", model: "IC-7300", id: "icom-ic7300")
        register(&table, manufacturer: "ICOM", model: "IC-7300 MK II", id: "icom-ic7300mk2")
        // LNR Precision
        register(&table, manufacturer: "LNR", model: "LD-5", id: "lnr-ld5")
        register(&table, manufacturer: "LNR", model: "MTR-3B V4", id: "lnr-mtr3b-v4")
        register(&table, manufacturer: "LNR", model: "MTR-4B V2", id: "lnr-mtr4b-v2")
        register(&table, manufacturer: "LNR", model: "MTR-5B", id: "lnr-mtr5b")
        // NorCal QRP Club
        register(&table, manufacturer: "NorCal", model: "20", id: "norcal-20")
        register(&table, manufacturer: "NorCal", model: "40A", id: "norcal-40a")
        // PennTek
        register(&table, manufacturer: "PennTek", model: "TR-25", id: "penntek-tr25")
        register(&table, manufacturer: "PennTek", model: "TR-35", id: "penntek-tr35")
        register(&table, manufacturer: "PennTek", model: "TR-45L", id: "penntek-tr45l")
        // Venus
        register(&table, manufacturer: "Venus", model: "SW-3B", id: "venus-sw3b")
        register(&table, manufacturer: "Venus", model: "SW-6B", id: "venus-sw6b")
        // Xiegu
        register(&table, manufacturer: "Xiegu", model: "G1M", id: "xiegu-g1m")
        register(&table, manufacturer: "Xiegu", model: "G90", id: "xiegu-g90")
        register(&table, manufacturer: "Xiegu", model: "G106", id: "xiegu-g106")
        register(&table, manufacturer: "Xiegu", model: "X5105", id: "xiegu-x5105")
        register(&table, manufacturer: "Xiegu", model: "X6100", id: "xiegu-x6100")
        register(&table, manufacturer: "Xiegu", model: "X6200", id: "xiegu-x6200")
        // Yaesu
        register(&table, manufacturer: "Yaesu", model: "FT-710", id: "yaesu-ft710")
        register(&table, manufacturer: "Yaesu", model: "FT-891", id: "yaesu-ft891")
        register(&table, manufacturer: "Yaesu", model: "FT-991A", id: "yaesu-ft991a")
        register(&table, manufacturer: "Yaesu", model: "FTDX101MP", id: "yaesu-ftdx101mp")
        register(&table, manufacturer: "Yaesu", model: "FTX-1", id: "yaesu-ftx1")
        return table
    }()

    /// Normalize a string for lookup: lowercase, strip spaces/hyphens/slashes
    private static func normalize(_ string: String) -> String {
        string.lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "/", with: "")
    }

    /// Register a radio's name variants in the lookup table
    private static func register(
        _ table: inout [String: String],
        manufacturer: String,
        model: String,
        id: String
    ) {
        table[normalize("\(manufacturer) \(model)")] = id
        table[normalize(model)] = id
        table[normalize(id)] = id
    }
}
