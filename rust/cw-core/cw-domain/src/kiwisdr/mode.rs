//! KiwiSDR demodulation modes and passbands. Port of `KiwiSDRTypes.swift`
//! (`KiwiSDRMode`).

/// Radio modes supported by KiwiSDR, mapped from amateur radio modes.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum KiwiSdrMode {
    Cw,
    Usb,
    Lsb,
    Am,
    Nbfm,
}

impl KiwiSdrMode {
    /// KiwiSDR protocol name for this mode.
    pub fn kiwi_name(self) -> &'static str {
        match self {
            KiwiSdrMode::Cw => "cw",
            KiwiSdrMode::Usb => "usb",
            KiwiSdrMode::Lsb => "lsb",
            KiwiSdrMode::Am => "am",
            KiwiSdrMode::Nbfm => "nbfm",
        }
    }

    /// Human-readable mode name.
    pub fn display_name(self) -> &'static str {
        match self {
            KiwiSdrMode::Cw => "CW",
            KiwiSdrMode::Usb => "USB",
            KiwiSdrMode::Lsb => "LSB",
            KiwiSdrMode::Am => "AM",
            KiwiSdrMode::Nbfm => "NBFM",
        }
    }

    /// Low frequency cut in Hz.
    pub fn low_cut(self) -> i32 {
        match self {
            KiwiSdrMode::Cw => 300,
            KiwiSdrMode::Usb => 300,
            KiwiSdrMode::Lsb => -2_700,
            KiwiSdrMode::Am => -5_000,
            KiwiSdrMode::Nbfm => -6_000,
        }
    }

    /// High frequency cut in Hz.
    pub fn high_cut(self) -> i32 {
        match self {
            KiwiSdrMode::Cw => 800,
            KiwiSdrMode::Usb => 2_700,
            KiwiSdrMode::Lsb => -300,
            KiwiSdrMode::Am => 5_000,
            KiwiSdrMode::Nbfm => 6_000,
        }
    }

    /// Offset in kHz to subtract from the operating frequency to get the
    /// KiwiSDR carrier frequency. For CW the operating frequency is the signal
    /// frequency; the receiver must tune below it so the signal lands in the
    /// center of the audio passband.
    pub fn carrier_offset_khz(self) -> f64 {
        match self {
            KiwiSdrMode::Cw => f64::from(self.low_cut() + self.high_cut()) / 2.0 / 1_000.0,
            KiwiSdrMode::Usb | KiwiSdrMode::Lsb | KiwiSdrMode::Am | KiwiSdrMode::Nbfm => 0.0,
        }
    }

    /// Bandwidth in Hz.
    pub fn bandwidth_hz(self) -> i32 {
        self.high_cut() - self.low_cut()
    }

    /// Human-readable bandwidth description, e.g. `2.4 kHz` or `500 Hz`.
    pub fn bandwidth_description(self) -> String {
        let bw = self.bandwidth_hz();
        if bw >= 1_000 {
            format!("{:.1} kHz", f64::from(bw) / 1_000.0)
        } else {
            format!("{bw} Hz")
        }
    }

    /// Map from a Carrier Wave mode string to a KiwiSDR mode. SSB resolves to
    /// LSB below 10 MHz and USB at or above, matching the Swift port source.
    pub fn from_carrier_wave_mode(mode: &str, frequency_mhz: Option<f64>) -> KiwiSdrMode {
        match mode.to_uppercase().as_str() {
            "CW" => KiwiSdrMode::Cw,
            "SSB" => match frequency_mhz {
                Some(freq) if freq < 10.0 => KiwiSdrMode::Lsb,
                _ => KiwiSdrMode::Usb,
            },
            "USB" => KiwiSdrMode::Usb,
            "LSB" => KiwiSdrMode::Lsb,
            "FT8" | "FT4" | "RTTY" | "DATA" | "DIGITAL" | "PSK31" | "PSK" | "JT65" | "JT9"
            | "WSPR" | "JTTY" => KiwiSdrMode::Usb,
            "AM" => KiwiSdrMode::Am,
            "FM" => KiwiSdrMode::Nbfm,
            _ => KiwiSdrMode::Usb,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn cw_passband_and_carrier_offset() {
        let mode = KiwiSdrMode::Cw;
        assert_eq!(mode.low_cut(), 300);
        assert_eq!(mode.high_cut(), 800);
        assert_eq!(mode.bandwidth_hz(), 500);
        // Center of CW passband: (300 + 800) / 2 = 550 Hz = 0.550 kHz.
        assert!((mode.carrier_offset_khz() - 0.550).abs() < 1e-12);
        assert_eq!(mode.bandwidth_description(), "500 Hz");
    }

    #[test]
    fn voice_modes_have_no_carrier_offset() {
        for mode in [KiwiSdrMode::Usb, KiwiSdrMode::Lsb, KiwiSdrMode::Am, KiwiSdrMode::Nbfm] {
            assert_eq!(mode.carrier_offset_khz(), 0.0);
        }
        assert_eq!(KiwiSdrMode::Usb.bandwidth_description(), "2.4 kHz");
    }

    #[test]
    fn carrier_wave_mode_mapping() {
        assert_eq!(KiwiSdrMode::from_carrier_wave_mode("cw", None), KiwiSdrMode::Cw);
        assert_eq!(KiwiSdrMode::from_carrier_wave_mode("SSB", Some(7.2)), KiwiSdrMode::Lsb);
        assert_eq!(KiwiSdrMode::from_carrier_wave_mode("SSB", Some(14.2)), KiwiSdrMode::Usb);
        assert_eq!(KiwiSdrMode::from_carrier_wave_mode("SSB", None), KiwiSdrMode::Usb);
        assert_eq!(KiwiSdrMode::from_carrier_wave_mode("FT8", None), KiwiSdrMode::Usb);
        assert_eq!(KiwiSdrMode::from_carrier_wave_mode("AM", None), KiwiSdrMode::Am);
        assert_eq!(KiwiSdrMode::from_carrier_wave_mode("FM", None), KiwiSdrMode::Nbfm);
        assert_eq!(KiwiSdrMode::from_carrier_wave_mode("MYSTERY", None), KiwiSdrMode::Usb);
    }
}
