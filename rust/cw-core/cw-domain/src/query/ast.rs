//! Query AST. Port of `QueryAST.swift`.

use super::token::{QueryField, SourcePosition};
use crate::service_type::ServiceType;
use chrono::{Duration, Local, NaiveDate, NaiveDateTime, TimeZone};

/// Root node of a parsed query.
#[derive(Debug, Clone, PartialEq)]
pub struct ParsedQuery {
    pub expression: QueryExpression,
    pub source_text: String,
    /// Inclusive `[start, end]` `qso_date` window (unix seconds) ANDed onto the compiled SQL,
    /// independent of the DSL `expression`. Used by the brag-sheet consumer whose UTC instant
    /// period the day-granular DSL date terms can't express. `(None, None)` (the default) means
    /// no window. Never set by the parser — only by `with_date_window`.
    pub date_window: (Option<i64>, Option<i64>),
}

impl ParsedQuery {
    pub fn new(expression: QueryExpression, source_text: impl Into<String>) -> Self {
        ParsedQuery { expression, source_text: source_text.into(), date_window: (None, None) }
    }

    /// Return a copy with an inclusive `qso_date` window applied (see `date_window`).
    pub fn with_date_window(mut self, start: Option<i64>, end: Option<i64>) -> Self {
        self.date_window = (start, end);
        self
    }

    /// Whether the query matches everything.
    pub fn is_empty(&self) -> bool {
        matches!(self.expression, QueryExpression::Empty)
    }
}

/// Query expression tree.
#[derive(Debug, Clone, PartialEq)]
pub enum QueryExpression {
    Empty,
    Term(QueryTerm),
    And(Vec<QueryExpression>),
    Or(Vec<QueryExpression>),
    Not(Box<QueryExpression>),
}

impl QueryExpression {
    /// Flatten nested ANDs/ORs.
    pub fn flattened(&self) -> QueryExpression {
        match self {
            QueryExpression::Empty | QueryExpression::Term(_) => self.clone(),
            QueryExpression::And(expressions) => {
                let mut flattened = Vec::new();
                for expr in expressions {
                    let flat = expr.flattened();
                    if let QueryExpression::And(nested) = flat {
                        flattened.extend(nested);
                    } else {
                        flattened.push(flat);
                    }
                }
                if flattened.len() == 1 {
                    flattened.into_iter().next().unwrap()
                } else {
                    QueryExpression::And(flattened)
                }
            }
            QueryExpression::Or(expressions) => {
                let mut flattened = Vec::new();
                for expr in expressions {
                    let flat = expr.flattened();
                    if let QueryExpression::Or(nested) = flat {
                        flattened.extend(nested);
                    } else {
                        flattened.push(flat);
                    }
                }
                if flattened.len() == 1 {
                    flattened.into_iter().next().unwrap()
                } else {
                    QueryExpression::Or(flattened)
                }
            }
            QueryExpression::Not(inner) => QueryExpression::Not(Box::new(inner.flattened())),
        }
    }

    /// Extract all terms from the expression.
    pub fn all_terms(&self) -> Vec<QueryTerm> {
        match self {
            QueryExpression::Empty => vec![],
            QueryExpression::Term(term) => vec![term.clone()],
            QueryExpression::And(exprs) | QueryExpression::Or(exprs) => {
                exprs.iter().flat_map(|e| e.all_terms()).collect()
            }
            QueryExpression::Not(inner) => inner.all_terms(),
        }
    }

    /// Whether any positive term uses an indexed field.
    pub fn has_indexed_positive_term(&self) -> bool {
        match self {
            QueryExpression::Empty => false,
            QueryExpression::Term(term) => term.field.map(|f| f.is_indexed()).unwrap_or(false),
            QueryExpression::And(exprs) | QueryExpression::Or(exprs) => {
                exprs.iter().any(|e| e.has_indexed_positive_term())
            }
            QueryExpression::Not(_) => false,
        }
    }

    /// Whether all terms are negated.
    pub fn is_negation_only(&self) -> bool {
        match self {
            QueryExpression::Empty => false,
            QueryExpression::Term(_) => false,
            QueryExpression::And(exprs) => exprs.iter().all(|e| e.is_negation_only()),
            QueryExpression::Or(exprs) => exprs.iter().all(|e| e.is_negation_only()),
            QueryExpression::Not(_) => true,
        }
    }
}

/// A single search term.
#[derive(Debug, Clone, PartialEq)]
pub struct QueryTerm {
    /// nil for bare terms that match multiple fields.
    pub field: Option<QueryField>,
    pub condition: TermCondition,
    pub position: SourcePosition,
}

/// How a term matches values.
#[derive(Debug, Clone, PartialEq)]
pub enum TermCondition {
    Equals(String),
    Contains(String),
    Prefix(String),
    Suffix(String),
    GreaterThan(f64),
    LessThan(f64),
    GreaterThanOrEqual(f64),
    LessThanOrEqual(f64),
    Range(String, String),
    NumericRange(f64, f64),
    DateEquals(DateMatch),
    DateAfter(DateMatch),
    DateBefore(DateMatch),
    DateRange(DateMatch, DateMatch),
    Boolean(bool),
    Service(ServiceType),
}

