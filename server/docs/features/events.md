# User-Submitted Events

## Summary

Community-submitted ham radio events (club meetings, swap meets, hamfests, etc.) with admin moderation and proximity-based discovery. Users submit events and browse nearby events in the **CarrierWave iOS app** (separate repo). Admins review and approve/reject events via the **iOS admin app** (`ios-admin/` in this repo). The **server** (this repo) provides the API endpoints for both clients.

## Repo Scope

| Component | Repo | What's built |
|-----------|------|--------------|
| Server API endpoints | **This repo** (`challenges-server`) | Migration, models, db layer, handlers, router |
| Admin app moderation UI | **This repo** (`ios-admin/`) | Pending events list, review screen, submitter history |
| User event submission & discovery | **CarrierWave app** (separate repo) | Submit form, map + list view, my events, push notifications |

## Data Model

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| `id` | UUID | auto | |
| `name` | string(200) | yes | |
| `description` | text(2000) | no | |
| `event_type` | enum | yes | `club_meeting`, `swap_meet`, `field_day`, `special_event`, `hamfest`, `net`, `other` |
| `start_date` | timestamptz | yes | |
| `end_date` | timestamptz | no | null = single-moment event |
| `timezone` | string | yes | IANA identifier, e.g. `America/New_York` |
| `venue_name` | string(200) | no | e.g. "VFW Hall" |
| `address` | text | yes | Street address |
| `city` | string | yes | |
| `state` | string | no | |
| `country` | string | yes | |
| `latitude` | float | yes | Client-side geocoded |
| `longitude` | float | yes | Client-side geocoded |
| `cost` | string(100) | no | Free-text, e.g. "Free", "$10 at door" |
| `url` | string | no | External event page |
| `submitted_by` | string | yes | Submitter's callsign |
| `status` | enum | yes | `pending`, `approved`, `rejected` |
| `reviewed_by` | string | no | Admin who reviewed |
| `reviewed_at` | timestamptz | no | |
| `rejection_reason` | text | no | |
| `created_at` | timestamptz | auto | |
| `updated_at` | timestamptz | auto | |

PostGIS `geography` column (`location`) + GIST index for proximity queries.

## API Endpoints

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

### Admin

- `GET /v1/admin/events` — List events with status filter (defaults to `pending`)
- `PUT /v1/admin/events/{id}` — Edit any event fields (fix typos, adjust coordinates before approving)
- `PUT /v1/admin/events/{id}/review` — Approve or reject: `{ "action": "approve"|"reject", "reason": "..." }`
- `DELETE /v1/admin/events/{id}` — Hard delete any event

---

## CarrierWave App Requirements (Separate Repo)

> The following sections describe requirements for the **CarrierWave iOS app** (separate repo).
> They are documented here for completeness — this repo does NOT implement these screens.

### Event Discovery: Map + List Hybrid View

- Upper portion: MapKit map with pins for nearby approved events.
- Lower portion: Scrollable list sorted by date.
- Uses device location by default. User can drag map or search a location to browse other areas.
- Radius control: configurable (10 / 25 / 50 / 100 km) via segmented control or picker.
- Filters: event type picker (multi-select), date range.

### Event Detail Sheet

Tap a pin or list row to see:
- Name, event type badge
- Date/time displayed in event's timezone with label (e.g. "7:00 PM ET")
- Venue name, address, map snippet
- Cost (if set)
- Description
- External link button (if URL set)
- Submitter callsign

### Event Submission Flow

1. **"Submit Event" button** — accessible from the events view (floating action button or nav bar).
2. **Form fields** (single scrollable form):
   - Name (required, text field)
   - Event type (required, picker wheel / segmented)
   - Start date & time (required, date picker)
   - End date & time (optional, date picker — hidden by default, "Add end time" toggle)
   - Timezone (auto-detected from selected location, editable picker)
   - Venue name (optional, text field)
   - Address (required, text field with MapKit autocomplete suggestions)
   - Map confirmation (inline map with draggable pin — geocoded from address, user can adjust)
   - City / State / Country (auto-populated from geocode, editable)
   - Cost (optional, text field, placeholder: "e.g. Free, $5")
   - Website URL (optional, text field with URL keyboard)
   - Description (optional, multi-line text view, 2000 char limit with counter)
