# Auth Index

Authentication and authorization: device tokens and middleware.

## Files

### `src/auth/mod.rs`
Module declarations and re-exports.

**Exports:**
- Re-exports all public items from submodules

### `src/auth/token.rs`
Device token generation and validation.

**Exports:**
- `fn generate_device_token()` - Generate random token with `fd_` prefix (32 alphanumeric chars)
- `fn is_valid_token_format()` - Validate token format (prefix + length + charset)

**Tests:**
- `test_generate_token_format` - Verify token prefix and length
- `test_generate_token_uniqueness` - Verify tokens are unique
- `test_is_valid_token_format` - Verify format validation

### `src/auth/middleware.rs`
Axum middleware for authentication.

**Exports:**
- `struct AuthContext` - Authenticated user context with callsign and participant_id
- `async fn optional_auth()` - Middleware that extracts auth if present, doesn't require it
- `async fn require_auth()` - Middleware that requires valid Bearer token, returns 401 if missing/invalid
- `async fn require_admin()` - Middleware that requires admin token match, returns 401 if invalid

**Internal:**
- `struct ParticipantRow` - Internal struct for query result
- `async fn validate_token()` - Lookup token in database, update last_seen_at
