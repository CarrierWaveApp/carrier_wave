//! Query lexer. Port of `QueryLexer.swift`.
//!
//! Operates on a `Vec<char>` so all offsets are character counts, matching
//! Swift's `String.Index`/`distance` semantics exactly.

use super::error::QueryError;
use super::token::{PositionedToken, QueryField, QueryToken, SourcePosition};

pub struct QueryLexer {
    input: Vec<char>,
    index: usize,
}

impl QueryLexer {
    pub fn new(input: &str) -> Self {
        QueryLexer { input: input.chars().collect(), index: 0 }
    }

    pub fn tokenize(mut self) -> Result<Vec<PositionedToken>, QueryError> {
        let mut tokens: Vec<PositionedToken> = Vec::new();

        while !self.is_at_end() {
            self.skip_whitespace();
            if self.is_at_end() {
                break;
            }
            let start_offset = self.index;

            match self.peek() {
                Some('|') | Some('-') | Some('(') | Some(')') => {
                    tokens.push(self.scan_single_char_token(start_offset));
                }
                Some('>') => {
                    tokens.push(self.scan_comparison_token(
                        '>',
                        QueryToken::GreaterThan,
                        QueryToken::GreaterThanOrEqual,
                        '=',
                        start_offset,
                    ));
                }
                Some('<') => {
                    tokens.push(self.scan_comparison_token(
                        '<',
                        QueryToken::LessThan,
                        QueryToken::LessThanOrEqual,
                        '=',
                        start_offset,
                    ));
                }
                Some('"') => {
                    tokens.push(self.scan_quoted_string_token(start_offset)?);
                }
                _ => {
                    tokens.extend(self.scan_word_or_field_token(start_offset)?);
                }
            }
        }

        tokens.push(PositionedToken::new(
            QueryToken::Eof,
            SourcePosition::new(self.input.len(), 0),
            "",
        ));
        Ok(tokens)
    }

    fn is_at_end(&self) -> bool {
        self.index >= self.input.len()
    }

    fn peek(&self) -> Option<char> {
        self.input.get(self.index).copied()
    }

    fn advance(&mut self) -> Option<char> {
        let ch = self.input.get(self.index).copied();
        if ch.is_some() {
            self.index += 1;
        }
        ch
    }

    fn skip_whitespace(&mut self) {
        while let Some(ch) = self.peek() {
            if ch.is_whitespace() {
                self.advance();
            } else {
                break;
            }
        }
    }

    fn scan_single_char_token(&mut self, start_offset: usize) -> PositionedToken {
        let ch = self.advance().unwrap();
        let token = match ch {
            '|' => QueryToken::Or,
            '-' => QueryToken::Not,
            '(' => QueryToken::OpenParen,
            ')' => QueryToken::CloseParen,
            _ => unreachable!(),
        };
        PositionedToken::new(token, SourcePosition::new(start_offset, 1), ch.to_string())
    }

    fn scan_comparison_token(
        &mut self,
        base_char: char,
        base: QueryToken,
        extended: QueryToken,
        follow_char: char,
        start_offset: usize,
    ) -> PositionedToken {
        self.advance();
        if self.peek() == Some(follow_char) {
            self.advance();
            return PositionedToken::new(
                extended,
                SourcePosition::new(start_offset, 2),
                format!("{base_char}{follow_char}"),
            );
        }
        PositionedToken::new(base, SourcePosition::new(start_offset, 1), base_char.to_string())
    }

    fn scan_quoted_string_token(
        &mut self,
        start_offset: usize,
    ) -> Result<PositionedToken, QueryError> {
        let value = self.scan_quoted_string()?;
        let length = self.index - start_offset;
        Ok(PositionedToken::new(
            QueryToken::Value(value.clone()),
            SourcePosition::new(start_offset, length),
            value,
        ))
    }

    fn scan_word_or_field_token(
        &mut self,
        start_offset: usize,
    ) -> Result<Vec<PositionedToken>, QueryError> {
        let word = self.scan_word();

        // If scan_word made no progress the current character starts no valid
        // token (e.g. '%', '@', '#').  Consume it and emit nothing — this
        // guarantees termination on any input.
        if word.is_empty() {
            self.advance();
            return Ok(vec![]);
        }

        let length = word.chars().count();

        if self.peek() == Some(':') {
            self.scan_field_qualifier(&word, start_offset, length)
        } else if word == ".." {
            Ok(vec![PositionedToken::new(
                QueryToken::Range,
                SourcePosition::new(start_offset, 2),
                "..",
            )])
        } else if word.contains("..") {
            Ok(self.split_embedded_range(&word, start_offset))
        } else {
            Ok(vec![PositionedToken::new(
                QueryToken::Value(word.clone()),
                SourcePosition::new(start_offset, length),
                word,
            )])
        }
    }

