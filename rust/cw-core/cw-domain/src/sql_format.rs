//! SQL pretty-printer for the query workbench's Format button. Port of
//! Sweep's `SQLFormatter.swift`.
//!
//! Walks a tokenized stream with a paren-context stack so subqueries,
//! function calls, and CASE expressions all indent properly. Not a full
//! sqlfluff — no rule-based linting, no dialect tables — but output is
//! stable across re-runs (idempotent) and handles the shapes a workbench
//! user actually writes: SELECT lists, WHERE/HAVING AND/OR chains,
//! JOIN … ON, UNION, CTEs, subqueries in FROM/IN/EXISTS, CASE expressions.

/// Format a SQL string. Entry point matching `SQLFormatter.format`.
pub fn format_sql(sql: &str) -> String {
    let tokens: Vec<Token> = tokenize(sql)
        .into_iter()
        .filter(|token| !matches!(token, Token::Whitespace))
        .collect();
    let mut emitter = Emitter::new(tokens);
    emitter.run();
    emitter.output.trim().to_string()
}

// ---- Tokens -----------------------------------------------------------------

#[derive(Debug, Clone, PartialEq)]
enum Token {
    /// Identifier or keyword (keywords folded to uppercase).
    Word(String),
    /// `(` `)` `,` `;` `*` `!=` `->>` …
    Symbol(String),
    /// `'foo'` / `"foo"` / `` `foo` ``.
    StringLiteral(String),
    /// `-- …` or `/* … */`.
    Comment(String),
    Whitespace,
}

/// Words we uppercase and treat as keywords during reflow.
const KEYWORDS: [&str; 53] = [
    "SELECT", "FROM", "WHERE", "AND", "OR", "NOT", "IN", "LIKE",
    "BETWEEN", "IS", "NULL", "AS", "ASC", "DESC", "ON", "USING",
    "JOIN", "INNER", "LEFT", "RIGHT", "FULL", "OUTER", "CROSS",
    "GROUP", "BY", "ORDER", "HAVING", "LIMIT", "OFFSET",
    "UNION", "ALL", "INTERSECT", "EXCEPT", "DISTINCT",
    "WITH", "RECURSIVE", "VALUES", "RETURNING",
    "CASE", "WHEN", "THEN", "ELSE", "END", "EXISTS",
    "INSERT", "INTO", "UPDATE", "DELETE", "SET",
    "COUNT", "SUM", "AVG", "MIN",
];
// ("MAX", "CAST", "OVER", "PARTITION", "WINDOW" continue below — const
// arrays need a fixed length, so the tail lives in KEYWORDS_TAIL.)
const KEYWORDS_TAIL: [&str; 5] = ["MAX", "CAST", "OVER", "PARTITION", "WINDOW"];

fn is_keyword(upper: &str) -> bool {
    KEYWORDS.contains(&upper) || KEYWORDS_TAIL.contains(&upper)
}

/// Major clauses that start a new line at the current frame's base indent.
const MAJOR_CLAUSES: [&str; 15] = [
    "SELECT", "FROM", "WHERE", "GROUP BY", "HAVING", "ORDER BY",
    "LIMIT", "OFFSET", "UNION", "UNION ALL", "INTERSECT", "EXCEPT",
    "WITH", "VALUES", "RETURNING",
];

/// Multi-word JOIN heads that act like a single clause keyword.
const JOIN_CLAUSES: [&str; 9] = [
    "JOIN", "INNER JOIN", "LEFT JOIN", "RIGHT JOIN", "FULL JOIN",
    "CROSS JOIN", "LEFT OUTER JOIN", "RIGHT OUTER JOIN", "FULL OUTER JOIN",
];

/// Clauses whose body is a series of items — each item gets its own line at
/// the body indent.
const LIST_STYLE_CLAUSES: [&str; 9] = [
    "SELECT", "FROM", "WHERE", "HAVING",
    "GROUP BY", "ORDER BY", "VALUES", "RETURNING", "WITH",
];

// ---- Emitter -----------------------------------------------------------------

/// What the *body* of an open frame represents — controls how commas and
/// AND/OR are broken.
#[derive(Debug, Clone, Copy, PartialEq)]
enum FrameMode {
    Top,
    SelectList,
    FromList,
    Condition,
    ItemList,
    FunctionCall,
    Subquery,
    ParenList,
    CaseExpression,
}

#[derive(Debug, Clone, Copy)]
struct Frame {
    indent: usize,
    mode: FrameMode,
}

