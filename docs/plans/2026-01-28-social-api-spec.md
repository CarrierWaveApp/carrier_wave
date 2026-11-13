# Social Activity Feed - Server API Specification

> **Status:** Draft
> **Date:** 2026-01-28
> **Base URL:** `https://challenges.example.com/v1`

## Overview

This document specifies the API endpoints needed for the social activity feed feature. All endpoints extend the existing challenges server.

## Authentication

All authenticated endpoints require a Bearer token in the Authorization header:

```
Authorization: Bearer <token>
```

## Response Format

All responses use a standard wrapper:

```json
{
  "data": { ... },
  "meta": {
    "timestamp": "2026-01-28T15:30:00Z"
  }
}
```

Error responses:

```json
{
  "error": {
    "code": "ERROR_CODE",
    "message": "Human-readable message"
  }
}
```

---

## Users

### Search Users

Search for users by callsign or display name.

```
GET /v1/users/search?q={query}
```

**Authentication:** Optional (public search)

**Query Parameters:**
| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `q` | string | Yes | Search query (min 2 characters) |
| `limit` | int | No | Max results (default: 20, max: 50) |

**Response:**
```json
{
  "data": [
    {
      "userId": "usr_abc123",
      "callsign": "W1ABC",
      "displayName": "John Smith"
    }
  ]
}
```

---

## Friends

### List Friends

Get the authenticated user's confirmed friends.

```
GET /v1/friends
```

**Authentication:** Required

**Response:**
```json
{
  "data": [
    {
      "friendshipId": "550e8400-e29b-41d4-a716-446655440000",
      "userId": "usr_abc123",
      "callsign": "W1ABC",
      "displayName": "John Smith",
      "acceptedAt": "2026-01-15T10:30:00Z"
    }
  ]
}
```

### Send Friend Request

Send a friend request to another user.

```
POST /v1/friends/requests
```

**Authentication:** Required

**Request Body:**
```json
{
  "toUserId": "usr_abc123"
}
```

Or with invite token:
```json
{
  "inviteToken": "inv_xyz789"
}
```

**Response:**
```json
{
  "data": {
    "id": "550e8400-e29b-41d4-a716-446655440000",
    "fromUserId": "usr_me",
    "fromCallsign": "K2XYZ",
    "toUserId": "usr_abc123",
    "toCallsign": "W1ABC",
    "status": "pending",
    "requestedAt": "2026-01-28T15:30:00Z"
  }
}
```

**Error Codes:**
| Code | Description |
|------|-------------|
| `USER_NOT_FOUND` | Target user doesn't exist |
| `ALREADY_FRIENDS` | Already friends with this user |
| `REQUEST_EXISTS` | Pending request already exists |
| `CANNOT_FRIEND_SELF` | Cannot send request to yourself |

### Get Pending Requests

Get incoming and outgoing pending friend requests.

```
GET /v1/friends/requests/pending
```

**Authentication:** Required

**Response:**
```json
{
  "data": {
    "incoming": [
      {
        "id": "550e8400-e29b-41d4-a716-446655440000",
        "fromUserId": "usr_abc123",
        "fromCallsign": "W1ABC",
        "toUserId": "usr_me",
        "toCallsign": "K2XYZ",
        "status": "pending",
        "requestedAt": "2026-01-28T15:30:00Z"
      }
    ],
    "outgoing": [
      {
        "id": "660e8400-e29b-41d4-a716-446655440001",
        "fromUserId": "usr_me",
        "fromCallsign": "K2XYZ",
        "toUserId": "usr_def456",
        "toCallsign": "N3QRS",
        "status": "pending",
        "requestedAt": "2026-01-27T12:00:00Z"
      }
    ]
  }
}
```

### Accept Friend Request

Accept a pending friend request.

```
POST /v1/friends/requests/{requestId}/accept
```

**Authentication:** Required

**Response:** `204 No Content`

**Error Codes:**
| Code | Description |
|------|-------------|
| `REQUEST_NOT_FOUND` | Request doesn't exist or already handled |
| `NOT_RECIPIENT` | You are not the recipient of this request |

### Decline Friend Request

Decline a pending friend request.

