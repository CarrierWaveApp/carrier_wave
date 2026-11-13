//! Pack-checklist reminder generation — port of `GearReminderEngine`
//! (`GearReminderStorage.swift`).
//!
//! Given the selected radio/antenna connector tags, the operating mode, and
//! whether an antenna/key is present, produce the ordered "don't forget"
//! reminders the wizard's Pack Checklist shows. Pure and deterministic (stable
//! ids), so iOS and Android render the identical list. Connector *persistence*
//! (the iCloud-KVS `GearConnectorStorage`) stays host-side; this owns only the
//! generation rules.

/// RF connector types used on radios and antennas (`ConnectorType`).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ConnectorType {
    Bnc,
    So239,
    Sma,
    NType,
}

impl ConnectorType {
    /// The Swift `rawValue` string.
    pub fn raw_value(self) -> &'static str {
        match self {
            ConnectorType::Bnc => "BNC",
            ConnectorType::So239 => "SO-239",
            ConnectorType::Sma => "SMA",
            ConnectorType::NType => "N-Type",
        }
    }

    /// Parse from the raw value; `None` for anything else.
    pub fn from_raw(raw: &str) -> Option<ConnectorType> {
        match raw {
            "BNC" => Some(ConnectorType::Bnc),
            "SO-239" => Some(ConnectorType::So239),
            "SMA" => Some(ConnectorType::Sma),
            "N-Type" => Some(ConnectorType::NType),
            _ => None,
        }
    }

    /// The coax/cable label (`coaxLabel`).
    pub fn coax_label(self) -> &'static str {
        match self {
            ConnectorType::Bnc => "BNC coax",
            ConnectorType::So239 => "PL-259 coax",
            ConnectorType::Sma => "SMA coax",
            ConnectorType::NType => "N-Type coax",
        }
    }
}

/// A contextual reminder generated from the selected equipment combo
/// (`GearReminder`). `id` is deterministic for stable identity across
/// regenerations.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct GearReminder {
    pub id: String,
    pub text: String,
    pub icon: String,
}

impl GearReminder {
    fn new(id: impl Into<String>, text: impl Into<String>, icon: &str) -> GearReminder {
        GearReminder { id: id.into(), text: text.into(), icon: icon.to_string() }
    }
}

const CABLE_ICON: &str = "cable.connector";

/// Voice modes that prompt a mic-cable reminder.
const VOICE_MODES: [&str; 5] = ["SSB", "USB", "LSB", "AM", "FM"];
/// Digital modes that prompt an audio-interface reminder.
const DIGITAL_MODES: [&str; 4] = ["FT8", "FT4", "JTTY", "DIGITAL"];

/// Build the reminders for the current equipment combination
/// (`GearReminderEngine.generate`), preserving section order:
/// connector → antenna → power → mode → general.
pub fn generate(
    radio_connector: Option<ConnectorType>,
    antenna_connector: Option<ConnectorType>,
    mode: &str,
    has_antenna: bool,
    has_key: bool,
) -> Vec<GearReminder> {
    let mut result = Vec::new();
    append_connector(radio_connector, antenna_connector, &mut result);
    append_antenna(has_antenna, &mut result);
    append_power(&mut result);
    append_mode(mode, has_key, &mut result);
    result.push(GearReminder::new("headphones", "Headphones", "headphones"));
    result
}

fn append_connector(
    radio: Option<ConnectorType>,
    antenna: Option<ConnectorType>,
    result: &mut Vec<GearReminder>,
) {
    match (radio, antenna) {
        (Some(rc), Some(ac)) if rc == ac => {
            result.push(GearReminder::new(format!("coax-{}", rc.raw_value()), rc.coax_label(), CABLE_ICON));
        }
        (Some(rc), Some(ac)) => {
            result.push(GearReminder::new(
                format!("adapter-{}-{}", rc.raw_value(), ac.raw_value()),
                format!("{}-to-{} adapter", rc.raw_value(), ac.raw_value()),
                "arrow.triangle.swap",
            ));
            result.push(GearReminder::new(
                format!("coax-{}", ac.raw_value()),
                format!("{} (antenna side)", ac.coax_label()),
                CABLE_ICON,
            ));
        }
        (Some(rc), None) => {
            result.push(GearReminder::new(format!("coax-{}", rc.raw_value()), rc.coax_label(), CABLE_ICON));
        }
        (None, Some(ac)) => {
            result.push(GearReminder::new(format!("coax-{}", ac.raw_value()), ac.coax_label(), CABLE_ICON));
        }
        (None, None) => {}
    }
}

