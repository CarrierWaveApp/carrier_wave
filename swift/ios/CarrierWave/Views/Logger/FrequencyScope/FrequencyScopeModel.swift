import CarrierWaveCore
import CarrierWaveCwFfi
import CarrierWaveData
import SwiftUI

// MARK: - ScopeSpot

/// One on-air station rendered as a row in the frequency scope. Mirrors the
/// Band Scope's `ScopeRow` vocabulary (tier dot, monospaced call, age) but is
/// self-contained so the session wizard can feed it live spots without the
/// full spot-engine plumbing.
struct ScopeSpot: Identifiable, Hashable {
    let id = UUID()
    /// True dial frequency in Hz — full precision, never rounded to whole kHz.
    let frequencyHz: Int
    let callsign: String
    let tier: SpotTier
    let mode: String
    let wpm: Int?
    let ageSeconds: Int

    /// Compact age string matching `BandScopeAge` (`25s`, `11m`, `2h`).
    var ageText: String {
        if ageSeconds < 60 {
            return "\(ageSeconds)s"
        }
        if ageSeconds < 3_600 {
            return "\(ageSeconds / 60)m"
        }
        return "\(ageSeconds / 3_600)h"
    }

    /// One goal chip max (§9): needed → NEW DX, club → CLUB, else none.
    var chip: String? {
        switch tier {
        case .needed: "NEW DX"
        case .club: "CLUB"
        default: nil
        }
    }
}

// MARK: - ScopeVerdict

/// The advisory shown under the readout. `isGood` drives green vs orange on the
/// reticle, the advisory, and the Start-bar caution — orange whenever the pick
/// is off (off-plan, no privilege, wrong segment, or QRM), green only when
/// clear and appropriate.
struct ScopeVerdict {
    let isGood: Bool
    let message: String

    var attributed: AttributedString {
        (try? AttributedString(
            markdown: message,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(message)
    }
}

// MARK: - ScopeRowInfo

/// Precomputed render data for one ruler row (frequency in Hz). Building these
/// once per band/mode/step — instead of per scroll frame — keeps the fling
/// smooth: the band-plan lookups never run on the scroll path.
struct ScopeRowInfo: Identifiable, Equatable {
    let hz: Int
    let freqText: String
    let spot: ScopeSpot?
    let hatched: Bool
    let segLabel: String?
    let blockLabel: String?
    let hole: String?
    /// Extra stations sharing this row beyond the lead (pileup / duplicate
    /// decodes) — rendered as "+N".
    let pileupCount: Int
    /// Verdict precomputed at build time so the scroll path does zero band-plan
    /// work — the field just looks these up for the centered row.
    let isGood: Bool
    let advisory: String

    var id: Int {
        hz
    }
}

// MARK: - FrequencyScopeLogic

/// Thin adapter over the shared `cw_domain::frequency_scope` Rust port. All
/// band-plan evaluation, ruler-row building, and advisory phrasing now live in
/// Rust (`frequency_scope_*` FFI); this only maps the FFI DTOs to the
/// view-layer `ScopeRowInfo` / `ScopeVerdict` vocabulary. Both platforms call
/// the same port — no duplicated logic.
enum FrequencyScopeLogic {
    /// Bands with a band plan, in scope order.
    static func availableBands() -> [String] {
        frequencyScopeAvailableBands()
    }

    /// Full displayable Hz span of a band.
    static func bandRangeHz(_ band: String) -> ClosedRange<Int>? {
        guard let range = frequencyScopeBandRange(band: band) else {
            return nil
        }
        return Int(range.lowHz) ... Int(range.highHz)
    }

    /// Where the scope starts for a band+mode.
    static func defaultHz(band: String, mode: String) -> Int? {
        frequencyScopeDefaultHz(band: band, mode: mode).map { Int($0) }
    }

    /// The verdict + advisory for one frequency (Hz).
    static func evaluate(
        hz: Int, band: String, mode: String, license: LicenseClass, spots: [ScopeSpot]
    ) -> ScopeVerdict {
        let verdict = frequencyScopeEvaluate(
            hz: Int64(hz), band: band, mode: mode,
            license: license.ffi, spots: spots.map(\.ffi)
        )
        return ScopeVerdict(isGood: verdict.isGood, message: verdict.message)
    }

    /// Build every ruler row for a band at the current step (Hz).
    static func buildRows(
        band: String, mode: String, license: LicenseClass, step: Int, spots: [ScopeSpot]
    ) -> [ScopeRowInfo] {
        frequencyScopeRows(
            band: band, mode: mode, license: license.ffi,
            step: Int64(step), spots: spots.map(\.ffi)
        )
        .map(ScopeRowInfo.init(ffi:))
    }
}

// MARK: - FFI DTO mapping

private extension LicenseClass {
    var ffi: FfiLicenseClass {
        switch self {
        case .technician: .technician
        case .general: .general
        case .extra: .extra
        }
    }
}

private extension ScopeSpot {
    var ffi: FfiScopeSpot {
        FfiScopeSpot(
            frequencyHz: Int64(frequencyHz),
            callsign: callsign,
            tier: Int32(tier.rawValue),
            wpm: wpm.map { Int32($0) },
            ageSeconds: Int64(ageSeconds)
        )
    }

    init(ffi: FfiScopeSpot) {
        self.init(
            frequencyHz: Int(ffi.frequencyHz),
            callsign: ffi.callsign,
            tier: SpotTier(rawValue: Int(ffi.tier)) ?? .rbn,
            mode: "",
            wpm: ffi.wpm.map { Int($0) },
            ageSeconds: Int(ffi.ageSeconds)
        )
    }
}

private extension ScopeRowInfo {
    init(ffi: FfiScopeRow) {
        self.init(
            hz: Int(ffi.hz),
            freqText: ffi.freqText,
            spot: ffi.spot.map(ScopeSpot.init(ffi:)),
            hatched: ffi.hatched,
            segLabel: ffi.segLabel,
            blockLabel: ffi.blockLabel,
            hole: ffi.hole,
            pileupCount: Int(ffi.pileupCount),
            isGood: ffi.isGood,
            advisory: ffi.advisory
        )
    }
}
