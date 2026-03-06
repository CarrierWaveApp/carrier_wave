import Foundation
import Testing
@testable import CWSweep

// MARK: - KiwiSDRMode Tests

@Test func kiwiSDRModeKiwiNames() {
    #expect(KiwiSDRMode.cw.kiwiName == "cw")
    #expect(KiwiSDRMode.usb.kiwiName == "usb")
    #expect(KiwiSDRMode.lsb.kiwiName == "lsb")
    #expect(KiwiSDRMode.am.kiwiName == "am")
    #expect(KiwiSDRMode.nbfm.kiwiName == "nbfm")
}

@Test func kiwiSDRModeDisplayNames() {
    #expect(KiwiSDRMode.cw.displayName == "CW")
    #expect(KiwiSDRMode.usb.displayName == "USB")
    #expect(KiwiSDRMode.lsb.displayName == "LSB")
    #expect(KiwiSDRMode.am.displayName == "AM")
    #expect(KiwiSDRMode.nbfm.displayName == "NBFM")
}

@Test func kiwiSDRModeBandwidths() {
    // CW: 300-800 = 500 Hz
    #expect(KiwiSDRMode.cw.bandwidthHz == 500)
    // USB: 300-2700 = 2400 Hz
    #expect(KiwiSDRMode.usb.bandwidthHz == 2_400)
    // LSB: -2700 to -300 = 2400 Hz
    #expect(KiwiSDRMode.lsb.bandwidthHz == 2_400)
    // AM: -5000 to 5000 = 10000 Hz
    #expect(KiwiSDRMode.am.bandwidthHz == 10_000)
}

@Test func kiwiSDRModeBandwidthDescriptions() {
    #expect(KiwiSDRMode.cw.bandwidthDescription == "500 Hz")
    #expect(KiwiSDRMode.usb.bandwidthDescription == "2.4 kHz")
    #expect(KiwiSDRMode.am.bandwidthDescription == "10.0 kHz")
}

@Test func kiwiSDRModeCarrierOffset() {
    // CW offset = (300 + 800) / 2 / 1000 = 0.55
    #expect(KiwiSDRMode.cw.carrierOffsetKHz == 0.55)
    // All others should be 0
    #expect(KiwiSDRMode.usb.carrierOffsetKHz == 0)
    #expect(KiwiSDRMode.lsb.carrierOffsetKHz == 0)
    #expect(KiwiSDRMode.am.carrierOffsetKHz == 0)
}

@Test func kiwiSDRModeFromCarrierWaveMode() {
    // Direct mappings
    #expect(KiwiSDRMode.from(carrierWaveMode: "CW", frequencyMHz: nil) == .cw)
    #expect(KiwiSDRMode.from(carrierWaveMode: "USB", frequencyMHz: nil) == .usb)
    #expect(KiwiSDRMode.from(carrierWaveMode: "LSB", frequencyMHz: nil) == .lsb)
    #expect(KiwiSDRMode.from(carrierWaveMode: "AM", frequencyMHz: nil) == .am)
    #expect(KiwiSDRMode.from(carrierWaveMode: "FM", frequencyMHz: nil) == .nbfm)

    // SSB auto-select: below 10 MHz = LSB, above = USB
    #expect(KiwiSDRMode.from(carrierWaveMode: "SSB", frequencyMHz: 7.074) == .lsb)
    #expect(KiwiSDRMode.from(carrierWaveMode: "SSB", frequencyMHz: 14.074) == .usb)

    // Digital modes → USB
    #expect(KiwiSDRMode.from(carrierWaveMode: "FT8", frequencyMHz: nil) == .usb)
    #expect(KiwiSDRMode.from(carrierWaveMode: "RTTY", frequencyMHz: nil) == .usb)
    #expect(KiwiSDRMode.from(carrierWaveMode: "DATA", frequencyMHz: nil) == .usb)

    // Unknown → USB
    #expect(KiwiSDRMode.from(carrierWaveMode: "UNKNOWN", frequencyMHz: nil) == .usb)
}

// MARK: - KiwiSDRError Tests

@Test func kiwiSDRErrorDescriptions() {
    #expect(KiwiSDRError.invalidURL.errorDescription == "Invalid KiwiSDR URL")
    #expect(KiwiSDRError.notConnected.errorDescription == "Not connected to KiwiSDR")
    #expect(KiwiSDRError.connectionLost.errorDescription == "Connection to KiwiSDR lost")
    #expect(KiwiSDRError.authenticationFailed.errorDescription == "KiwiSDR authentication failed (bad password)")
    #expect(KiwiSDRError.tooBusy(4).errorDescription == "KiwiSDR is full (4 channels in use)")
    #expect(KiwiSDRError.serverRedirect("http://other.host")
        .errorDescription == "KiwiSDR redirected to http://other.host")
}
