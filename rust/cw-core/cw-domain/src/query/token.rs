//! Query tokens & fields. Port of `QueryToken.swift`.

/// Searchable fields in QSO records. Discriminant order mirrors the Swift enum.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum QueryField {
    Callsign,
    Band,
    Mode,
    Frequency,
    Park,
    Sota,
    Grid,
    State,
    Country,
    Dxcc,
    Name,
    Qth,
    Notes,
    MyCallsign,
    MyGrid,
    Date,
    After,
    Before,
    Power,
    Confirmed,
    Synced,
    Pending,
    Source,
}

impl QueryField {
    /// All recognized aliases → field. Mirrors `QueryField.aliases`.
    pub fn parse(name: &str) -> Option<QueryField> {
        use QueryField::*;
        Some(match name.to_lowercase().as_str() {
            "call" | "callsign" => Callsign,
            "band" => Band,
            "mode" => Mode,
            "freq" | "frequency" => Frequency,
            "park" | "pota" => Park,
            "sota" => Sota,
            "grid" => Grid,
            "state" => State,
            "country" => Country,
            "dxcc" => Dxcc,
            "name" | "op" => Name,
            "qth" => Qth,
            "notes" => Notes,
            "mycall" => MyCallsign,
            "mygrid" => MyGrid,
            "date" | "on" => Date,
            "after" | "since" | "from" => After,
            "before" | "until" | "to" => Before,
            "power" => Power,
            "confirmed" => Confirmed,
            "synced" => Synced,
            "pending" => Pending,
            "source" => Source,
            _ => return None,
        })
    }

    /// All alias keys (for fuzzy "did you mean" suggestions). Order matches the
    /// Swift dictionary literal so nearest-match ties resolve identically.
    pub const ALIAS_KEYS: [&'static str; 31] = [
        "call", "callsign", "band", "mode", "freq", "frequency", "park", "pota", "sota", "grid",
        "state", "country", "dxcc", "name", "op", "qth", "notes", "mycall", "mygrid", "date", "on",
        "after", "since", "from", "before", "until", "to", "power", "confirmed", "synced",
        "pending",
    ];

    pub fn display_name(self) -> &'static str {
        use QueryField::*;
        match self {
            Callsign => "callsign",
            Band => "band",
            Mode => "mode",
            Frequency => "frequency",
            Park => "park",
            Sota => "sota",
            Grid => "grid",
            State => "state",
            Country => "country",
            Dxcc => "dxcc",
            Name => "name",
            Qth => "qth",
            Notes => "notes",
            MyCallsign => "mycall",
            MyGrid => "mygrid",
            Date => "date",
            After => "after",
            Before => "before",
            Power => "power",
            Confirmed => "confirmed",
            Synced => "synced",
            Pending => "pending",
            Source => "source",
        }
    }

    pub fn is_indexed(self) -> bool {
        use QueryField::*;
        matches!(self, Callsign | Band | Mode | Park | Date | After | Before)
    }

    pub fn requires_text_scan(self) -> bool {
        use QueryField::*;
        matches!(self, Notes | Name | Qth)
    }
}

/// Token types produced by the lexer. Port of `QueryToken`.
#[derive(Debug, Clone, PartialEq)]
pub enum QueryToken {
    Field(QueryField),
    Value(String),
    Or,
    Not,
    OpenParen,
    CloseParen,
    Range,
    GreaterThan,
    LessThan,
    GreaterThanOrEqual,
    LessThanOrEqual,
    Eof,
}

/// Position in the source string for error reporting.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct SourcePosition {
    pub offset: usize,
    pub length: usize,
}

impl SourcePosition {
    pub const UNKNOWN: SourcePosition = SourcePosition { offset: 0, length: 0 };

    pub fn new(offset: usize, length: usize) -> Self {
        SourcePosition { offset, length }
    }
}

/// Token + source position + raw text. Port of `PositionedToken`.
#[derive(Debug, Clone, PartialEq)]
pub struct PositionedToken {
    pub token: QueryToken,
    pub position: SourcePosition,
    pub raw_text: String,
}

impl PositionedToken {
    pub fn new(token: QueryToken, position: SourcePosition, raw_text: impl Into<String>) -> Self {
        PositionedToken { token, position, raw_text: raw_text.into() }
    }
}
