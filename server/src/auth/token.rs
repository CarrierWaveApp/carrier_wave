use rand::Rng;

const TOKEN_PREFIX: &str = "fd_";
const TOKEN_LENGTH: usize = 32;
const TOKEN_CHARS: &[u8] = b"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";

pub fn generate_device_token() -> String {
    let mut rng = rand::thread_rng();
    let token: String = (0..TOKEN_LENGTH)
        .map(|_| {
            let idx = rng.gen_range(0..TOKEN_CHARS.len());
            TOKEN_CHARS[idx] as char
        })
        .collect();
    format!("{}{}", TOKEN_PREFIX, token)
}

#[allow(dead_code)]
pub fn is_valid_token_format(token: &str) -> bool {
    if !token.starts_with(TOKEN_PREFIX) {
        return false;
    }
    let suffix = &token[TOKEN_PREFIX.len()..];
    suffix.len() == TOKEN_LENGTH && suffix.chars().all(|c| c.is_ascii_alphanumeric())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_generate_token_format() {
        let token = generate_device_token();
        assert!(token.starts_with("fd_"));
        assert_eq!(token.len(), 3 + TOKEN_LENGTH); // "fd_" + 32 chars
    }

    #[test]
    fn test_generate_token_uniqueness() {
        let token1 = generate_device_token();
        let token2 = generate_device_token();
        assert_ne!(token1, token2);
    }

    #[test]
    fn test_is_valid_token_format() {
        assert!(is_valid_token_format("fd_abcdefghijklmnopqrstuvwxyz123456"));
        assert!(!is_valid_token_format("abc"));
        assert!(!is_valid_token_format("fd_short"));
        assert!(!is_valid_token_format(
            "xx_abcdefghijklmnopqrstuvwxyz123456"
        ));
    }
}
