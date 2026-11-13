//! Query parser + condition building. Ports `QueryParser.swift`,
//! `QueryParser+FieldTerms.swift`, `QueryParser+Conditions.swift`.

use super::ast::{parse_ymd, DateMatch, ParsedQuery, QueryExpression, QueryTerm, TermCondition};
use super::error::QueryError;
use super::lexer::QueryLexer;
use super::token::{PositionedToken, QueryField, QueryToken, SourcePosition};
use crate::service_type::ServiceType;

pub struct QueryParser {
    tokens: Vec<PositionedToken>,
    index: usize,
}

impl QueryParser {
    pub fn new(tokens: Vec<PositionedToken>) -> Self {
        QueryParser { tokens, index: 0 }
    }

    /// Convenience: parse a string directly (lex + parse).
    pub fn parse_str(input: &str) -> Result<ParsedQuery, QueryError> {
        let tokens = QueryLexer::new(input).tokenize()?;
        QueryParser::new(tokens).parse()
    }

    pub fn parse(&mut self) -> Result<ParsedQuery, QueryError> {
        if self.tokens.is_empty()
            || (self.tokens.len() == 1 && self.tokens[0].token == QueryToken::Eof)
        {
            return Ok(ParsedQuery::new(QueryExpression::Empty, ""));
        }

        let expr = self.parse_expression()?;
        let source_text = self.tokens[..self.tokens.len().saturating_sub(1)]
            .iter()
            .map(|t| t.raw_text.clone())
            .collect::<Vec<_>>()
            .join(" ");
        Ok(ParsedQuery::new(expr.flattened(), source_text))
    }

    fn is_at_end(&self) -> bool {
        self.index >= self.tokens.len() || self.tokens[self.index].token == QueryToken::Eof
    }

    fn peek(&self) -> Option<&PositionedToken> {
        self.tokens.get(self.index)
    }

    fn peek_token(&self) -> Option<QueryToken> {
        self.peek().map(|pt| pt.token.clone())
    }

    fn advance(&mut self) -> Option<PositionedToken> {
        if self.is_at_end() {
            return None;
        }
        let token = self.tokens[self.index].clone();
        self.index += 1;
        Some(token)
    }

    fn parse_expression(&mut self) -> Result<QueryExpression, QueryError> {
        self.parse_or()
    }

    fn parse_or(&mut self) -> Result<QueryExpression, QueryError> {
        let mut terms = vec![self.parse_and()?];
        while self.peek_token() == Some(QueryToken::Or) {
            self.advance();
            terms.push(self.parse_and()?);
        }
        if terms.len() == 1 {
            Ok(terms.into_iter().next().unwrap())
        } else {
            Ok(QueryExpression::Or(terms))
        }
    }

    fn parse_and(&mut self) -> Result<QueryExpression, QueryError> {
        let mut terms: Vec<QueryExpression> = Vec::new();
        while !self.is_at_end()
            && self.peek_token() != Some(QueryToken::Or)
            && self.peek_token() != Some(QueryToken::CloseParen)
        {
            terms.push(self.parse_unary()?);
        }
        if terms.is_empty() {
            Ok(QueryExpression::Empty)
        } else if terms.len() == 1 {
            Ok(terms.into_iter().next().unwrap())
        } else {
            Ok(QueryExpression::And(terms))
        }
    }

    fn parse_unary(&mut self) -> Result<QueryExpression, QueryError> {
        if self.peek_token() == Some(QueryToken::Not) {
            self.advance();
            let inner = self.parse_primary()?;
            return Ok(QueryExpression::Not(Box::new(inner)));
        }
        self.parse_primary()
    }