```
POST /v1/friends/requests/{requestId}/decline
```

**Authentication:** Required

**Response:** `204 No Content`

**Error Codes:**
| Code | Description |
|------|-------------|
| `REQUEST_NOT_FOUND` | Request doesn't exist or already handled |
| `NOT_RECIPIENT` | You are not the recipient of this request |

### Remove Friend

Remove an existing friend.

```
DELETE /v1/friends/{friendshipId}
```

**Authentication:** Required

**Response:** `204 No Content`

**Error Codes:**
| Code | Description |
|------|-------------|
| `FRIENDSHIP_NOT_FOUND` | Friendship doesn't exist |

### Generate Invite Link

Generate a shareable invite link for adding friends.

```
GET /v1/friends/invite-link
```

**Authentication:** Required

**Response:**
```json
{
  "data": {
    "token": "inv_xyz789abc",
    "url": "https://carrierwave.app/invite/inv_xyz789abc",
    "expiresAt": "2026-02-28T15:30:00Z"
  }
}
```

---

## Clubs

### List My Clubs

Get clubs the authenticated user belongs to (based on callsign matching Polo notes lists).

```
GET /v1/clubs
```

**Authentication:** Required

**Response:**
```json
{
  "data": [
    {
      "id": "550e8400-e29b-41d4-a716-446655440000",
      "name": "Pacific Northwest DX Club",
      "description": "A club for DXers in the Pacific Northwest",
      "memberCount": 42,
      "poloNotesListId": "pnw-dx-club"
    }
  ]
}
```

### Get Club Details

Get details and member list for a specific club.

```
GET /v1/clubs/{clubId}
```

**Authentication:** Required

**Query Parameters:**
| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `includeMembers` | bool | No | Include member list (default: true) |

**Response:**
```json
{
  "data": {
    "id": "550e8400-e29b-41d4-a716-446655440000",
    "name": "Pacific Northwest DX Club",
    "description": "A club for DXers in the Pacific Northwest",
    "poloNotesListURL": "https://polo.ham2k.com/lists/pnw-dx-club",
    "memberCount": 42,
    "lastSyncedAt": "2026-01-28T12:00:00Z",
    "members": [
      {
        "callsign": "W7ABC",
        "userId": "usr_abc123",
        "isCarrierWaveUser": true
      },
      {
        "callsign": "K7XYZ",
        "userId": null,
        "isCarrierWaveUser": false
      }
    ]
  }
}
```

### Create Club (Admin Only)

Create a new club. Requires admin privileges.

```
POST /v1/clubs
```

**Authentication:** Required (Admin)

**Request Body:**
```json
{
  "name": "Pacific Northwest DX Club",
  "description": "A club for DXers in the Pacific Northwest",
  "poloNotesListURL": "https://polo.ham2k.com/lists/pnw-dx-club"
}
```

**Response:**
```json
{
  "data": {
    "id": "550e8400-e29b-41d4-a716-446655440000",
    "name": "Pacific Northwest DX Club",
    "description": "A club for DXers in the Pacific Northwest",
    "poloNotesListURL": "https://polo.ham2k.com/lists/pnw-dx-club",
    "memberCount": 0,
    "lastSyncedAt": null
  }
}
```

### Sync Club Members (Admin/Internal)

Trigger a sync of club members from the Polo notes list.

```
POST /v1/clubs/{clubId}/sync
```

**Authentication:** Required (Admin or internal)

**Response:**
```json
{
  "data": {
    "memberCount": 42,
    "added": 5,
    "removed": 2,
    "lastSyncedAt": "2026-01-28T15:30:00Z"
  }
}
```

---

## Activity Feed

### Get Feed

Get paginated activity feed for the authenticated user.

```
GET /v1/feed
```

**Authentication:** Required

**Query Parameters:**
| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `filter` | string | No | `friends`, `club:{clubId}`, or omit for all |
| `limit` | int | No | Max items (default: 50, max: 100) |
| `before` | string | No | Cursor for pagination (timestamp or ID) |
| `after` | string | No | Cursor for newer items |

