//! Parsed FT8 message types + computed properties. Port of `FT8Message`.

/// A parsed FT8 message representing a step in the standard QSO exchange.
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub enum Ft8Message {
    Cq { call: String, grid: String, modifier: Option<String> },
    Directed { from: String, to: String, grid: String },
    SignalReport { from: String, to: String, db: i32 },
    RogerReport { from: String, to: String, db: i32 },
    Roger { from: String, to: String },
    RogerEnd { from: String, to: String },
    End { from: String, to: String },
    FreeText(String),
}

impl Ft8Message {
    /// Whether this message can be responded to (only CQ calls).
    pub fn is_callable(&self) -> bool {
        matches!(self, Ft8Message::Cq { .. })
    }

    /// Whether this message signals QSO completion.
    pub fn completes_qso(&self) -> bool {
        matches!(self, Ft8Message::RogerEnd { .. } | Ft8Message::End { .. })
    }

    /// The originating callsign, if applicable.
    pub fn caller_callsign(&self) -> Option<&str> {
        match self {
            Ft8Message::Cq { call, .. } => Some(call),
            Ft8Message::Directed { from, .. }
            | Ft8Message::SignalReport { from, .. }
            | Ft8Message::RogerReport { from, .. }
            | Ft8Message::Roger { from, .. }
            | Ft8Message::RogerEnd { from, .. }
            | Ft8Message::End { from, .. } => Some(from),
            Ft8Message::FreeText(_) => None,
        }
    }

    /// Grid locator from CQ or directed messages; `None` if empty or absent.
    pub fn grid(&self) -> Option<&str> {
        match self {
            Ft8Message::Cq { grid, .. } | Ft8Message::Directed { grid, .. } => {
                if grid.is_empty() {
                    None
                } else {
                    Some(grid)
                }
            }
            _ => None,
        }
    }

    /// CQ modifier (POTA, DX, …), only on CQ messages.
    pub fn cq_modifier(&self) -> Option<&str> {
        match self {
            Ft8Message::Cq { modifier, .. } => modifier.as_deref(),
            _ => None,
        }
    }

    /// Destination callsign for directed messages; `None` for CQ and free text.
    pub fn target_callsign(&self) -> Option<&str> {
        match self {
            Ft8Message::Directed { to, .. }
            | Ft8Message::SignalReport { to, .. }
            | Ft8Message::RogerReport { to, .. }
            | Ft8Message::Roger { to, .. }
            | Ft8Message::RogerEnd { to, .. }
            | Ft8Message::End { to, .. } => Some(to),
            Ft8Message::Cq { .. } | Ft8Message::FreeText(_) => None,
        }
    }

    /// Whether this message involves `callsign` as sender or receiver.
    pub fn involves(&self, callsign: &str) -> bool {
        let upper = callsign.to_uppercase();
        if self.caller_callsign().map(|c| c.to_uppercase()) == Some(upper.clone()) {
            return true;
        }
        if self.target_callsign().map(|c| c.to_uppercase()) == Some(upper) {
            return true;
        }
        false
    }

    /// Whether this message is directed to `callsign` (case-insensitive).
    pub fn is_directed_to(&self, callsign: &str) -> bool {
        let target = callsign.to_uppercase();
        self.target_callsign().map(|t| t.to_uppercase()) == Some(target)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn cq_properties() {
        let cq = Ft8Message::Cq {
            call: "W1AW".into(),
            grid: "FN31".into(),
            modifier: Some("POTA".into()),
        };
        assert!(cq.is_callable());
        assert!(!cq.completes_qso());
        assert_eq!(cq.caller_callsign(), Some("W1AW"));
        assert_eq!(cq.grid(), Some("FN31"));
        assert_eq!(cq.cq_modifier(), Some("POTA"));
        assert_eq!(cq.target_callsign(), None);
    }

    #[test]
    fn directed_and_involvement() {
        let msg = Ft8Message::SignalReport { from: "K2ABC".into(), to: "W1AW".into(), db: -12 };
        assert!(msg.involves("w1aw"));
        assert!(msg.involves("K2ABC"));
        assert!(!msg.involves("N0CALL"));
        assert!(msg.is_directed_to("w1aw"));
        assert!(!msg.is_directed_to("k2abc"));
    }

    #[test]
    fn completion() {
        let end = Ft8Message::RogerEnd { from: "A".into(), to: "B".into() };
        assert!(end.completes_qso());
        let free = Ft8Message::FreeText("HELLO".into());
        assert_eq!(free.caller_callsign(), None);
        assert_eq!(free.grid(), None);
    }
}