    fn parse_primary(&mut self) -> Result<QueryExpression, QueryError> {
        let token = match self.peek() {
            Some(t) => t.clone(),
            None => return Ok(QueryExpression::Empty),
        };

        match token.token {
            QueryToken::OpenParen => self.parse_group(),
            QueryToken::Field(field) => self.parse_field_term(field, token.position),
            QueryToken::Value(value) => {
                self.advance();
                self.parse_bare_term(&value, token.position)
            }
            QueryToken::Eof => Ok(QueryExpression::Empty),
            _ => Err(QueryError::UnexpectedToken {
                expected: "search term".to_string(),
                got: token.raw_text,
                position: token.position,
            }),
        }
    }

    fn parse_group(&mut self) -> Result<QueryExpression, QueryError> {
        let open_paren = self.advance().unwrap();
        let inner = self.parse_expression()?;
        if self.peek_token() == Some(QueryToken::CloseParen) {
            self.advance();
            Ok(inner)
        } else {
            Err(QueryError::UnmatchedParenthesis { position: open_paren.position })
        }
    }

    // ----- Field terms (QueryParser+FieldTerms.swift) -----

    fn parse_field_term(
        &mut self,
        field: QueryField,
        position: SourcePosition,
    ) -> Result<QueryExpression, QueryError> {
        self.advance(); // consume field token

        let mut comparison: Option<QueryToken> = None;
        if let Some(token) = self.peek_token() {
            match token {
                QueryToken::GreaterThan
                | QueryToken::LessThan
                | QueryToken::GreaterThanOrEqual
                | QueryToken::LessThanOrEqual => {
                    comparison = Some(token);
                    self.advance();
                }
                _ => {}
            }
        }

        let value_token = match self.peek() {
            Some(pt) => pt.clone(),
            None => {
                return Err(QueryError::UnexpectedToken {
                    expected: "value".to_string(),
                    got: "end of input".to_string(),
                    position,
                })
            }
        };
        let value = match &value_token.token {
            QueryToken::Value(v) => v.clone(),
            _ => {
                return Err(QueryError::UnexpectedToken {
                    expected: "value".to_string(),
                    got: value_token.raw_text.clone(),
                    position: value_token.position,
                })
            }
        };
        self.advance();

        let mut end_value: Option<String> = None;
        if self.peek_token() == Some(QueryToken::Range) {
            self.advance();
            if let Some(end_token) = self.peek() {
                if let QueryToken::Value(end) = &end_token.token {
                    let end = end.clone();
                    self.advance();
                    end_value = Some(end);
                }
            }
        }

        let condition = self.build_condition(
            field,
            &value,
            end_value.as_deref(),
            comparison.as_ref(),
            value_token.position,
        )?;
        Ok(QueryExpression::Term(QueryTerm { field: Some(field), condition, position }))
    }

    fn parse_bare_term(
        &mut self,
        value: &str,
        position: SourcePosition,
    ) -> Result<QueryExpression, QueryError> {
        let mut end_value: Option<String> = None;
        if self.peek_token() == Some(QueryToken::Range) {
            self.advance();
            if let Some(end_token) = self.peek() {
                if let QueryToken::Value(end) = &end_token.token {
                    let end = end.clone();
                    self.advance();
                    end_value = Some(end);
                }
            }
        }

        // Bare terms without wildcards/ranges are implicit callsign prefix searches.
        if end_value.is_none() && !value.contains('*') {
            return Ok(QueryExpression::Term(QueryTerm {
                field: Some(QueryField::Callsign),
                condition: TermCondition::Prefix(value.to_uppercase()),
                position,
            }));
        }

        let condition = build_bare_term_condition(value, end_value.as_deref());
        Ok(QueryExpression::Term(QueryTerm { field: None, condition, position }))
    }

    // ----- Conditions (QueryParser+Conditions.swift) -----