fn append_antenna(has_antenna: bool, result: &mut Vec<GearReminder>) {
    if !has_antenna {
        return;
    }
    result.push(GearReminder::new("counterpoise", "Counterpoise / radials", "line.diagonal"));
    result.push(GearReminder::new("mast", "Antenna support / mast", "arrow.up.to.line"));
    result.push(GearReminder::new("guy-lines", "Guy lines & stakes", "tent"));
}

fn append_power(result: &mut Vec<GearReminder>) {
    result.push(GearReminder::new("power-cable", "Power cable", "bolt"));
    result.push(GearReminder::new("battery", "Battery / power supply", "battery.100"));
}

fn append_mode(mode: &str, has_key: bool, result: &mut Vec<GearReminder>) {
    if mode == "CW" && has_key {
        result.push(GearReminder::new("key-cable", "Paddle cable (1/4\u{2033} or 3.5mm)", CABLE_ICON));
    }
    if VOICE_MODES.contains(&mode) {
        result.push(GearReminder::new("mic-cable", "Mic cable / adapter", CABLE_ICON));
    }
    if DIGITAL_MODES.contains(&mode) {
        result.push(GearReminder::new("audio-interface", "Audio interface / USB cable", CABLE_ICON));
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn ids(reminders: &[GearReminder]) -> Vec<&str> {
        reminders.iter().map(|reminder| reminder.id.as_str()).collect()
    }

    #[test]
    fn matching_connectors_share_one_coax() {
        let reminders = generate(Some(ConnectorType::Bnc), Some(ConnectorType::Bnc), "CW", true, true);
        assert_eq!(reminders[0].id, "coax-BNC");
        assert_eq!(reminders[0].text, "BNC coax");
    }

    #[test]
    fn mismatched_connectors_add_adapter_and_antenna_coax() {
        let reminders = generate(Some(ConnectorType::Bnc), Some(ConnectorType::So239), "CW", true, false);
        assert_eq!(reminders[0].id, "adapter-BNC-SO-239");
        assert_eq!(reminders[0].text, "BNC-to-SO-239 adapter");
        assert_eq!(reminders[1].id, "coax-SO-239");
        assert_eq!(reminders[1].text, "PL-259 coax (antenna side)");
    }

    #[test]
    fn cw_with_key_adds_paddle_cable() {
        let reminders = generate(None, None, "CW", false, true);
        assert!(ids(&reminders).contains(&"key-cable"));
        // No antenna → no counterpoise; power + headphones always present.
        assert!(!ids(&reminders).contains(&"counterpoise"));
        assert!(ids(&reminders).contains(&"power-cable"));
        assert!(ids(&reminders).contains(&"battery"));
        assert_eq!(reminders.last().unwrap().id, "headphones");
    }

    #[test]
    fn voice_mode_adds_mic_cable_not_key() {
        let reminders = generate(None, None, "SSB", false, true);
        assert!(ids(&reminders).contains(&"mic-cable"));
        assert!(!ids(&reminders).contains(&"key-cable"));
    }

    #[test]
    fn digital_mode_adds_audio_interface() {
        let reminders = generate(None, None, "FT8", true, false);
        assert!(ids(&reminders).contains(&"audio-interface"));
    }

    #[test]
    fn section_order_connector_antenna_power_mode_general() {
        let reminders = generate(Some(ConnectorType::Sma), None, "CW", true, true);
        assert_eq!(
            ids(&reminders),
            vec![
                "coax-SMA",       // connector
                "counterpoise",   // antenna
                "mast",
                "guy-lines",
                "power-cable",    // power
                "battery",
                "key-cable",      // mode
                "headphones",     // general
            ]
        );
    }

    #[test]
    fn connector_roundtrip() {
        for connector in [ConnectorType::Bnc, ConnectorType::So239, ConnectorType::Sma, ConnectorType::NType] {
            assert_eq!(ConnectorType::from_raw(connector.raw_value()), Some(connector));
        }
        assert_eq!(ConnectorType::from_raw("XYZ"), None);
    }
}