3. **Validation**: Client-side validation before submit. Required fields highlighted if empty. Coordinates must be present.
4. **Submission confirmation**: "Your event has been submitted for review. You'll be notified when it's approved." Dismiss to events list.

### My Events

- Accessible from profile/settings or a "My Events" row in the events section.
- List of all events submitted by the user, grouped by status:
  - **Pending** — yellow indicator, "Awaiting review"
  - **Approved** — green indicator, "Live"
  - **Rejected** — red indicator, shows rejection reason
- Tap to view full detail with **Edit** and **Delete** actions.
- Edit opens the same form pre-filled. Submitting shows a note if key-field edits will reset approval.
- Delete shows a destructive confirmation alert.

### Push Notifications

- **Push on approval**: "Your event '[name]' has been approved and is now visible to nearby operators."
- **Push on rejection**: "Your event '[name]' was not approved. Reason: [reason]." Deep-links to the event detail so user can edit and resubmit.

---

## iOS Admin App: Event Moderation (This Repo — `ios-admin/`)

### Pending Events List

- New **"Events"** section in the admin app navigation.
- **Badge count** on the Events nav item showing number of pending events.
- List view showing pending events sorted by submission date (oldest first — FIFO review).
- Each row shows: event name, type badge, submitter callsign, city/state, submitted date, "time waiting" label (e.g. "2 days ago").
- **Filter bar**: All / Pending / Approved / Rejected. Defaults to Pending.
- **Pull-to-refresh**.

### Event Detail / Review Screen

Tap a pending event to open the review screen:

- **Read-only section** (top):
  - Submitter callsign (tappable to see their submission history / other events)
  - Submission timestamp
- **Editable fields** (admin can fix before approving):
  - Name, description, event type, dates, timezone, venue name, address, cost, URL
  - Inline map showing pin location (draggable by admin to correct)
- **Action buttons** (bottom, sticky):
  - **Approve** (green) — one-tap, confirms with brief haptic
  - **Reject** (red) — opens a sheet for rejection reason (text field + common quick-pick reasons: "Incomplete information", "Duplicate event", "Not ham radio related", "Inappropriate content"). Reason is sent in push notification to submitter.
- **Delete** — in a "..." overflow menu. Hard deletes with confirmation alert.

### Admin Push Notifications

- **New pending event**: "New event submitted: '[name]' in [city, state] by [callsign]". Tapping opens the review screen directly.
- Badge count on app icon reflects pending review count.

### Submitter History

From the review screen, tapping the submitter callsign shows:
- Total events submitted
- Approval / rejection counts
- List of their past submissions with statuses
- Helps admin gauge trustworthiness

## Key Decisions

| Decision | Choice |
|----------|--------|
| Geocoding | Client-side (iOS sends lat/lon) |
| Recurrence | One-off events only |
| Edit re-review | Key fields only (name, description, address, venue, location) |
| Timezone | Store IANA timezone identifier |
| Venue name | Separate optional field |
| Cost | Optional free-text field |
| Event types | `club_meeting`, `swap_meet`, `field_day`, `special_event`, `hamfest`, `net`, `other` |
| Past events | Kept in DB, hidden by default, browsable via `include_past` param |
| Spam prevention | Max 10 pending events per callsign |
| Location input | Address autocomplete + draggable map pin confirmation |
| User notifications | Push on approval and rejection |
| Admin review UX | List with detail view, badge counts |
| Admin editing | Can edit event fields before approving |
| Discovery UX | Map + list hybrid with radius control |

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Spam/garbage submissions | Admin moderation gate + 10 pending cap per callsign |
| Unverified callsigns | Moderation catches bad actors; admin can revoke tokens |
| Stale pending events | Auto-reject after 14 days unreviewed |
| Slow moderation | Push notifications to admin app on new submissions |
| Bad geocode from address | Map pin confirmation lets user correct coordinates |
| Admin overwhelm | Submitter history helps assess trust; quick-pick rejection reasons speed review |

## Out of Scope (v1)

- Recurring events / RRULE
- RSVP / capacity tracking
- Auto-approve for trusted submitters
- Cross-instance event federation
- Contact info fields (PII risk)
- Web UI event submission (API-ready, but iOS app only for v1)
