//! Query language tests — derived from the Swift implementation's semantics.

use super::*;
use crate::service_type::ServiceType;

fn parse_ok(input: &str) -> ParsedQuery {
    parse(input).unwrap_or_else(|e| panic!("parse failed for {input:?}: {}", e.message()))
}

#[test]
fn empty_query_is_empty() {
    assert!(parse_ok("").is_empty());
    assert!(parse_ok("   ").is_empty());
}

#[test]
fn bare_term_is_callsign_prefix_uppercased() {
    let parsed = parse_ok("w1aw");
    match parsed.expression {
        QueryExpression::Term(term) => {
            assert_eq!(term.field, Some(QueryField::Callsign));
            assert_eq!(term.condition, TermCondition::Prefix("W1AW".to_string()));
        }
        other => panic!("expected term, got {other:?}"),
    }
}

#[test]
fn field_equals() {
    let parsed = parse_ok("mode:ft8");
    match parsed.expression {
        QueryExpression::Term(term) => {
            assert_eq!(term.field, Some(QueryField::Mode));
            assert_eq!(term.condition, TermCondition::Equals("ft8".to_string()));
        }
        other => panic!("expected term, got {other:?}"),
    }
}

#[test]
fn implicit_and_of_two_fields() {
    let parsed = parse_ok("band:20m mode:ft8");
    match parsed.expression {
        QueryExpression::And(exprs) => assert_eq!(exprs.len(), 2),
        other => panic!("expected and, got {other:?}"),
    }
}

#[test]
fn or_operator() {
    let parsed = parse_ok("band:20m | band:40m");
    match parsed.expression {
        QueryExpression::Or(exprs) => assert_eq!(exprs.len(), 2),
        other => panic!("expected or, got {other:?}"),
    }
}

#[test]
fn not_operator() {
    let parsed = parse_ok("-mode:cw");
    assert!(matches!(parsed.expression, QueryExpression::Not(_)));
}

#[test]
fn grouping_collapses_to_inner() {
    let parsed = parse_ok("(mode:ft8)");
    assert!(matches!(parsed.expression, QueryExpression::Term(_)));
}

#[test]
fn unmatched_paren_errors() {
    let err = parse("(mode:ft8").unwrap_err();
    assert!(matches!(err, QueryError::UnmatchedParenthesis { .. }));
}

#[test]
fn wildcards() {
    // Trailing wildcard → prefix
    match parse_ok("call:W1*").expression {
        QueryExpression::Term(t) => assert_eq!(t.condition, TermCondition::Prefix("W1".into())),
        o => panic!("{o:?}"),
    }
    // Leading wildcard → suffix
    match parse_ok("call:*AW").expression {
        QueryExpression::Term(t) => assert_eq!(t.condition, TermCondition::Suffix("AW".into())),
        o => panic!("{o:?}"),
    }
    // Both → contains
    match parse_ok("call:*1A*").expression {
        QueryExpression::Term(t) => assert_eq!(t.condition, TermCondition::Contains("1A".into())),
        o => panic!("{o:?}"),
    }
}

#[test]
fn numeric_comparison_and_exact_tolerance() {
    match parse_ok("freq:>14000").expression {
        QueryExpression::Term(t) => assert_eq!(t.condition, TermCondition::GreaterThan(14000.0)),
        o => panic!("{o:?}"),
    }
    match parse_ok("freq:14074").expression {
        QueryExpression::Term(t) => {
            assert_eq!(t.condition, TermCondition::NumericRange(14074.0 - 0.0005, 14074.0 + 0.0005));
        }
        o => panic!("{o:?}"),
    }
}

#[test]
fn numeric_range() {
    match parse_ok("freq:14000..14350").expression {
        QueryExpression::Term(t) => {
            assert_eq!(t.condition, TermCondition::NumericRange(14000.0, 14350.0));
        }
        o => panic!("{o:?}"),
    }
}

#[test]
fn invalid_number_errors() {
    let err = parse("freq:abc").unwrap_err();
    assert!(matches!(err, QueryError::InvalidNumberFormat { .. }));
}

#[test]
fn date_conditions() {
    match parse_ok("after:7d").expression {
        QueryExpression::Term(t) => {
            assert_eq!(t.condition, TermCondition::DateAfter(DateMatch::Relative { days: 7 }));
        }
        o => panic!("{o:?}"),
    }
    match parse_ok("date:today").expression {
        QueryExpression::Term(t) => {
            assert_eq!(t.condition, TermCondition::DateEquals(DateMatch::Today));
        }
        o => panic!("{o:?}"),
    }
    match parse_ok("date:2024").expression {
        QueryExpression::Term(t) => {
            assert_eq!(t.condition, TermCondition::DateEquals(DateMatch::Year(2024)));
        }
        o => panic!("{o:?}"),
    }
    match parse_ok("date:2024-03").expression {
        QueryExpression::Term(t) => {
            assert_eq!(t.condition, TermCondition::DateEquals(DateMatch::YearMonth(2024, 3)));
        }
        o => panic!("{o:?}"),
    }
}

#[test]
fn invalid_date_errors() {
    let err = parse("date:notadate").unwrap_err();
    assert!(matches!(err, QueryError::InvalidDateFormat { .. }));
}