impl Frame {
    fn item_indent(&self) -> usize {
        self.indent + 1
    }
}

struct Emitter {
    tokens: Vec<Token>,
    output: String,
    stack: Vec<Frame>,
    index: usize,
    at_line_start: bool,
    stick_to_prev: bool,
}

impl Emitter {
    fn new(tokens: Vec<Token>) -> Emitter {
        Emitter {
            tokens,
            output: String::new(),
            stack: vec![Frame { indent: 0, mode: FrameMode::Top }],
            index: 0,
            at_line_start: true,
            stick_to_prev: false,
        }
    }

    fn run(&mut self) {
        while self.index < self.tokens.len() {
            self.step();
        }
    }

    fn current_indent(&self) -> usize {
        self.stack.last().map(|frame| frame.indent).unwrap_or(0)
    }

    fn step(&mut self) {
        match self.tokens[self.index].clone() {
            Token::Word(text) => self.handle_word(&text),
            Token::Symbol(text) => self.handle_symbol(&text),
            Token::StringLiteral(text) => {
                self.emit_inline(&text);
                self.index += 1;
            }
            Token::Comment(text) => {
                if !self.at_line_start && !self.output.ends_with(' ') {
                    self.output.push(' ');
                }
                self.output.push_str(&text);
                self.at_line_start = false;
                self.stick_to_prev = false;
                self.index += 1;
            }
            Token::Whitespace => {
                self.index += 1;
            }
        }
    }

    // ---- Word handling ----

    fn handle_word(&mut self, word: &str) {
        let upper = word.to_uppercase();

        // Try multi-word major clause / JOIN first.
        if let Some((text, consumed)) = self.match_clause(self.index) {
            self.emit_clause(&text, consumed);
            return;
        }

        // Top-of-frame keywords that flip frame mode (e.g. bare ON).
        if let Some(mode) = frame_mode_for_clause(&upper) {
            self.apply_clause_frame_mode(mode);
        }

        // CASE / WHEN / THEN / ELSE / END
        if upper == "CASE" {
            self.emit_inline(word);
            let indent = self.current_indent();
            self.stack.push(Frame { indent, mode: FrameMode::CaseExpression });
            self.index += 1;
            return;
        }
        if upper == "END" {
            if let Some(frame) = self.stack.last().copied() {
                if frame.mode == FrameMode::CaseExpression {
                    self.emit_on_new_line(frame.indent, word);
                    self.stack.pop();
                    self.index += 1;
                    return;
                }
            }
        }
        if matches!(upper.as_str(), "WHEN" | "ELSE") {
            if let Some(frame) = self.stack.last().copied() {
                if frame.mode == FrameMode::CaseExpression {
                    self.emit_on_new_line(frame.item_indent(), word);
                    self.index += 1;
                    return;
                }
            }
        }
        if upper == "THEN" {
            if let Some(frame) = self.stack.last() {
                if frame.mode == FrameMode::CaseExpression {
                    self.emit_inline(word);
                    self.index += 1;
                    return;
                }
            }
        }

        // Top-level AND / OR inside a condition frame breaks.
        if matches!(upper.as_str(), "AND" | "OR") {
            if let Some(frame) = self.stack.last().copied() {
                if frame.mode == FrameMode::Condition {
                    self.emit_on_new_line(frame.item_indent(), word);
                    self.index += 1;
                    return;
                }
            }
        }

        self.emit_inline(word);
        self.index += 1;
    }

    /// Multi-word clause heads (GROUP BY / UNION ALL / LEFT JOIN / …) match
    /// up front so they emit as one clause rather than separate words.
    fn match_clause(&self, idx: usize) -> Option<(String, usize)> {
        let Token::Word(first) = self.tokens.get(idx)? else {
            return None;
        };
        let first_up = first.to_uppercase();

        // Three-word JOIN heads (LEFT OUTER JOIN, etc.).
        if let Some((two_text, two_after)) = self.peek_word(idx) {
            if let Some((three_text, three_after)) = self.peek_word(two_after - 1) {
                let tri = format!("{first_up} {two_text} {three_text}");
                if JOIN_CLAUSES.contains(&tri.as_str()) {
                    return Some((tri, three_after - idx));
                }
            }
            // Two-word combos (GROUP BY, INNER JOIN, UNION ALL).
            let combined = format!("{first_up} {two_text}");
            if MAJOR_CLAUSES.contains(&combined.as_str())
                || JOIN_CLAUSES.contains(&combined.as_str())
            {
                return Some((combined, two_after - idx));
            }
        }
        // One-word major clause / bare JOIN.
        if MAJOR_CLAUSES.contains(&first_up.as_str()) || first_up == "JOIN" {
            return Some((first_up, 1));
        }
        None
    }