impl TermCondition {
    pub fn display_value(&self) -> String {
        match self {
            TermCondition::Equals(v)
            | TermCondition::Contains(v)
            | TermCondition::Prefix(v)
            | TermCondition::Suffix(v) => v.clone(),
            TermCondition::GreaterThan(n)
            | TermCondition::LessThan(n)
            | TermCondition::GreaterThanOrEqual(n)
            | TermCondition::LessThanOrEqual(n) => fmt_f64(*n),
            TermCondition::Range(a, b) => format!("{a}..{b}"),
            TermCondition::NumericRange(a, b) => format!("{}..{}", fmt_f64(*a), fmt_f64(*b)),
            TermCondition::DateEquals(d)
            | TermCondition::DateAfter(d)
            | TermCondition::DateBefore(d) => d.description(),
            TermCondition::DateRange(a, b) => format!("{}..{}", a.description(), b.description()),
            TermCondition::Boolean(v) => if *v { "yes" } else { "no" }.to_string(),
            TermCondition::Service(svc) => svc.raw_value().to_string(),
        }
    }

    pub fn requires_full_scan(&self) -> bool {
        matches!(self, TermCondition::Suffix(_) | TermCondition::Contains(_))
    }
}

/// Mirrors Swift `String(n)` for a `Double`: integral values print without a
/// decimal point (`14.0` → "14"), otherwise the shortest round-trippable form.
fn fmt_f64(n: f64) -> String {
    if n.fract() == 0.0 && n.is_finite() {
        format!("{}", n as i64)
    } else {
        let s = format!("{n}");
        s
    }
}

/// Parsed date value. Port of `DateMatch`.
#[derive(Debug, Clone, PartialEq)]
pub enum DateMatch {
    Specific(NaiveDate),
    Relative { days: i64 },
    Today,
    Yesterday,
    Year(i32),
    YearMonth(i32, u32),
}

impl DateMatch {
    pub fn description(&self) -> String {
        match self {
            DateMatch::Specific(date) => date.format("%Y-%m-%d").to_string(),
            DateMatch::Relative { days } => format!("{days}d"),
            DateMatch::Today => "today".to_string(),
            DateMatch::Yesterday => "yesterday".to_string(),
            DateMatch::Year(year) => year.to_string(),
            DateMatch::YearMonth(year, month) => format!("{year:04}-{month:02}"),
        }
    }

    /// Resolve to an absolute `[start, end)` range in local time, mirroring
    /// `DateMatch.resolve()` using `Calendar.current`.
    pub fn resolve(&self) -> (NaiveDateTime, NaiveDateTime) {
        let now = Local::now().naive_local();
        let start_of_day = |dt: NaiveDateTime| dt.date().and_hms_opt(0, 0, 0).unwrap();
        match self {
            DateMatch::Specific(date) => {
                let start = date.and_hms_opt(0, 0, 0).unwrap();
                (start, start + Duration::days(1))
            }
            DateMatch::Relative { days } => {
                let start = start_of_day(now - Duration::days(*days));
                (start, now)
            }
            DateMatch::Today => {
                let start = start_of_day(now);
                (start, start + Duration::days(1))
            }
            DateMatch::Yesterday => {
                let start = start_of_day(now - Duration::days(1));
                (start, start + Duration::days(1))
            }
            DateMatch::Year(year) => {
                let start = NaiveDate::from_ymd_opt(*year, 1, 1).unwrap().and_hms_opt(0, 0, 0).unwrap();
                let end = NaiveDate::from_ymd_opt(year + 1, 1, 1).unwrap().and_hms_opt(0, 0, 0).unwrap();
                (start, end)
            }
            DateMatch::YearMonth(year, month) => {
                let start = NaiveDate::from_ymd_opt(*year, *month, 1).unwrap().and_hms_opt(0, 0, 0).unwrap();
                let (ny, nm) = if *month == 12 { (year + 1, 1) } else { (*year, month + 1) };
                let end = NaiveDate::from_ymd_opt(ny, nm, 1).unwrap().and_hms_opt(0, 0, 0).unwrap();
                (start, end)
            }
        }
    }
}

/// Parse a `yyyy-MM-dd` string the way Foundation's `DateFormatter` does for the
/// query language (used by the parser's date handling).
pub(crate) fn parse_ymd(value: &str) -> Option<NaiveDate> {
    NaiveDate::parse_from_str(value, "%Y-%m-%d").ok()
}

/// Helper kept for symmetry with the Swift `Calendar`-based resolution; ensures
/// the `TimeZone`/`Local` imports are exercised even when `resolve` is unused.
#[allow(dead_code)]
pub(crate) fn local_midnight(date: NaiveDate) -> NaiveDateTime {
    Local
        .from_local_datetime(&date.and_hms_opt(0, 0, 0).unwrap())
        .single()
        .map(|dt| dt.naive_local())
        .unwrap_or_else(|| date.and_hms_opt(0, 0, 0).unwrap())
}
