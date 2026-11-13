//! Query errors. Port of `QueryError`.

use super::token::SourcePosition;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum QueryError {
    UnknownField { field: String, suggestion: Option<String>, position: SourcePosition },
    UnterminatedString { position: SourcePosition },
    UnexpectedToken { expected: String, got: String, position: SourcePosition },
    InvalidDateFormat { value: String, position: SourcePosition },
    InvalidNumberFormat { value: String, position: SourcePosition },
    EmptyQuery,
    UnmatchedParenthesis { position: SourcePosition },
}

impl QueryError {
    pub fn message(&self) -> String {
        match self {
            QueryError::UnknownField { field, suggestion, .. } => match suggestion {
                Some(sug) => format!("Unknown field '{field}' - did you mean '{sug}'?"),
                None => format!("Unknown field '{field}'"),
            },
            QueryError::UnterminatedString { .. } => "Unterminated quoted string".to_string(),
            QueryError::UnexpectedToken { expected, got, .. } => {
                format!("Expected {expected}, got '{got}'")
            }
            QueryError::InvalidDateFormat { value, .. } => format!(
                "Invalid date format '{value}' - use YYYY-MM-DD, 'today', 'yesterday', or '7d'"
            ),
            QueryError::InvalidNumberFormat { value, .. } => format!("Invalid number '{value}'"),
            QueryError::EmptyQuery => "Empty query".to_string(),
            QueryError::UnmatchedParenthesis { .. } => "Unmatched parenthesis".to_string(),
        }
    }

    pub fn position(&self) -> SourcePosition {
        match self {
            QueryError::UnknownField { position, .. }
            | QueryError::UnterminatedString { position }
            | QueryError::UnexpectedToken { position, .. }
            | QueryError::InvalidDateFormat { position, .. }
            | QueryError::InvalidNumberFormat { position, .. }
            | QueryError::UnmatchedParenthesis { position } => *position,
            QueryError::EmptyQuery => SourcePosition::UNKNOWN,
        }
    }
}

impl std::fmt::Display for QueryError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.message())
    }
}

impl std::error::Error for QueryError {}