    /// Next word token after `idx`, skipping comments (Swift `peekWord`);
    /// returns the uppercased text and the index just past it.
    fn peek_word(&self, idx: usize) -> Option<(String, usize)> {
        let mut cursor = idx + 1;
        while cursor < self.tokens.len() {
            match &self.tokens[cursor] {
                Token::Word(text) => return Some((text.to_uppercase(), cursor + 1)),
                Token::Comment(_) => cursor += 1,
                _ => return None,
            }
        }
        None
    }

    // ---- Clause emission ----

    fn emit_clause(&mut self, text: &str, consumed: usize) {
        let Some(frame) = self.stack.last().copied() else {
            return;
        };
        let upper = text.to_uppercase();

        // JOINs nest one level under FROM (sqlfluff "indented_joins").
        let emit_at = if is_join_clause(&upper) { frame.item_indent() } else { frame.indent };
        self.emit_on_new_line(emit_at, text);
        self.index += consumed;

        if let Some(mode) = frame_mode_for_clause(&upper) {
            self.apply_clause_frame_mode(mode);
        }

        if LIST_STYLE_CLAUSES.contains(&upper.as_str()) {
            if let Some(updated) = self.stack.last().copied() {
                self.output.push('\n');
                self.output.push_str(&indent_string(updated.item_indent()));
                self.at_line_start = true;
                self.stick_to_prev = false;
            }
        }
    }

    fn apply_clause_frame_mode(&mut self, mode: FrameMode) {
        if let Some(frame) = self.stack.last_mut() {
            frame.mode = mode;
        }
    }

    // ---- Symbol handling ----

    fn handle_symbol(&mut self, symbol: &str) {
        match symbol {
            "(" => self.handle_open_paren(),
            ")" => self.handle_close_paren(),
            "," => self.handle_comma(),
            ";" => {
                if self.output.ends_with(' ') {
                    self.output.pop();
                }
                self.output.push_str(";\n");
                self.at_line_start = true;
                self.stick_to_prev = false;
                self.index += 1;
            }
            _ => {
                self.emit_inline(symbol);
                self.index += 1;
            }
        }
    }

    fn handle_open_paren(&mut self) {
        // Subquery detection runs FIRST — `IN (SELECT …)` / `EXISTS (SELECT …)`
        // must indent even though IN/EXISTS look like identifier suffixes.
        let is_subquery = self.next_word_is_clause_start();
        let is_function_call = !is_subquery && self.previous_non_whitespace_is_identifier();

        self.output.push('(');
        self.at_line_start = false;
        self.stick_to_prev = true;
        self.index += 1;

        let indent = self.current_indent();
        if is_function_call {
            self.stack.push(Frame { indent, mode: FrameMode::FunctionCall });
            return;
        }
        let mode = if is_subquery { FrameMode::Subquery } else { FrameMode::ParenList };
        self.stack.push(Frame { indent: indent + 1, mode });
    }

    fn handle_close_paren(&mut self) {
        let popped = self.stack.pop();
        // Subqueries close on a dedented new line for readability.
        if popped.map(|frame| frame.mode) == Some(FrameMode::Subquery) {
            if let Some(frame) = self.stack.last() {
                self.output.push('\n');
                self.output.push_str(&indent_string(frame.indent));
                self.at_line_start = true;
            }
        }
        if self.output.ends_with(' ') {
            self.output.pop();
        }
        self.output.push(')');
        self.at_line_start = false;
        self.stick_to_prev = false;
        self.index += 1;
    }

    fn handle_comma(&mut self) {
        if self.output.ends_with(' ') {
            self.output.pop();
        }
        self.output.push(',');
        match self.stack.last().map(|frame| frame.mode) {
            Some(FrameMode::FunctionCall) | Some(FrameMode::Top) | None => {
                self.output.push(' ');
                self.at_line_start = false;
            }
            Some(_) => {
                if let Some(frame) = self.stack.last().copied() {
                    self.output.push('\n');
                    self.output.push_str(&indent_string(frame.item_indent()));
                    self.at_line_start = true;
                }
            }
        }
        self.stick_to_prev = false;
        self.index += 1;
    }

