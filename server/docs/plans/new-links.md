# Friend Invite Links - Server Implementation Plan
 
> **Status:** Ready for implementation
> **Target:** challenges-server (Rust)
> **Client:** Already implemented in Carrier Wave iOS app
 
## Overview
 
Implement friend invite links that allow users to share a URL. When another user opens the URL, they can send a friend request to the link creator without needing to search for their callsign.
 
## Database Schema
 
### New Table: `friend_invites`
 
```sql
CREATE TABLE friend_invites (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    token VARCHAR(64) NOT NULL UNIQUE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at TIMESTAMPTZ NOT NULL,
    used_at TIMESTAMPTZ,          -- NULL until used
    used_by_user_id UUID REFERENCES users(id), -- Who used the invite
 
    CONSTRAINT token_format CHECK (token ~ '^inv_[a-zA-Z0-9]{20,}$')
);
 
CREATE INDEX idx_friend_invites_token ON friend_invites(token);
CREATE INDEX idx_friend_invites_user_id ON friend_invites(user_id);
CREATE INDEX idx_friend_invites_expires_at ON friend_invites(expires_at);
```
 
## API Endpoints
 
### 1. Generate Invite Link
 
**Endpoint:** `GET /v1/friends/invite-link`
 
**Authentication:** Required (Bearer token)
 
**Description:** Generates a new invite link for the authenticated user. Each call generates a fresh link. Old links remain valid until they expire or are used.
 
**Response 200:**
```json
{
  "data": {
    "token": "inv_a1b2c3d4e5f6g7h8i9j0k1l2",
    "url": "https://carrierwave.app/invite/inv_a1b2c3d4e5f6g7h8i9j0k1l2",
    "expiresAt": "2026-02-11T00:00:00Z"
  }
}
```
 
**Implementation:**
1. Extract user_id from auth token
2. Generate a secure random token with `inv_` prefix (use 20+ alphanumeric chars)
3. Calculate expiration (7 days from now)
4. Insert into `friend_invites` table
5. Build URL using configured base URL + `/invite/` + token
6. Return the invite link DTO
 
**Error Responses:**
- 401 Unauthorized - Missing or invalid auth token
 
---
 
### 2. Accept Invite via Token
 
**Endpoint:** `POST /v1/friends/requests`
 
**Authentication:** Required (Bearer token)
 
**Description:** This endpoint already exists for sending friend requests by user ID. Add support for an alternate body format using an invite token.
 
**Existing Body (by user ID):**
```json
{
  "toUserId": "usr_abc123"
}
```
 
**New Body (by invite token):**
```json
{
  "inviteToken": "inv_a1b2c3d4e5f6g7h8i9j0k1l2"
}
```
 
**Response 200:** Same as existing friend request response
```json
{
  "data": {
    "id": "550e8400-e29b-41d4-a716-446655440000",
    "fromUserId": "usr_sender123",
    "fromCallsign": "N0CALL",
    "toUserId": "usr_inviter456",
    "toCallsign": "W1ABC",
    "status": "pending",
    "requestedAt": "2026-02-04T12:00:00Z"
  }
}
```
 
