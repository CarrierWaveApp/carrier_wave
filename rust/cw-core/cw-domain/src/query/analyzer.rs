//! Query performance analyzer. Port of `QueryAnalyzer.swift`.

use super::ast::{ParsedQuery, QueryExpression, QueryTerm, TermCondition};
use super::token::QueryField;

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub enum Severity {
    Hint = 0,
    Medium = 1,
    High = 2,
}

impl Severity {
    pub fn icon(self) -> &'static str {
        match self {
            Severity::Hint => "lightbulb",
            Severity::Medium => "bolt.fill",
            Severity::High => "exclamationmark.triangle.fill",
        }
    }
    pub fn color(self) -> &'static str {
        match self {
            Severity::Hint => "blue",
            Severity::Medium => "orange",
            Severity::High => "red",
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct QueryWarning {
    pub severity: Severity,
    pub message: String,
    pub suggestion: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub enum QueryCost {
    Indexed,
    Bounded,
    FullScan,
}

impl QueryCost {
    pub fn description(self) -> &'static str {
        match self {
            QueryCost::Indexed => "Fast (indexed)",
            QueryCost::Bounded => "Moderate (bounded scan)",
            QueryCost::FullScan => "Slow (full scan)",
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct QueryAnalysis {
    pub warnings: Vec<QueryWarning>,
    pub estimated_cost: QueryCost,
    pub uses_index: bool,
}

impl QueryAnalysis {
    pub fn should_warn(&self) -> bool {
        self.warnings.iter().any(|w| w.severity >= Severity::Medium)
    }
    pub fn requires_confirmation(&self) -> bool {
        self.warnings.iter().any(|w| w.severity >= Severity::High)
    }
    pub fn max_severity(&self) -> Option<Severity> {
        self.warnings.iter().map(|w| w.severity).max()
    }
}

pub struct QueryAnalyzer;

impl QueryAnalyzer {
    pub fn analyze(query: &ParsedQuery, qso_count: i64) -> QueryAnalysis {
        if query.is_empty() {
            return QueryAnalysis {
                warnings: vec![],
                estimated_cost: QueryCost::Indexed,
                uses_index: true,
            };
        }

        let terms = query.expression.all_terms();
        let (positive_terms, negated_terms) = categorize_terms(&query.expression);

        let uses_index = positive_terms
            .iter()
            .filter_map(|t| t.field)
            .any(|f| f.is_indexed());

        let mut warnings: Vec<QueryWarning> = Vec::new();
        warnings.extend(check_index_usage(uses_index, qso_count));
        warnings.extend(check_leading_wildcards(&terms));
        warnings.extend(check_negation_only(&positive_terms, &negated_terms));
        warnings.extend(check_text_scan_fields(&positive_terms));
        warnings.extend(check_substring_matching(&terms));

        let has_date_bound = positive_terms.iter().any(|t| {
            matches!(t.field, Some(QueryField::Date) | Some(QueryField::After) | Some(QueryField::Before))
        });

        warnings.extend(check_large_dataset(has_date_bound, qso_count, uses_index));
        warnings.extend(check_frequency_search(&terms, qso_count, has_date_bound));

        let cost = determine_cost(uses_index, has_date_bound);

        // Dedup by message (first occurrence wins), then sort by severity desc.
        let mut seen: Vec<String> = Vec::new();
        let mut unique: Vec<QueryWarning> = Vec::new();
        for warning in warnings {
            if !seen.contains(&warning.message) {
                seen.push(warning.message.clone());
                unique.push(warning);
            }
        }
        unique.sort_by_key(|warning| std::cmp::Reverse(warning.severity));

        QueryAnalysis { warnings: unique, estimated_cost: cost, uses_index }
    }
}

fn check_index_usage(uses_index: bool, qso_count: i64) -> Vec<QueryWarning> {
    if uses_index || qso_count <= 1_000 {
        return vec![];
    }
    vec![QueryWarning {
        severity: Severity::High,
        message: format!("This search scans all {} QSOs", grouped(qso_count)),
        suggestion: Some("Add a callsign, date, band, or mode filter".to_string()),
    }]
}

fn check_leading_wildcards(terms: &[QueryTerm]) -> Vec<QueryWarning> {
    terms
        .iter()
        .filter_map(|term| {
            if let TermCondition::Suffix(pattern) = &term.condition {
                Some(QueryWarning {
                    severity: Severity::High,
                    message: format!("Wildcard at start of '*{pattern}' can't use index"),
                    suggestion: Some(format!("Use trailing wildcard instead: '{pattern}*'")),
                })
            } else {
                None
            }
        })
        .collect()
}

fn check_negation_only(positive: &[QueryTerm], negated: &[QueryTerm]) -> Vec<QueryWarning> {
    if positive.is_empty() && negated.is_empty() {
        return vec![];
    }
    if !positive.is_empty() || negated.is_empty() {
        return vec![];
    }
    vec![QueryWarning {
        severity: Severity::High,
        message: "Exclusion-only query must scan all records".to_string(),
        suggestion: Some("Add a positive filter like a date range".to_string()),
    }]
}

fn check_text_scan_fields(positive: &[QueryTerm]) -> Vec<QueryWarning> {
    positive
        .iter()
        .filter_map(|term| {
            let field = term.field?;
            if field.requires_text_scan() {
                Some(QueryWarning {
                    severity: Severity::Medium,
                    message: format!("Searching '{}' scans all records", field.display_name()),
                    suggestion: None,
                })
            } else {
                None
            }
        })
        .collect()
}

fn check_substring_matching(terms: &[QueryTerm]) -> Vec<QueryWarning> {
    terms
        .iter()
        .filter_map(|term| {
            let field = term.field?;
            if field.requires_text_scan() {
                return None;
            }
            if let TermCondition::Contains(_) = &term.condition {
                Some(QueryWarning {
                    severity: Severity::Medium,
                    message: format!(
                        "Substring search on '{}' is slower than prefix",
                        field.display_name()
                    ),
                    suggestion: Some(format!("Use '{}*' for prefix match", term.condition.display_value())),
                })
            } else {
                None
            }
        })
        .collect()
}

fn check_large_dataset(has_date_bound: bool, qso_count: i64, uses_index: bool) -> Vec<QueryWarning> {
    if has_date_bound || qso_count <= 10_000 || !uses_index {
        return vec![];
    }
    vec![QueryWarning {
        severity: Severity::Hint,
        message: format!("Searching {} QSOs", grouped(qso_count)),
        suggestion: Some("Add 'after:30d' to search recent contacts only".to_string()),
    }]
}

fn check_frequency_search(terms: &[QueryTerm], qso_count: i64, has_date_bound: bool) -> Vec<QueryWarning> {
    let has_frequency = terms.iter().any(|t| t.field == Some(QueryField::Frequency));
    if !has_frequency || qso_count <= 5_000 || has_date_bound {
        return vec![];
    }
    vec![QueryWarning {
        severity: Severity::Medium,
        message: "Frequency searches may be slow on large datasets".to_string(),
        suggestion: Some("Add a date filter to reduce scan size".to_string()),
    }]
}

fn determine_cost(uses_index: bool, has_date_bound: bool) -> QueryCost {
    if uses_index {
        QueryCost::Indexed
    } else if has_date_bound {
        QueryCost::Bounded
    } else {
        QueryCost::FullScan
    }
}

fn categorize_terms(expression: &QueryExpression) -> (Vec<QueryTerm>, Vec<QueryTerm>) {
    let mut positive = Vec::new();
    let mut negated = Vec::new();

    fn walk(expr: &QueryExpression, is_negated: bool, positive: &mut Vec<QueryTerm>, negated: &mut Vec<QueryTerm>) {
        match expr {
            QueryExpression::Empty => {}
            QueryExpression::Term(term) => {
                if is_negated {
                    negated.push(term.clone());
                } else {
                    positive.push(term.clone());
                }
            }
            QueryExpression::And(exprs) | QueryExpression::Or(exprs) => {
                for e in exprs {
                    walk(e, is_negated, positive, negated);
                }
            }
            QueryExpression::Not(inner) => walk(inner, !is_negated, positive, negated),
        }
    }

    walk(expression, false, &mut positive, &mut negated);
    (positive, negated)
}

/// `Int.formatted()` for the en_US locale: thousands grouped with commas.
/// (Swift uses the current locale; en_US grouping is the common case.)
fn grouped(n: i64) -> String {
    let neg = n < 0;
    let digits = n.unsigned_abs().to_string();
    let bytes = digits.as_bytes();
    let mut out = String::new();
    let len = bytes.len();
    for (i, b) in bytes.iter().enumerate() {
        if i > 0 && (len - i) % 3 == 0 {
            out.push(',');
        }
        out.push(*b as char);
    }
    if neg {
        format!("-{out}")
    } else {
        out
    }
}