    // ---- Emit primitives ----

    fn emit_inline(&mut self, text: &str) {
        if self.at_line_start || self.stick_to_prev {
            self.output.push_str(text);
        } else {
            if !self.output.ends_with(' ') && !self.output.is_empty() {
                self.output.push(' ');
            }
            self.output.push_str(text);
        }
        self.at_line_start = false;
        self.stick_to_prev = false;
    }

    fn emit_on_new_line(&mut self, level: usize, text: &str) {
        while self.output.ends_with(' ') {
            self.output.pop();
        }
        if !self.output.is_empty() {
            self.output.push('\n');
        }
        self.output.push_str(&indent_string(level));
        self.output.push_str(text);
        self.at_line_start = false;
        self.stick_to_prev = false;
    }

    fn previous_non_whitespace_is_identifier(&self) -> bool {
        match self.output.chars().last() {
            Some(ch) => ch.is_alphanumeric() || ch == '_' || ch == '.',
            None => false,
        }
    }

    fn next_word_is_clause_start(&self) -> bool {
        // Start past the current `(` token.
        let mut cursor = self.index + 1;
        while cursor < self.tokens.len() {
            match &self.tokens[cursor] {
                Token::Word(text) => {
                    let upper = text.to_uppercase();
                    return matches!(upper.as_str(), "SELECT" | "WITH" | "VALUES");
                }
                Token::Whitespace | Token::Comment(_) => cursor += 1,
                _ => return false,
            }
        }
        false
    }
}

fn is_join_clause(upper: &str) -> bool {
    upper == "JOIN" || JOIN_CLAUSES.contains(&upper)
}

/// Body mode each clause keyword puts the surrounding frame into.
fn frame_mode_for_clause(upper: &str) -> Option<FrameMode> {
    match upper {
        "SELECT" => Some(FrameMode::SelectList),
        "FROM" => Some(FrameMode::FromList),
        "WHERE" | "HAVING" | "ON" => Some(FrameMode::Condition),
        "GROUP BY" | "ORDER BY" | "BY" | "VALUES" | "RETURNING" => Some(FrameMode::ItemList),
        _ => None,
    }
}

fn indent_string(level: usize) -> String {
    "    ".repeat(level)
}

// ---- Tokenizer -----------------------------------------------------------------

fn tokenize(sql: &str) -> Vec<Token> {
    let chars: Vec<char> = sql.chars().collect();
    let mut tokens = Vec::new();
    let mut index = 0;

    while index < chars.len() {
        let ch = chars[index];

        if ch.is_whitespace() {
            while index < chars.len() && chars[index].is_whitespace() {
                index += 1;
            }
            tokens.push(Token::Whitespace);
            continue;
        }
        // Line comment: -- …
        if ch == '-' && chars.get(index + 1) == Some(&'-') {
            let start = index;
            while index < chars.len() && chars[index] != '\n' {
                index += 1;
            }
            tokens.push(Token::Comment(chars[start..index].iter().collect()));
            continue;
        }
        // Block comment: /* … */
        if ch == '/' && chars.get(index + 1) == Some(&'*') {
            let start = index;
            index += 2;
            while index < chars.len() {
                if chars[index] == '*' && chars.get(index + 1) == Some(&'/') {
                    index += 2;
                    break;
                }
                index += 1;
            }
            tokens.push(Token::Comment(chars[start..index].iter().collect()));
            continue;
        }
        // String literal with doubled-quote escapes.
        if ch == '\'' || ch == '"' || ch == '`' {
            let quote = ch;
            let start = index;
            index += 1;
            while index < chars.len() {
                if chars[index] == quote {
                    if chars.get(index + 1) == Some(&quote) {
                        index += 2;
                        continue;
                    }
                    index += 1;
                    break;
                }
                index += 1;
            }
            tokens.push(Token::StringLiteral(chars[start..index].iter().collect()));
            continue;
        }
        // Word: identifier or keyword.
        if ch.is_alphanumeric() || ch == '_' {
            let start = index;
            while index < chars.len() {
                let here = chars[index];
                if here.is_alphanumeric() || here == '_' || here == '.' {
                    index += 1;
                } else {
                    break;
                }
            }
            let raw: String = chars[start..index].iter().collect();
            let upper = raw.to_uppercase();
            let folded = if is_keyword(&upper) { upper } else { raw };
            tokens.push(Token::Word(folded));
            continue;
        }
        // Multi-char operators, longest first, so `->>` doesn't truncate.
        if let Some((op, span)) = match_operator(&chars, index) {
            tokens.push(Token::Symbol(op));
            index += span;
            continue;
        }
        tokens.push(Token::Symbol(ch.to_string()));
        index += 1;
    }
    tokens
}

