//! Carrier Wave query language — the Phase-0 migration beachhead.
//!
//! Faithful port of `CarrierWaveCore/QueryLanguage/*`: lexer → parser → AST,
//! plus a performance analyzer. Pure, no I/O.
//!
//! ```
//! use cw_domain::query::{parse, QueryExpression, TermCondition};
//! let parsed = parse("band:20m mode:ft8").unwrap();
//! assert!(matches!(parsed.expression, QueryExpression::And(_)));
//! ```

pub mod analyzer;
pub mod ast;
pub mod error;
pub mod eval;
pub mod lexer;
pub mod parser;
pub mod token;

pub use analyzer::{QueryAnalysis, QueryAnalyzer, QueryCost, QueryWarning, Severity};
pub use ast::{DateMatch, ParsedQuery, QueryExpression, QueryTerm, TermCondition};
pub use error::QueryError;
pub use eval::{matches, QueryRow};
pub use lexer::QueryLexer;
pub use parser::QueryParser;
pub use token::{PositionedToken, QueryField, QueryToken, SourcePosition};

/// Convenience: lex + parse a query string into an AST.
pub fn parse(input: &str) -> Result<ParsedQuery, QueryError> {
    QueryParser::parse_str(input)
}

/// Convenience: parse + analyze in one call.
pub fn parse_and_analyze(input: &str, qso_count: i64) -> Result<QueryAnalysis, QueryError> {
    let parsed = parse(input)?;
    Ok(QueryAnalyzer::analyze(&parsed, qso_count))
}

#[cfg(test)]
mod tests;
