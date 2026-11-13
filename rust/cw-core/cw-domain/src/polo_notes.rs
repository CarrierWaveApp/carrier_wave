//! Ham2K Polo callsign-notes parsing. Port of `PoloNotesParser.swift` +
//! `PoloNotesEntry.swift`.
//!
//! Pure logic — downloading the notes file (and merging multiple sources)
//! stays in the Swift/Kotlin app layer; this crate owns the line grammar and
//! the leading-emoji / name / note split, including the Unicode emoji
//! classification Swift performs via `Unicode.Scalar.Properties.isEmoji`.

use std::collections::HashMap;

use unicode_properties::UnicodeEmoji;
use unicode_segmentation::UnicodeSegmentation;

/// A parsed entry from a Polo notes list file.
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct PoloNotesEntry {
    /// The callsign (always uppercase).
    pub callsign: String,
    /// Leading emoji from the note text (e.g. "🌳").
    pub emoji: Option<String>,
    /// Operator name parsed from the note text.
    pub name: Option<String>,
    /// Note text (everything after the name; may contain markdown links).
    pub note: Option<String>,
}

impl PoloNotesEntry {
    /// Construct an entry, uppercasing the callsign (mirrors the Swift init).
    pub fn new(callsign: &str, emoji: Option<String>, name: Option<String>, note: Option<String>) -> Self {
        Self { callsign: callsign.to_uppercase(), emoji, name, note }
    }

    /// Callsign-only entry with no note.
    pub fn callsign_only(callsign: &str) -> Self {
        Self::new(callsign, None, None, None)
    }

    /// Parse an entry from a callsign and the note text following it.
    pub fn from_note_text(callsign: &str, note_text: &str) -> Self {
        let (emoji, remaining) = extract_leading_emoji(note_text);
        let trimmed = remaining.trim();

        let split = find_name_end(trimmed);
        let (name, note) = if split == 0 {
            (None, non_empty(trimmed))
        } else if split == trimmed.len() {
            (non_empty(trimmed), None)
        } else {
            let name_str = trimmed[..split].trim();
            let note_str = trimmed[split..].trim();
            (non_empty(name_str), non_empty(note_str))
        };

        Self::new(callsign, emoji, name, note)
    }
}

/// Parse a Polo notes list file into a map of uppercase callsign → entry.
pub fn parse(content: &str) -> HashMap<String, PoloNotesEntry> {
    let mut result: HashMap<String, PoloNotesEntry> = HashMap::new();
    for line in content.lines() {
        let trimmed = line.trim();
        if trimmed.is_empty() || trimmed.starts_with('#') {
            continue;
        }
        if let Some(entry) = parse_line(trimmed) {
            result.insert(entry.callsign.to_uppercase(), entry);
        }
    }
    result
}

/// Parse a single non-empty, non-comment line.
pub fn parse_line(line: &str) -> Option<PoloNotesEntry> {
    // Split on whitespace keeping empty fields, mirroring Swift's
    // `components(separatedBy: .whitespaces)`.
    let components: Vec<&str> = line.split(|ch: char| ch.is_whitespace()).collect();
    let first = components.first()?;
    let callsign = first.to_uppercase();
    if !is_likely_callsign(&callsign) {
        return None;
    }

    let note_text = components[1..].join(" ");
    let note_text = note_text.trim();
    if note_text.is_empty() {
        return Some(PoloNotesEntry::callsign_only(&callsign));
    }
    Some(PoloNotesEntry::from_note_text(&callsign, note_text))
}

/// Basic check that a string looks like a callsign.
fn is_likely_callsign(text: &str) -> bool {
    if text.chars().count() < 3 {
        return false;
    }
    if !text.chars().any(|c| c.is_alphabetic()) {
        return false;
    }
    if !text.chars().any(|c| c.is_numeric()) {
        return false;
    }
    !matches!(text, "THE" | "AND" | "FOR" | "ARE" | "BUT" | "NOT" | "YOU" | "ALL")
}

/// Byte index where the name portion ends — stops at the first `[` (markdown
/// link) or non-text emoji grapheme.
fn find_name_end(text: &str) -> usize {
    for (offset, grapheme) in text.grapheme_indices(true) {
        if grapheme == "[" {
            return offset;
        }
        if is_non_text_emoji(grapheme) {
            return offset;
        }
    }
    text.len()
}