    fn scan_field_qualifier(
        &mut self,
        word: &str,
        start_offset: usize,
        length: usize,
    ) -> Result<Vec<PositionedToken>, QueryError> {
        self.advance(); // consume ':'
        if let Some(field) = QueryField::parse(word) {
            return Ok(vec![PositionedToken::new(
                QueryToken::Field(field),
                SourcePosition::new(start_offset, length + 1),
                format!("{word}:"),
            )]);
        }
        let suggestion = Self::find_similar_field(word);
        Err(QueryError::UnknownField {
            field: word.to_string(),
            suggestion,
            position: SourcePosition::new(start_offset, length),
        })
    }

    fn split_embedded_range(&self, word: &str, start_offset: usize) -> Vec<PositionedToken> {
        // Mirrors Swift: split on '.', parts[0] is everything before the first
        // '.', afterRange drops (beforeRange.count + 2) characters.
        let chars: Vec<char> = word.chars().collect();
        let first_dot = match chars.iter().position(|&c| c == '.') {
            Some(idx) => idx,
            None => return vec![],
        };
        let before_len = first_dot;
        let before_range: String = chars[..before_len].iter().collect();
        let drop = before_len + 2;
        let after_range: String =
            if drop <= chars.len() { chars[drop..].iter().collect() } else { String::new() };

        let mut tokens: Vec<PositionedToken> = Vec::new();

        if !before_range.is_empty() {
            let len = before_range.chars().count();
            tokens.push(PositionedToken::new(
                QueryToken::Value(before_range.clone()),
                SourcePosition::new(start_offset, len),
                before_range.clone(),
            ));
        }

        tokens.push(PositionedToken::new(
            QueryToken::Range,
            SourcePosition::new(start_offset + before_len, 2),
            "..",
        ));

        if !after_range.is_empty() {
            let len = after_range.chars().count();
            tokens.push(PositionedToken::new(
                QueryToken::Value(after_range.clone()),
                SourcePosition::new(start_offset + before_len + 2, len),
                after_range,
            ));
        }

        tokens
    }

    fn scan_word(&mut self) -> String {
        let mut result = String::new();
        while let Some(ch) = self.peek() {
            if Self::is_word_character(ch) {
                result.push(ch);
                self.advance();
            } else {
                break;
            }
        }
        result
    }

    fn is_word_character(ch: char) -> bool {
        ch.is_alphabetic()
            || ch.is_numeric()
            || ch == '*'
            || ch == '/'
            || ch == '-'
            || ch == '.'
            || ch == '_'
    }

    fn scan_quoted_string(&mut self) -> Result<String, QueryError> {
        let start_offset = self.index;
        self.advance(); // opening quote

        let mut result = String::new();
        while let Some(ch) = self.peek() {
            if ch == '"' {
                self.advance(); // closing quote
                return Ok(result);
            } else if ch == '\\' {
                self.advance(); // backslash
                if let Some(escaped) = self.advance() {
                    result.push(escaped);
                }
            } else {
                result.push(ch);
                self.advance();
            }
        }

        Err(QueryError::UnterminatedString {
            position: SourcePosition::new(start_offset, result.chars().count() + 1),
        })
    }

    fn find_similar_field(input: &str) -> Option<String> {
        let lowercased = input.to_lowercase();
        let mut best_match: Option<String> = None;
        let mut best_score = usize::MAX;
        for name in QueryField::ALIAS_KEYS {
            let score = levenshtein_distance(&lowercased, name);
            if score < best_score && score <= 2 {
                best_score = score;
                best_match = Some(name.to_string());
            }
        }
        best_match
    }
}

pub(crate) fn levenshtein_distance(s1: &str, s2: &str) -> usize {
    let a: Vec<char> = s1.chars().collect();
    let b: Vec<char> = s2.chars().collect();
    let m = a.len();
    let n = b.len();
    if m == 0 {
        return n;
    }
    if n == 0 {
        return m;
    }

    let mut previous_row: Vec<usize> = (0..=n).collect();
    let mut current_row: Vec<usize> = vec![0; n + 1];

    for i in 1..=m {
        current_row[0] = i;
        for j in 1..=n {
            let cost = if a[i - 1] == b[j - 1] { 0 } else { 1 };
            current_row[j] = (previous_row[j] + 1)
                .min(current_row[j - 1] + 1)
                .min(previous_row[j - 1] + cost);
        }
        std::mem::swap(&mut previous_row, &mut current_row);
    }

    previous_row[n]
}