    fn build_condition(
        &self,
        field: QueryField,
        value: &str,
        end_value: Option<&str>,
        comparison: Option<&QueryToken>,
        position: SourcePosition,
    ) -> Result<TermCondition, QueryError> {
        use QueryField::*;

        if field == Date || field == After || field == Before {
            return build_date_condition(field, value, end_value, position);
        }
        if field == Frequency || field == Power || field == Dxcc {
            return build_numeric_condition(value, end_value, comparison, position);
        }
        if field == Confirmed || field == Synced || field == Pending {
            return build_status_condition(value, position);
        }
        if field == Source {
            return build_source_condition(value, position);
        }

        if let Some(end_value) = end_value {
            return Ok(TermCondition::Range(value.to_string(), end_value.to_string()));
        }

        if value.contains('*') {
            if value.starts_with('*') && value.ends_with('*') {
                let inner: String = value.chars().skip(1).take(value.chars().count() - 2).collect();
                return Ok(TermCondition::Contains(inner));
            } else if let Some(rest) = value.strip_prefix('*') {
                return Ok(TermCondition::Suffix(rest.to_string()));
            } else if let Some(rest) = value.strip_suffix('*') {
                return Ok(TermCondition::Prefix(rest.to_string()));
            }
        }

        Ok(TermCondition::Equals(value.to_string()))
    }
}

fn build_date_condition(
    field: QueryField,
    value: &str,
    end_value: Option<&str>,
    position: SourcePosition,
) -> Result<TermCondition, QueryError> {
    let date_match = parse_date_value(value)
        .ok_or_else(|| QueryError::InvalidDateFormat { value: value.to_string(), position })?;

    if let Some(end_value) = end_value {
        let end_match = parse_date_value(end_value).ok_or_else(|| {
            QueryError::InvalidDateFormat { value: end_value.to_string(), position }
        })?;
        return Ok(TermCondition::DateRange(date_match, end_match));
    }

    Ok(match field {
        QueryField::After => TermCondition::DateAfter(date_match),
        QueryField::Before => TermCondition::DateBefore(date_match),
        _ => TermCondition::DateEquals(date_match),
    })
}

fn build_numeric_condition(
    value: &str,
    end_value: Option<&str>,
    comparison: Option<&QueryToken>,
    position: SourcePosition,
) -> Result<TermCondition, QueryError> {
    let number = parse_double(value)
        .ok_or_else(|| QueryError::InvalidNumberFormat { value: value.to_string(), position })?;

    if let Some(end_value) = end_value {
        let end_number = parse_double(end_value).ok_or_else(|| {
            QueryError::InvalidNumberFormat { value: end_value.to_string(), position }
        })?;
        return Ok(TermCondition::NumericRange(number, end_number));
    }

    if let Some(comparison) = comparison {
        match comparison {
            QueryToken::GreaterThan => return Ok(TermCondition::GreaterThan(number)),
            QueryToken::LessThan => return Ok(TermCondition::LessThan(number)),
            QueryToken::GreaterThanOrEqual => {
                return Ok(TermCondition::GreaterThanOrEqual(number))
            }
            QueryToken::LessThanOrEqual => return Ok(TermCondition::LessThanOrEqual(number)),
            _ => {}
        }
    }

    Ok(TermCondition::NumericRange(number - 0.0005, number + 0.0005))
}

fn build_status_condition(
    value: &str,
    position: SourcePosition,
) -> Result<TermCondition, QueryError> {
    let lowered = value.to_lowercase();
    if lowered == "yes" || lowered == "true" || lowered == "1" {
        return Ok(TermCondition::Boolean(true));
    }
    if lowered == "no" || lowered == "false" || lowered == "0" {
        return Ok(TermCondition::Boolean(false));
    }
    if let Some(service) = ServiceType::from_raw_value(&lowered) {
        return Ok(TermCondition::Service(service));
    }
    match lowered.as_str() {
        "lotw" | "logbookoftheworld" => Ok(TermCondition::Service(ServiceType::Lotw)),
        "qrz" => Ok(TermCondition::Service(ServiceType::Qrz)),
        "pota" => Ok(TermCondition::Service(ServiceType::Pota)),
        "lofi" | "ham2k" => Ok(TermCondition::Service(ServiceType::Lofi)),
        "hamrs" => Ok(TermCondition::Service(ServiceType::Hamrs)),
        "clublog" | "club log" => Ok(TermCondition::Service(ServiceType::Clublog)),
        _ => Err(QueryError::UnexpectedToken {
            expected: "yes/no or service name (lotw, qrz, pota, lofi, hamrs, clublog)".to_string(),
            got: value.to_string(),
            position,
        }),
    }
}

