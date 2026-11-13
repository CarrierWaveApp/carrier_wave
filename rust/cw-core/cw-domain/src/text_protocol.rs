//! `;`-terminated text protocol response extractor used by Kenwood + Yaesu.
//! Port of `TextProtocolParser.swift`.

/// Returns `(responses, consumed_bytes)`. Caller retains unconsumed tail for
/// the next call.
pub fn extract_responses(buffer: &str) -> (Vec<String>, usize) {
    let mut responses = Vec::new();
    let mut consumed = 0usize;
    let bytes = buffer.as_bytes();
    let mut start = 0usize;
    for (idx, ch) in buffer.char_indices() {
        if ch == ';' {
            let chunk = &buffer[start..idx];
            if !chunk.is_empty() {
                responses.push(chunk.to_string());
            }
            // Past the semicolon (`;` is one byte in UTF-8).
            consumed = idx + 1;
            start = consumed;
        }
    }
    let _ = bytes;
    (responses, consumed)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn extracts_complete_responses() {
        let (responses, consumed) = extract_responses("FA00014060000;MD3;");
        assert_eq!(responses, vec!["FA00014060000", "MD3"]);
        assert_eq!(consumed, "FA00014060000;MD3;".len());
    }

    #[test]
    fn skips_empty_segments() {
        let (responses, consumed) = extract_responses(";;;");
        assert!(responses.is_empty());
        assert_eq!(consumed, 3);
    }

    #[test]
    fn leaves_unterminated_tail() {
        let (responses, consumed) = extract_responses("MD3;FA000");
        assert_eq!(responses, vec!["MD3"]);
        assert_eq!(consumed, 4);
        // Caller should keep buffer[consumed..] = "FA000"
        assert_eq!(&"MD3;FA000"[consumed..], "FA000");
    }
}