**Response:**
```json
{
  "data": {
    "items": [
      {
        "id": "550e8400-e29b-41d4-a716-446655440000",
        "callsign": "W1ABC",
        "userId": "usr_abc123",
        "displayName": "John Smith",
        "activityType": "newDXCCEntity",
        "timestamp": "2026-01-28T15:30:00Z",
        "details": {
          "entityName": "Japan",
          "entityCode": "JA",
          "band": "20m",
          "mode": "SSB"
        }
      },
      {
        "id": "660e8400-e29b-41d4-a716-446655440001",
        "callsign": "K2XYZ",
        "userId": "usr_def456",
        "displayName": null,
        "activityType": "dailyStreak",
        "timestamp": "2026-01-28T14:00:00Z",
        "details": {
          "streakDays": 30
        }
      }
    ],
    "pagination": {
      "hasMore": true,
      "nextCursor": "2026-01-28T14:00:00Z"
    }
  }
}
```

### Report Activity

Report a notable activity from the client.

```
POST /v1/activities
```

**Authentication:** Required

**Request Body:**
```json
{
  "type": "newDXCCEntity",
  "timestamp": "2026-01-28T15:30:00Z",
  "details": {
    "entityName": "Japan",
    "entityCode": "JA",
    "band": "20m",
    "mode": "SSB",
    "workedCallsign": "JA1ABC"
  }
}
```

**Activity Types and Required Details:**

| Type | Required Details |
|------|------------------|
| `challengeTierUnlock` | `challengeId`, `challengeName`, `tierName` |
| `challengeCompletion` | `challengeId`, `challengeName` |
| `newDXCCEntity` | `entityName`, `entityCode`, `band`, `mode` |
| `newBand` | `band`, `mode` |
| `newMode` | `mode`, `band` |
| `dxContact` | `workedCallsign`, `distanceKm`, `band`, `mode` |
| `potaActivation` | `parkReference`, `parkName`, `qsoCount` |
| `sotaActivation` | `parkReference`, `parkName`, `qsoCount` |
| `dailyStreak` | `streakDays` |
| `potaDailyStreak` | `streakDays` |
| `personalBest` | `recordType`, `recordValue` |

**Response:**
```json
{
  "data": {
    "id": "550e8400-e29b-41d4-a716-446655440000",
    "callsign": "K2XYZ",
    "activityType": "newDXCCEntity",
    "timestamp": "2026-01-28T15:30:00Z",
    "details": {
      "entityName": "Japan",
      "entityCode": "JA",
      "band": "20m",
      "mode": "SSB",
      "workedCallsign": "JA1ABC"
    }
  }
}
```

**Error Codes:**
| Code | Description |
|------|-------------|
| `INVALID_ACTIVITY_TYPE` | Unknown activity type |
| `MISSING_DETAILS` | Required details for activity type missing |
| `DUPLICATE_ACTIVITY` | Similar activity already reported recently |

---

## Polo Notes List Integration

The server needs to periodically fetch and parse Ham2K Polo callsign notes lists for club membership.

### Expected Polo List Format

TBD - Need to confirm with Ham2K team. Expected to be JSON or CSV with callsigns.

### Sync Strategy

1. Server fetches Polo list URL for each club periodically (e.g., hourly)
2. Parse callsigns from list
3. Update club membership records
4. Mark users as club members if their callsign appears in list

---

## Rate Limits

| Endpoint Category | Limit |
|-------------------|-------|
| User search | 30 requests/minute |
| Friend actions | 60 requests/minute |
| Feed fetch | 120 requests/minute |
| Activity report | 60 requests/minute |

---

## Webhook Events (Future)

For push notifications, the server could emit webhooks:

| Event | Payload |
|-------|---------|
| `friend.request.received` | Friend request details |
| `friend.request.accepted` | Friendship details |
| `activity.friend` | New activity from a friend |

---

## Implementation Notes

1. **User identity**: Users are identified by their challenges server account, linked to callsign
2. **Privacy**: Activity is only visible to friends and club members
3. **Deduplication**: Server should deduplicate similar activities within a time window
4. **Retention**: Activity items should be retained for at least 90 days
5. **Polo sync**: Club member sync should handle Polo API rate limits gracefully
