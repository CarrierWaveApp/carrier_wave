//! Decoded CW text element with role/category annotations. Port of
//! `CWTextElement.swift` + `SuggestionCategory.swift`.

/// Role of a callsign in a QSO. Matches `CallsignRole` in Swift.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CallsignRole {
    /// Station calling (after CQ, or before DE).
    Caller,
    /// Station being called (after DE).
    Callee,
    Unknown,
}

/// Category of a suggested CW word. Port of `SuggestionCategory`.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SuggestionCategory {
    Prosign,
    Abbreviation,
    Number,
}

impl SuggestionCategory {
    /// The Swift raw value (`prosign`/`abbreviation`/`number`).
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Prosign => "prosign",
            Self::Abbreviation => "abbreviation",
            Self::Number => "number",
        }
    }
}

/// One segment of decoded CW text. Mirrors the Swift enum cases.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum CwTextElement {
    Text(String),
    Callsign {
        text: String,
        role: CallsignRole,
    },
    Prosign(String),
    SignalReport(String),
    /// Grid square, e.g. "EM74".
    Grid(String),
    /// Power level, e.g. "100W".
    Power(String),
    /// Operator name.
    Name(String),
    Suggestion {
        original: String,
        suggested: String,
        category: SuggestionCategory,
    },
}

impl CwTextElement {
    /// Stable composite ID matching `CWTextElement.id` in Swift.
    pub fn id(&self) -> String {
        match self {
            Self::Text(s) => format!("text-{s}"),
            Self::Callsign { text, .. } => format!("call-{text}"),
            Self::Prosign(s) => format!("pro-{s}"),
            Self::SignalReport(s) => format!("rst-{s}"),
            Self::Grid(s) => format!("grid-{s}"),
            Self::Power(s) => format!("pwr-{s}"),
            Self::Name(s) => format!("name-{s}"),
            Self::Suggestion {
                original,
                suggested,
                ..
            } => format!("sug-{original}-{suggested}"),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ids_match_swift_format() {
        assert_eq!(CwTextElement::Text("CQ".into()).id(), "text-CQ");
        assert_eq!(
            CwTextElement::Callsign {
                text: "W6JY".into(),
                role: CallsignRole::Caller,
            }
            .id(),
            "call-W6JY"
        );
        assert_eq!(CwTextElement::Prosign("AR".into()).id(), "pro-AR");
        assert_eq!(CwTextElement::SignalReport("599".into()).id(), "rst-599");
        assert_eq!(CwTextElement::Grid("EM74".into()).id(), "grid-EM74");
        assert_eq!(CwTextElement::Power("100W".into()).id(), "pwr-100W");
        assert_eq!(CwTextElement::Name("Jay".into()).id(), "name-Jay");
        assert_eq!(
            CwTextElement::Suggestion {
                original: "ar".into(),
                suggested: "AR".into(),
                category: SuggestionCategory::Prosign,
            }
            .id(),
            "sug-ar-AR"
        );
    }

    #[test]
    fn suggestion_category_raw_values() {
        assert_eq!(SuggestionCategory::Prosign.as_str(), "prosign");
        assert_eq!(SuggestionCategory::Abbreviation.as_str(), "abbreviation");
        assert_eq!(SuggestionCategory::Number.as_str(), "number");
    }
}
