# User-Submitted Events — CarrierWave Implementation Plan

**Date:** 2026-03-14
**Server PRD:** `~/projects/activities-server/docs/features/events.md`
**Server Plan:** `~/projects/activities-server/docs/plans/2026-03-14-user-events.md`

---

## Overview

Add user-submitted ham radio events (club meetings, swap meets, hamfests, etc.) with proximity-based discovery to the CarrierWave iOS app. Users submit events and browse nearby events. Events go through admin moderation on the server side (handled in activities-server repo).

### Scope (this repo)

- Event submission form with address autocomplete and map pin confirmation
- Map + list hybrid discovery view with radius and type filters
- "My Events" screen showing all statuses (pending/approved/rejected)
- Event detail sheet
- Push notifications on approval/rejection

### Out of scope (activities-server repo)

- Server API endpoints, migration, models, db layer, handlers
- Admin moderation UI (ios-admin app)

---

## API Endpoints (consumed by this app)

### Public

- `GET /v1/events` — Approved upcoming events near a location
  - Required: `lat`, `lon`, `radius_km`
  - Optional: `event_type`, `from_date`, `to_date`, `include_past`, `limit`, `offset`
  - Default: upcoming events only (`start_date >= NOW()`)
- `GET /v1/events/{id}` — Single approved event

### Authenticated (device token)

- `POST /v1/events` — Submit a new event (status = `pending`). Max 10 pending per callsign.
- `PUT /v1/events/{id}` — Edit own event. If approved, edits to key fields (name, description, address, venue_name, latitude, longitude) reset status to `pending`. Date/time/cost/url changes stay approved.
- `DELETE /v1/events/{id}` — Delete own event
- `GET /v1/events/mine` — Own events, all statuses

---

## Data Model

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| `id` | UUID | auto | |
| `name` | string(200) | yes | |
| `description` | text(2000) | no | |
| `eventType` | enum | yes | `club_meeting`, `swap_meet`, `field_day`, `special_event`, `hamfest`, `net`, `other` |
| `startDate` | ISO 8601 | yes | |
| `endDate` | ISO 8601 | no | null = single-moment event |
| `timezone` | string | yes | IANA identifier, e.g. `America/New_York` |
| `venueName` | string(200) | no | e.g. "VFW Hall" |
| `address` | text | yes | Street address |
| `city` | string | yes | |
| `state` | string | no | |
| `country` | string | yes | |
| `latitude` | float | yes | Client-side geocoded |
| `longitude` | float | yes | Client-side geocoded |
| `cost` | string(100) | no | Free-text, e.g. "Free", "$10 at door" |
| `url` | string | no | External event page |
| `submittedBy` | string | yes | Submitter's callsign |
| `status` | enum | yes | `pending`, `approved`, `rejected` |
| `reviewedBy` | string | no | Admin who reviewed |
| `reviewedAt` | ISO 8601 | no | |
| `rejectionReason` | text | no | |
| `createdAt` | ISO 8601 | auto | |
| `updatedAt` | ISO 8601 | auto | |

---

## Phase 1: API Client

### File: `CarrierWaveData/Sources/CarrierWaveData/Services/EventsClient.swift`

New `actor EventsClient` following the pattern of existing API clients.

**Types:**

```
EventType           — enum: clubMeeting, swapMeet, fieldDay, specialEvent, hamfest, net, other
EventStatus         — enum: pending, approved, rejected
EventResponse       — Codable, camelCase, all fields from data model
EventListItem       — Codable, subset for list display (excludes description)
EventListResponse   — { events: [EventListItem], totalCount: Int }
CreateEventRequest  — Encodable
UpdateEventRequest  — Encodable (all fields optional)
```

**Methods:**

```swift
func listEvents(lat:lon:radiusKm:eventType:fromDate:toDate:includePast:limit:offset:) async throws -> EventListResponse
func getEvent(id:) async throws -> EventResponse
func createEvent(_:) async throws -> EventResponse
func updateEvent(id:_:) async throws -> EventResponse
func deleteEvent(id:) async throws
func listMyEvents(limit:offset:) async throws -> [EventListItem]
```

---

## Phase 2: Event Discovery View (Map + List Hybrid)

### File: `CarrierWave/Views/Events/EventsView.swift`

- Upper portion: MapKit map with pins for nearby approved events
- Lower portion: Scrollable list sorted by date
- Uses device location by default; user can drag map or search a location to browse other areas
- Radius control: configurable (10 / 25 / 50 / 100 km) via segmented control or picker
- Filters: event type picker (multi-select), date range
- Data loading via `@State` + `.task` with `EventsClient` (no `@Query`)
- Pull-to-refresh

### File: `CarrierWave/Views/Events/EventMapAnnotation.swift`