**Implementation when `inviteToken` is provided:**
1. Extract sender's user_id from auth token
2. Look up invite by token in `friend_invites` table
3. Validate invite:
   - Token exists
   - Not expired (`expires_at > NOW()`)
   - Not already used (`used_at IS NULL`)
   - Inviter is not the same as sender (can't friend yourself)
4. Get the inviter's user_id from the invite record
5. Check if friendship/request already exists between these users
6. Create friend request from sender → inviter
7. Mark invite as used: `UPDATE friend_invites SET used_at = NOW(), used_by_user_id = ? WHERE token = ?`
8. Return the friend request DTO
 
**Error Responses:**
- 400 Bad Request - Invalid request body (neither toUserId nor inviteToken provided)
- 401 Unauthorized - Missing or invalid auth token
- 404 Not Found - Invite token not found or expired
- 409 Conflict - Friend request already exists, or already friends
- 422 Unprocessable Entity - Cannot send friend request to yourself
 
---
 
## Data Types
 
### InviteLinkDTO
```rust
#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct InviteLinkDTO {
    pub token: String,
    pub url: String,
    pub expires_at: DateTime<Utc>,
}
```
 
### CreateFriendRequestBody (updated)
```rust
#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CreateFriendRequestBody {
    // Existing field - send request to specific user
    #[serde(default)]
    pub to_user_id: Option<String>,
 
    // New field - send request via invite token
    #[serde(default)]
    pub invite_token: Option<String>,
}
```
 
---
 
## Configuration
 
Add to server config:
```rust
pub struct Config {
    // ... existing fields ...
 
    /// Base URL for invite links (e.g., "https://carrierwave.app")
    pub invite_base_url: String,
 
    /// How long invite links are valid (default: 7 days)
    pub invite_expiry_days: u32,
}
```
 
Environment variables:
```
INVITE_BASE_URL=https://activities.carrierwave.app
INVITE_EXPIRY_DAYS=7
```
 
---
 
## Token Generation
 
Generate secure tokens using:
```rust
use rand::Rng;
 
fn generate_invite_token() -> String {
    const CHARSET: &[u8] = b"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
    let mut rng = rand::thread_rng();
 
    let token: String = (0..24)
        .map(|_| {
            let idx = rng.gen_range(0..CHARSET.len());
            CHARSET[idx] as char
        })
        .collect();
 
    format!("inv_{}", token)
}
```
 
---
 
## Database Migration
 
Create migration file: `YYYYMMDDHHMMSS_create_friend_invites.sql`
 
```sql
-- Up
CREATE TABLE friend_invites (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    token VARCHAR(64) NOT NULL UNIQUE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at TIMESTAMPTZ NOT NULL,
    used_at TIMESTAMPTZ,
    used_by_user_id UUID REFERENCES users(id),
 
    CONSTRAINT token_format CHECK (token ~ '^inv_[a-zA-Z0-9]{20,}$')
);
 
CREATE INDEX idx_friend_invites_token ON friend_invites(token);
CREATE INDEX idx_friend_invites_user_id ON friend_invites(user_id);
CREATE INDEX idx_friend_invites_expires_at ON friend_invites(expires_at);
 
-- Down
DROP TABLE friend_invites;
```
 
---
 
## Cleanup Job (Optional)
 
Add a periodic cleanup job to remove expired/used invites:
 
```sql
DELETE FROM friend_invites
WHERE expires_at < NOW() - INTERVAL '30 days'
   OR used_at < NOW() - INTERVAL '30 days';
```
 
Run daily via cron or background worker.
 
---
 
## Testing
 
### Unit Tests
1. Token generation produces valid format
2. Invite creation sets correct expiration
3. Invite lookup returns NULL for expired tokens
4. Invite lookup returns NULL for used tokens
 
### Integration Tests
1. `GET /v1/friends/invite-link` returns valid invite
2. `POST /v1/friends/requests` with valid invite token creates friend request
3. `POST /v1/friends/requests` with expired token returns 404
4. `POST /v1/friends/requests` with used token returns 404
5. `POST /v1/friends/requests` with own invite token returns 422
6. `POST /v1/friends/requests` when already friends returns 409
 
---
 
## File Changes Summary
 
| File | Change |
|------|--------|
| `migrations/XXXX_create_friend_invites.sql` | New migration |
| `src/models/friend_invite.rs` | New model |
| `src/models/mod.rs` | Export new model |
| `src/routes/friends.rs` | Add invite link endpoint, modify create request |
| `src/config.rs` | Add invite config fields |
| `.env.example` | Add new env vars |
 
---
 
## Client Behavior Reference
 
The iOS client:
1. Calls `GET /v1/friends/invite-link` when user taps "Invite Friend"
2. Displays the URL and allows sharing via iOS share sheet
3. When user opens `carrierwave://invite/{token}` or `https://carrierwave.app/invite/{token}`:
   - App extracts the token
   - Shows confirmation dialog
   - Calls `POST /v1/friends/requests` with `{ "inviteToken": "{token}" }`
   - On success, shows the friend request was sent
