import Foundation

// MARK: - SatelliteDoppler

/// Doppler correction from the propagated slant-range rate, shared by the
/// iOS pointing/duplex screens and the CW Sweep satellite view.
///
/// `rangeRateKmPerSec` is positive while the satellite recedes (the sign the
/// Rust engine reports). Observed downlink `f_rx = f · (1 − ṙ/c)`; the uplink
/// is pre-corrected the opposite way, `f_tx = f · (1 + ṙ/c)`, so the
/// transponder hears the nominal frequency.
public enum SatelliteDoppler: Sendable {
    /// Speed of light in km/s.
    public static let lightSpeedKmPerSec = 299_792.458

    /// `−ṙ/c`: multiply a downlink by `(1 + factor)` and an uplink by
    /// `(1 − factor)`.
    public static func factor(rangeRateKmPerSec: Double) -> Double {
        -rangeRateKmPerSec / lightSpeedKmPerSec
    }

    /// The downlink frequency the receiver actually hears.
    public static func correctedDownlinkHz(nominalHz: Double, rangeRateKmPerSec: Double) -> Double {
        nominalHz * (1 - rangeRateKmPerSec / lightSpeedKmPerSec)
    }

    /// The uplink frequency to transmit so the satellite hears `nominalHz`.
    public static func correctedUplinkHz(nominalHz: Double, rangeRateKmPerSec: Double) -> Double {
        nominalHz * (1 + rangeRateKmPerSec / lightSpeedKmPerSec)
    }

    /// Downlink shift (corrected − nominal) in Hz; negative while receding.
    public static func downlinkShiftHz(nominalHz: Double, rangeRateKmPerSec: Double) -> Double {
        correctedDownlinkHz(nominalHz: nominalHz, rangeRateKmPerSec: rangeRateKmPerSec) - nominalHz
    }

    /// Uplink shift (corrected − nominal) in Hz; opposite sign to the downlink.
    public static func uplinkShiftHz(nominalHz: Double, rangeRateKmPerSec: Double) -> Double {
        correctedUplinkHz(nominalHz: nominalHz, rangeRateKmPerSec: rangeRateKmPerSec) - nominalHz
    }

    /// Round to the step most CAT paths accept without fighting the radio.
    public static func roundedHz(_ hz: Double, stepHz: Double = 10) -> UInt64 {
        UInt64(max(0, (hz / stepHz).rounded()) * stepHz)
    }
}