fn match_operator(chars: &[char], start: usize) -> Option<(String, usize)> {
    const THREE: [&str; 1] = ["->>"];
    const TWO: [&str; 9] = ["!=", "<>", "<=", ">=", "==", "||", "<<", ">>", "->"];

    let slice_eq = |op: &str, len: usize| -> bool {
        start + len <= chars.len() && chars[start..start + len].iter().collect::<String>() == op
    };
    for op in THREE {
        if slice_eq(op, 3) {
            return Some((op.to_string(), 3));
        }
    }
    for op in TWO {
        if slice_eq(op, 2) {
            return Some((op.to_string(), 2));
        }
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn select_where_breaks_items_and_conditions() {
        let out = format_sql(
            "select callsign, band, mode from qsos where band = '20m' and mode = 'CW' or snr > 10 order by qso_date desc limit 50",
        );
        let expected = "SELECT\n    callsign,\n    band,\n    mode\nFROM\n    qsos\nWHERE\n    band = '20m'\n    AND mode = 'CW'\n    OR snr > 10\nORDER BY\n    qso_date DESC\nLIMIT 50";
        assert_eq!(out, expected);
    }

    #[test]
    fn joins_nest_under_from_with_on_conditions() {
        let out = format_sql(
            "select s.callsign from scope.spots s left join qsos q on q.callsign = s.callsign and q.band = s.band",
        );
        let expected = "SELECT\n    s.callsign\nFROM\n    scope.spots s\n    LEFT JOIN qsos q ON q.callsign = s.callsign\n    AND q.band = s.band";
        assert_eq!(out, expected);
    }

    #[test]
    fn function_calls_stay_inline() {
        let out = format_sql("select count(*), max(snr_db) from scope.spot_observations");
        assert_eq!(
            out,
            "SELECT\n    COUNT(*),\n    MAX(snr_db)\nFROM\n    scope.spot_observations"
        );
    }

    #[test]
    fn in_subquery_indents() {
        // Swift-parity quirks preserved: no space before `(`, and the
        // closing paren stays inline because inner clauses overwrite the
        // subquery frame's mode before `)` arrives.
        let out = format_sql(
            "select spot_id from scope.spots where callsign in (select callsign from qsos)",
        );
        let expected = "SELECT\n    spot_id\nFROM\n    scope.spots\nWHERE\n    callsign IN(\n    SELECT\n        callsign\n    FROM\n        qsos)";
        assert_eq!(out, expected);
    }

    #[test]
    fn case_expression_breaks_when_else_end() {
        // Swift parity: the CASE frame anchors at the surrounding frame's
        // base indent (0 here), so WHEN/ELSE sit at 1 and END at 0.
        let out = format_sql(
            "select case when snr > 20 then 'loud' else 'weak' end as loudness from scope.spots",
        );
        let expected = "SELECT\n    CASE\n    WHEN snr > 20 THEN 'loud'\n    ELSE 'weak'\nEND AS loudness\nFROM\n    scope.spots";
        assert_eq!(out, expected);
    }

    #[test]
    fn multi_char_operators_stay_glued() {
        let out = format_sql("select a from t where a != 1 and b ->> 'x' >= 2");
        assert!(out.contains("!= 1"));
        assert!(out.contains("->> 'x' >= 2"));
    }

    #[test]
    fn string_literals_and_comments_preserved() {
        let out = format_sql("select 'it''s' as v -- trailing note\nfrom t");
        assert!(out.contains("'it''s'"));
        assert!(out.contains("-- trailing note"));
    }

    #[test]
    fn formatting_is_idempotent() {
        let inputs = [
            "select callsign, band from qsos where band='20m' and mode='CW' order by qso_date desc",
            "select s.callsign from scope.spots s left join qsos q on q.callsign = s.callsign",
            "select spot_id from scope.spots where callsign in (select callsign from qsos) and snr > 5",
            "select case when snr > 20 then 'loud' else 'weak' end from scope.spots group by band",
            "select count(*) from a union all select count(*) from b;",
        ];
        for input in inputs {
            let once = format_sql(input);
            let twice = format_sql(&once);
            assert_eq!(once, twice, "not idempotent for: {input}");
        }
    }
}
