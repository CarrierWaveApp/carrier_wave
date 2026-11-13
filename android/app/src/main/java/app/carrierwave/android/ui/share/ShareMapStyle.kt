package app.carrierwave.android.ui.share

import uniffi.cw_ffi.FfiShareMapStyle

/**
 * Display metadata for [FfiShareMapStyle], mirroring the iOS `ShareMapStyle`
 * `label`/`description` for the six custom-renderer cases
 * (`swift/packages/CarrierWaveData/Sources/CarrierWaveData/Models/Types.swift:139-165`).
 * iOS additionally has `.adaptive`/`.flat`/`.globe` (MapKit-backed); Android
 * has no MapKit equivalent, so those are absent here — `FfiShareMapStyle`
 * only carries the six Rust-rasterized styles.
 *
 * Extracted from the brag-sheet share flow (Task 9) so the activation share
 * card (Task 11) reuses the same style picker.
 */
fun FfiShareMapStyle.displayName(): String = when (this) {
    FfiShareMapStyle.AZIMUTHAL -> "Azimuthal"
    FfiShareMapStyle.MIDNIGHT -> "Midnight"
    FfiShareMapStyle.WARM -> "Warm"
    FfiShareMapStyle.OCEAN -> "Ocean"
    FfiShareMapStyle.ARCTIC -> "Arctic"
    FfiShareMapStyle.EMBER -> "Ember"
}

fun FfiShareMapStyle.description(): String = when (this) {
    FfiShareMapStyle.AZIMUTHAL -> "Azimuthal equidistant projection centered on your QTH"
    FfiShareMapStyle.MIDNIGHT -> "Deep indigo custom map"
    FfiShareMapStyle.WARM -> "Warm amber custom map"
    FfiShareMapStyle.OCEAN -> "Deep blue ocean chart"
    FfiShareMapStyle.ARCTIC -> "Cool grey-blue steel map"
    FfiShareMapStyle.EMBER -> "Red-orange signal heat map"
}

/**
 * Styles selectable for the current operator. Azimuthal requires a resolvable
 * home coordinate (it projects the map around the operator's QTH); if
 * [homeGridResolvable] is false, it's hidden from the picker — mirroring the
 * constraint iOS enforces (no operator coordinate → azimuthal is skipped).
 */
fun availableShareStyles(homeGridResolvable: Boolean): List<FfiShareMapStyle> =
    FfiShareMapStyle.values().filter { it != FfiShareMapStyle.AZIMUTHAL || homeGridResolvable }