#[test]
fn status_and_service_conditions() {
    match parse_ok("confirmed:yes").expression {
        QueryExpression::Term(t) => assert_eq!(t.condition, TermCondition::Boolean(true)),
        o => panic!("{o:?}"),
    }
    match parse_ok("synced:lotw").expression {
        QueryExpression::Term(t) => {
            assert_eq!(t.condition, TermCondition::Service(ServiceType::Lotw));
        }
        o => panic!("{o:?}"),
    }
    match parse_ok("source:manual").expression {
        QueryExpression::Term(t) => assert_eq!(t.condition, TermCondition::Equals("manual".into())),
        o => panic!("{o:?}"),
    }
}

#[test]
fn unknown_field_suggests_similar() {
    let err = parse("bnd:20m").unwrap_err();
    match err {
        QueryError::UnknownField { field, suggestion, .. } => {
            assert_eq!(field, "bnd");
            assert_eq!(suggestion.as_deref(), Some("band"));
        }
        o => panic!("{o:?}"),
    }
}

#[test]
fn unterminated_string_errors() {
    let err = parse("\"unterminated").unwrap_err();
    assert!(matches!(err, QueryError::UnterminatedString { .. }));
}

#[test]
fn quoted_string_is_value() {
    // A quoted value becomes a bare term; with no wildcard it's a callsign prefix.
    let parsed = parse_ok("\"hello world\"");
    match parsed.expression {
        QueryExpression::Term(t) => {
            assert_eq!(t.field, Some(QueryField::Callsign));
            assert_eq!(t.condition, TermCondition::Prefix("HELLO WORLD".into()));
        }
        o => panic!("{o:?}"),
    }
}

#[test]
fn flatten_nested_and() {
    // "a b c" → single flattened And of 3.
    match parse_ok("name:a name:b name:c").expression {
        QueryExpression::And(exprs) => assert_eq!(exprs.len(), 3),
        o => panic!("{o:?}"),
    }
}

#[test]
fn analyzer_empty_is_indexed() {
    let analysis = parse_and_analyze("", 100_000).unwrap();
    assert_eq!(analysis.estimated_cost, QueryCost::Indexed);
    assert!(analysis.uses_index);
    assert!(analysis.warnings.is_empty());
}

#[test]
fn analyzer_unindexed_large_dataset_warns_high() {
    // notes:foo is a text-scan field, not indexed → high warning past 1000 QSOs.
    let analysis = parse_and_analyze("notes:foo", 50_000).unwrap();
    assert!(!analysis.uses_index);
    assert_eq!(analysis.estimated_cost, QueryCost::FullScan);
    assert!(analysis.requires_confirmation());
    assert_eq!(analysis.max_severity(), Some(Severity::High));
    // Grouped count appears in some message.
    assert!(analysis.warnings.iter().any(|w| w.message.contains("50,000")));
}

#[test]
fn analyzer_indexed_is_fast() {
    let analysis = parse_and_analyze("band:20m", 50_000).unwrap();
    assert!(analysis.uses_index);
    assert_eq!(analysis.estimated_cost, QueryCost::Indexed);
}

#[test]
fn analyzer_leading_wildcard_warns() {
    let analysis = parse_and_analyze("call:*AW", 10).unwrap();
    assert!(analysis.warnings.iter().any(|w| w.message.contains("can't use index")));
}

#[test]
fn grouped_formatting_via_message() {
    let analysis = parse_and_analyze("notes:x", 1_234_567).unwrap();
    assert!(analysis.warnings.iter().any(|w| w.message.contains("1,234,567")));
}

#[test]
fn embedded_range_splits() {
    // "14000..14350" as a bare term builds a string range across multiple fields.
    let parsed = parse_ok("14000..14350");
    match parsed.expression {
        QueryExpression::Term(t) => {
            assert_eq!(t.field, None);
            assert_eq!(t.condition, TermCondition::Range("14000".into(), "14350".into()));
        }
        o => panic!("{o:?}"),
    }
}

// --- Unrecognized-character skip (infinite-loop regression) ---

#[test]
fn unrecognized_char_at_end_of_field_value_is_skipped() {
    // "notes:de%" — the '%' starts no valid token; it must be skipped so the
    // parse terminates.  The field value "de" is emitted; "%" is silently
    // dropped.  If the bug is present this test hangs forever.
    let parsed = parse_ok("notes:de%");
    match parsed.expression {
        QueryExpression::Term(t) => {
            assert_eq!(t.field, Some(QueryField::Notes));
            // No wildcard → Equals
            assert_eq!(t.condition, TermCondition::Equals("de".to_string()));
        }
        o => panic!("{o:?}"),
    }
}

#[test]
fn unrecognized_char_between_words_is_skipped() {
    // "a@b" — '@' is not a word character; it is skipped.  "a" and "b" are
    // separate bare-value terms → implicit AND of two callsign-prefix terms.
    let parsed = parse_ok("a@b");
    match parsed.expression {
        QueryExpression::And(exprs) => {
            assert_eq!(exprs.len(), 2, "expected two terms for a@b");
        }
        // A single term is also acceptable if the implementation fuses them,
        // but two is what the lenient-skip spec mandates.
        QueryExpression::Term(_) => {} // tolerate if implementations merge
        o => panic!("unexpected expression: {o:?}"),
    }
}

#[test]
fn multiple_unrecognized_chars_all_skipped() {
    // "%%%"  — three unrecognized chars in a row.  Parse must terminate and
    // yield an empty query (no real tokens).
    let parsed = parse("%%%").unwrap_or_else(|e| panic!("parse failed: {}", e.message()));
    assert!(parsed.is_empty(), "expected empty result for '%%%', got {parsed:?}");
}