- Map pin/annotation for events, color-coded by event type

---

## Phase 3: Event Detail Sheet

### File: `CarrierWave/Views/Events/EventDetailView.swift`

Tap a pin or list row to see:
- Name, event type badge
- Date/time displayed in event's timezone with label (e.g. "7:00 PM ET")
- Venue name, address, map snippet
- Cost (if set)
- Description
- External link button (if URL set)
- Submitter callsign

---

## Phase 4: Event Submission Flow

### File: `CarrierWave/Views/Events/EventSubmitView.swift`

Single scrollable form:

1. Name (required, text field)
2. Event type (required, picker wheel / segmented)
3. Start date & time (required, date picker)
4. End date & time (optional, date picker — hidden by default, "Add end time" toggle)
5. Timezone (auto-detected from selected location, editable picker)
6. Venue name (optional, text field)
7. Address (required, text field with MapKit autocomplete suggestions)
8. Map confirmation (inline map with draggable pin — geocoded from address, user can adjust)
9. City / State / Country (auto-populated from geocode, editable)
10. Cost (optional, text field, placeholder: "e.g. Free, $5")
11. Website URL (optional, text field with URL keyboard)
12. Description (optional, multi-line text view, 2000 char limit with counter)

**Client-side validation:**
- Required fields highlighted if empty
- `latitude` in range `[-90, 90]`, `longitude` in range `[-180, 180]`
- `startDate` must be in the future
- `endDate` must be after `startDate` if provided

**Submission confirmation:** "Your event has been submitted for review. You'll be notified when it's approved." Dismiss to events list.

**Reuse for editing:** Same form pre-filled when editing. Shows a note if key-field edits will reset approval status.

---

## Phase 5: My Events

### File: `CarrierWave/Views/Events/MyEventsView.swift`

- Accessible from profile/settings or a "My Events" row in the events section
- List of all events submitted by the user, grouped by status:
  - **Pending** — yellow indicator, "Awaiting review"
  - **Approved** — green indicator, "Live"
  - **Rejected** — red indicator, shows rejection reason
- Tap to view full detail with **Edit** and **Delete** actions
- Edit opens the same form pre-filled; submitting shows a note if key-field edits will reset approval
- Delete shows a destructive confirmation alert (follow delete confirmation patterns from `docs/features/delete-confirmation.md`)

---

## Phase 6: Push Notifications

- **Push on approval**: "Your event '[name]' has been approved and is now visible to nearby operators."
- **Push on rejection**: "Your event '[name]' was not approved. Reason: [reason]." Deep-links to the event detail so user can edit and resubmit.
- Register for push categories/actions for events
- Handle deep links to event detail from notification tap

---

## Phase 7: Navigation Integration

- Add "Events" tab or section accessible from main navigation
- Wire up EventsView as the entry point
- Deep link support for `/events/{id}` to open event detail

---

## Key Decisions

| Decision | Choice |
|----------|--------|
| Geocoding | Client-side (iOS sends lat/lon to server) |
| Recurrence | One-off events only (v1) |
| Edit re-review | Key fields only (name, description, address, venue, location) |
| Timezone | Store/display IANA timezone identifier |
| Location input | Address autocomplete + draggable map pin confirmation |
| Discovery UX | Map + list hybrid with radius control |
| Data loading | `@State` + `.task` with `EventsClient` — no `@Query` |

---

## Implementation Order

1. API client (`EventsClient` + types)
2. Event discovery view (map + list)
3. Event detail sheet
4. Event submission form
5. My events view
6. Push notifications
7. Navigation integration

---

## Estimated File Impact

| Action | File |
|--------|------|
| **New** | `CarrierWaveData/.../Services/EventsClient.swift` |
| **New** | `CarrierWave/Views/Events/EventsView.swift` |
| **New** | `CarrierWave/Views/Events/EventMapAnnotation.swift` |
| **New** | `CarrierWave/Views/Events/EventDetailView.swift` |
| **New** | `CarrierWave/Views/Events/EventSubmitView.swift` |
| **New** | `CarrierWave/Views/Events/MyEventsView.swift` |
| **Edit** | Navigation/tab setup (TBD based on current structure) |
| **Edit** | Push notification handler |
| **Edit** | `docs/FILE_INDEX.md` |
| **Edit** | `CHANGELOG.md` |

---

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Bad geocode from address | Map pin confirmation lets user correct coordinates |
| Stale pending events | Server auto-rejects after 14 days unreviewed |
| Max pending limit confusion | Show clear count of pending events + error message on limit hit |
| Push notification registration | Reuse existing push infrastructure if available |

## Out of Scope (v1)

- Recurring events / RRULE
- RSVP / capacity tracking
- Auto-approve for trusted submitters
- Web UI event submission
- Contact info fields (PII risk)