/// True for a visual emoji grapheme (📺🌊🏠), false for ASCII chars that happen
/// to carry the Emoji property (digits, `#`, `*`).
fn is_non_text_emoji(grapheme: &str) -> bool {
    let Some(first) = grapheme.chars().next() else {
        return false;
    };
    if (first as u32) <= 0x7F {
        return false;
    }
    first.is_emoji_char()
}

/// Extract a run of leading emoji graphemes. Mirrors Swift's
/// `extractLeadingEmoji`, which treats any grapheme whose first scalar carries
/// the Emoji property (and isn't a space) as part of the leading emoji.
fn extract_leading_emoji(text: &str) -> (Option<String>, &str) {
    let mut end = 0;
    for (offset, grapheme) in text.grapheme_indices(true) {
        let is_emoji = grapheme.chars().next().map(|c| c.is_emoji_char()).unwrap_or(false);
        if is_emoji && grapheme != " " {
            end = offset + grapheme.len();
        } else {
            break;
        }
    }
    if end == 0 {
        (None, text)
    } else {
        (Some(text[..end].to_string()), &text[end..])
    }
}

fn non_empty(value: &str) -> Option<String> {
    if value.is_empty() {
        None
    } else {
        Some(value.to_string())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn callsign_only_entry() {
        let entry = parse_line("N0CALL").unwrap();
        assert_eq!(entry.callsign, "N0CALL");
        assert_eq!(entry.emoji, None);
        assert_eq!(entry.name, None);
        assert_eq!(entry.note, None);
    }

    #[test]
    fn name_only_entry_uppercases_callsign() {
        let entry = parse_line("k1abc Bob").unwrap();
        assert_eq!(entry.callsign, "K1ABC");
        assert_eq!(entry.emoji, None);
        assert_eq!(entry.name.as_deref(), Some("Bob"));
        assert_eq!(entry.note, None);
    }

    #[test]
    fn leading_emoji_and_name() {
        let entry = parse_line("W1AW 🌳 Portable").unwrap();
        assert_eq!(entry.callsign, "W1AW");
        assert_eq!(entry.emoji.as_deref(), Some("🌳"));
        assert_eq!(entry.name.as_deref(), Some("Portable"));
        assert_eq!(entry.note, None);
    }

    #[test]
    fn emoji_name_and_markdown_note() {
        let entry = parse_line("W1AW 🎹 John [QRZ](http://qrz.com/W1AW)").unwrap();
        assert_eq!(entry.emoji.as_deref(), Some("🎹"));
        assert_eq!(entry.name.as_deref(), Some("John"));
        assert_eq!(entry.note.as_deref(), Some("[QRZ](http://qrz.com/W1AW)"));
    }

    #[test]
    fn mid_text_emoji_splits_name_and_note() {
        let entry = parse_line("W1AW John 📺 streamer").unwrap();
        assert_eq!(entry.emoji, None);
        assert_eq!(entry.name.as_deref(), Some("John"));
        assert_eq!(entry.note.as_deref(), Some("📺 streamer"));
    }

    #[test]
    fn markdown_link_only_note() {
        let entry = parse_line("W1AW [QRZ](http://qrz.com)").unwrap();
        assert_eq!(entry.name, None);
        assert_eq!(entry.note.as_deref(), Some("[QRZ](http://qrz.com)"));
    }

    #[test]
    fn rejects_non_callsign_tokens() {
        assert!(parse_line("AND something").is_none());
        assert!(parse_line("HELLO world").is_none()); // no digit
        assert!(parse_line("12 ab").is_none()); // too short
    }

    #[test]
    fn parse_skips_comments_and_blanks() {
        let content = "# a comment\n\nW1AW 🌳 Portable\nK1ABC Bob\n";
        let map = parse(content);
        assert_eq!(map.len(), 2);
        assert_eq!(map["W1AW"].name.as_deref(), Some("Portable"));
        assert_eq!(map["K1ABC"].name.as_deref(), Some("Bob"));
    }
}