fn build_source_condition(
    value: &str,
    position: SourcePosition,
) -> Result<TermCondition, QueryError> {
    let lowered = value.to_lowercase();
    match lowered.as_str() {
        "lotw" | "logbookoftheworld" => Ok(TermCondition::Service(ServiceType::Lotw)),
        "qrz" => Ok(TermCondition::Service(ServiceType::Qrz)),
        "pota" => Ok(TermCondition::Service(ServiceType::Pota)),
        "lofi" | "ham2k" => Ok(TermCondition::Service(ServiceType::Lofi)),
        "hamrs" => Ok(TermCondition::Service(ServiceType::Hamrs)),
        "clublog" | "club log" => Ok(TermCondition::Service(ServiceType::Clublog)),
        "manual" | "local" => Ok(TermCondition::Equals("manual".to_string())),
        _ => Err(QueryError::UnexpectedToken {
            expected: "source name (lotw, qrz, pota, lofi, hamrs, clublog, manual)".to_string(),
            got: value.to_string(),
            position,
        }),
    }
}

fn build_bare_term_condition(value: &str, end_value: Option<&str>) -> TermCondition {
    if let Some(end_value) = end_value {
        return TermCondition::Range(value.to_string(), end_value.to_string());
    }
    if value.contains('*') {
        if value.starts_with('*') && value.ends_with('*') {
            let inner: String = value.chars().skip(1).take(value.chars().count() - 2).collect();
            return TermCondition::Contains(inner);
        } else if let Some(rest) = value.strip_prefix('*') {
            return TermCondition::Suffix(rest.to_string());
        } else if let Some(rest) = value.strip_suffix('*') {
            return TermCondition::Prefix(rest.to_string());
        }
    }
    TermCondition::Contains(value.to_string())
}

fn parse_date_value(value: &str) -> Option<DateMatch> {
    let lowered = value.to_lowercase();
    if lowered == "today" {
        return Some(DateMatch::Today);
    }
    if lowered == "yesterday" {
        return Some(DateMatch::Yesterday);
    }
    if let Some(rest) = lowered.strip_suffix('d') {
        if let Ok(days) = rest.parse::<i64>() {
            return Some(DateMatch::Relative { days });
        }
    }
    if let Some(rest) = lowered.strip_suffix('m') {
        if let Ok(months) = rest.parse::<i64>() {
            return Some(DateMatch::Relative { days: months * 30 });
        }
    }
    if value.chars().count() == 4 {
        if let Ok(year) = value.parse::<i32>() {
            return Some(DateMatch::Year(year));
        }
    }
    if value.chars().count() == 7 && value.contains('-') {
        let parts: Vec<&str> = value.split('-').collect();
        if parts.len() == 2 {
            if let (Ok(year), Ok(month)) = (parts[0].parse::<i32>(), parts[1].parse::<u32>()) {
                return Some(DateMatch::YearMonth(year, month));
            }
        }
    }
    parse_ymd(value).map(DateMatch::Specific)
}

/// Mirror Swift `Double(_:)` string parsing closely enough for query values:
/// trims nothing, accepts decimal and scientific notation, rejects junk.
fn parse_double(value: &str) -> Option<f64> {
    // Swift's `Double("12")` works; Rust `"12".parse::<f64>()` works too.
    // Reject the special strings `inf`/`nan` that Rust accepts but a query value
    // never legitimately means, to stay closer to user intent.
    let v = value.trim();
    if v.is_empty() {
        return None;
    }
    match v.parse::<f64>() {
        Ok(n) if n.is_finite() => Some(n),
        _ => None,
    }
}
