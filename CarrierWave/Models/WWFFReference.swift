// WWFF Reference
//
// Data model for a WWFF (World Wide Flora & Fauna) reference
// representing a protected natural area registered in the WWFF directory.

import CarrierWaveData
import Foundation

// MARK: - WWFFReference

struct WWFFReference: Sendable {
    let reference: String // e.g., "KFF-1234"
    let name: String // e.g., "Yellowstone National Park"
    let program: String // e.g., "KFF"
    let status: String // e.g., "active"
    let continent: String? // e.g., "NA"
    let iota: String? // IOTA reference
    let grid: String? // Maidenhead locator
    let latitude: Double?
    let longitude: Double?
    let iucnCategory: String? // IUCN conservation category
    let country: String? // Country name
    let region: String? // Region name
    let dxccEntity: Int? // DXCC entity number
}
