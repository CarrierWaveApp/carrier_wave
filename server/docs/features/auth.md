# Authentication

## Overview

The challenges server uses a simple callsign + device token model. No user accounts or passwords - identity is tied to amateur radio callsigns.

## Device Tokens

### Format

```
fd_{32 alphanumeric characters}
```

The `fd_` prefix identifies FullDuplex challenge tokens.

### Generation

Tokens are generated using cryptographically secure random bytes:

```rust
use rand::Rng;

fn generate_token() -> String {
    let chars: Vec<char> = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        .chars()
        .collect();
    let token: String = (0..32)
        .map(|_| chars[rand::thread_rng().gen_range(0..chars.len())])
        .collect();
    format!("fd_{}", token)
}
```

### Lifecycle

1. **Creation**: Token generated on first challenge join
2. **Storage**: Client stores in Keychain, server stores in `participants` table
3. **Usage**: Included in `Authorization: Bearer` header
4. **Revocation**: Admin can revoke all tokens for a callsign

## Authentication Flow

### First Join

```
Client                              Server
  │                                   │
  │  POST /challenges/{id}/join       │
  │  { callsign: "W1ABC",             │
  │    deviceName: "iPhone" }         │
  │────────────────────────────────▶  │
  │                                   │
  │                            Generate token
  │                            Store in DB
  │                                   │
  │  { participationId: "...",        │
  │    deviceToken: "fd_abc123..." }  │
  │◀────────────────────────────────  │
  │                                   │
  │  (Store token in Keychain)        │
```

### Subsequent Requests

```
Client                              Server
  │                                   │
  │  POST /challenges/{id}/progress   │
  │  Authorization: Bearer fd_abc123  │
  │  { progress: {...} }              │
  │────────────────────────────────▶  │
  │                                   │
  │                            Validate token
  │                            Extract callsign
  │                            Process request
  │                                   │
  │  { accepted: true, ... }          │
  │◀────────────────────────────────  │
```

### Joining Another Challenge

If device already has a token, include it when joining:

```
POST /challenges/{id}/join
Authorization: Bearer fd_abc123
{ callsign: "W1ABC" }
```

Server verifies token matches callsign and creates participation.

## Multiple Devices

A callsign can have multiple device tokens:

| callsign | device_token | device_name |
|----------|--------------|-------------|
| W1ABC | fd_abc123... | iPhone |
| W1ABC | fd_def456... | iPad |
| W1ABC | fd_ghi789... | Mac |

All devices share the same progress for a challenge.

## Token Validation

Middleware extracts and validates tokens:

```rust
async fn auth_middleware(
    State(db): State<PgPool>,
    mut req: Request,
    next: Next,
) -> Result<Response, AppError> {
    if let Some(auth) = req.headers().get("authorization") {
        let token = auth
            .to_str()
            .ok()
            .and_then(|s| s.strip_prefix("Bearer "))
            .ok_or(AppError::InvalidToken)?;

        let participant = sqlx::query_as!(
            Participant,
            "SELECT * FROM participants WHERE device_token = $1",
            token
        )
        .fetch_optional(&db)
        .await?
        .ok_or(AppError::InvalidToken)?;

        // Update last_seen_at
        sqlx::query!(
            "UPDATE participants SET last_seen_at = now() WHERE id = $1",
            participant.id
        )
        .execute(&db)
        .await?;

        // Attach callsign to request extensions
        req.extensions_mut().insert(AuthContext {
            callsign: participant.callsign,
        });
    }

    Ok(next.run(req).await)
}
```

## Protected vs Public Endpoints

| Endpoint | Auth Required | Reason |
|----------|---------------|--------|
| `GET /challenges` | No | Public discovery |
| `GET /challenges/{id}` | No | Public info |
| `POST /challenges/{id}/join` | No* | Issues token |
| `POST /challenges/{id}/progress` | Yes | Modify own data |
| `GET /challenges/{id}/progress` | Yes | Read own data |
| `GET /challenges/{id}/leaderboard` | No | Public standings |
| `DELETE /challenges/{id}/leave` | Yes | Modify own data |

*Join accepts optional token for existing callsigns joining new challenges.

## Admin Authentication

Admin endpoints use a separate static token:

```
Authorization: Bearer {ADMIN_TOKEN}
```

The admin token is set via environment variable and grants full access to:
- Challenge CRUD
- Badge management
- Invite generation
- Token revocation

## Security Considerations

### Token Security

- Tokens are 32 random alphanumeric characters (~190 bits of entropy)
- Tokens are never logged or exposed in responses (except on creation)
- Tokens should be stored in Keychain (iOS) or equivalent secure storage

### Callsign Trust

This system doesn't verify callsign ownership. A user could claim any callsign. Mitigations:

1. **Community policing**: Leaderboards are public; fake callsigns get noticed
2. **Token revocation**: Admins can revoke tokens for abusive callsigns
3. **Future**: Could add QRZ/LoTW OAuth for verified identity

### Rate Limiting

Per-IP rate limiting prevents brute-force token guessing:
- Progress reporting: 30/min
- Other endpoints: 60-120/min

## Revocation

Admins can revoke all tokens for a callsign:

```
DELETE /v1/admin/participants/{callsign}/tokens
```

This immediately invalidates all devices for that callsign. The user would need to re-join challenges to get new tokens.

Use cases:
- Abusive behavior
- User request (lost device)
- Callsign transfer
