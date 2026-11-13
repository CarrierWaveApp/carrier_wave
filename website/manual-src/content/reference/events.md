---
title: "Events"
description: "Map-based event discovery, submission, and management"
weight: 15
showToc: true
---

The Events feature lets you discover, create, and manage amateur radio events on an interactive map. Find nearby ham radio gatherings, club meetings, swap meets, field days, and special event stations.

## Overview

Events in Carrier Wave provide:

- **Map + list discovery** of nearby amateur radio events
- **Event submission** with geocoding and approval workflow
- **Multi-day event support**
- **My Events** management for events you've created
- **Push notifications** for upcoming events

## Discovering Events

### Map View

The Events map shows pins for all upcoming events within your visible area:

- **Color-coded pins** by event type (gathering, contest, swap meet, special event, etc.)
- **Cluster markers** when events are densely packed at lower zoom levels
- **Tap a pin** to see event details in a callout overlay
- **Your location** shown as a distinct marker for distance reference

### List View

Toggle to list view for a scrollable list of events:

- **Sorted by date** (soonest first) or **distance** (nearest first)
- **Event name, date, and type** shown on each row
- **Distance badge** showing miles/km from your location

### Switching Views

Toggle between map and list views using the segmented control at the top of the Events screen.

## Filtering Events

### Radius Filter

Set a search radius to limit displayed events:

- **10, 25, 50, 100, 250, 500 miles** (or km equivalent)
- Events outside the radius are hidden
- Default: 100 miles from your location

### Type Filter

Filter by event type:

- **All** - Show everything
- **Gathering** - Club meetings, ham breakfasts, eyeball QSOs
- **Contest** - Contest operating events and multi-operator stations
- **Swap Meet** - Equipment sales and trade events
- **Special Event** - Special event stations (e.g., museum ships, commemorations)
- **Field Day** - ARRL Field Day and similar events
- **Training** - License exam sessions, Elmer events, workshops

### Date Filter

- **Upcoming** - Events starting within the next 30 days (default)
- **This Week** - Events in the next 7 days
- **This Weekend** - Friday through Sunday events
- **Custom Range** - Select specific start and end dates

## Event Details

Tap an event to view its full details:

### Header

- **Event name** (large text)
- **Date and time** with timezone
- **Event type** badge
- **Distance** from your location

### Description

Free-form text describing the event, including:

- What to expect
- Talk-in frequency (if applicable)
- Parking and access information
- Contact details for the organizer

### Location

- **Address** with tap-to-open in Maps
- **Map preview** showing the exact location
- **Directions** button to open navigation

### Schedule

For multi-day events:

- **Day-by-day schedule** with start/end times
- **Highlight** for today's activities (if the event is currently running)

### Actions

- **Add to Calendar** - Create an iOS calendar event
- **Share** - Share event details via the iOS share sheet
- **Report** - Flag inappropriate or incorrect events

## Submitting Events

### Creating an Event

1. Tap the **+** button on the Events screen
2. Fill in event details:
   - **Name** (required)
   - **Type** (select from categories)
   - **Date and time** (start and end, with timezone)
   - **Location** - Enter an address or drop a pin on the map
   - **Description** - Details about the event
   - **Repeating** - For recurring events (weekly, monthly)
   - **Multi-day** - Toggle for events spanning multiple days
3. Tap **Submit**

### Geocoding

When you enter an address, Carrier Wave geocodes it to coordinates:

- **Address autocomplete** suggests locations as you type
- **Map preview** shows the resolved location
- **Adjust pin** - Drag the pin to fine-tune the location if geocoding isn't precise
- **Reverse geocode** - Drop a pin first, and Carrier Wave fills in the address

### Approval Workflow

Submitted events go through a review process:

1. **Submitted** - Your event enters the review queue
2. **Under Review** - A moderator is evaluating the submission
3. **Approved** - The event appears on the map for all users
4. **Rejected** - The event was not approved (reason provided)

Approval typically takes 24-48 hours. You'll receive a push notification when the status changes.

## My Events

### My Events View

Access your submitted events from the Events toolbar:

- **Pending** - Events awaiting approval
- **Approved** - Published events visible to all users
- **Rejected** - Events that were not approved, with rejection reason
- **Past** - Your events that have already occurred

### Editing Events

Tap an approved event to edit:

- **Name, description, and details** can be updated
- **Date changes** require re-approval if the event hasn't started
- **Location changes** require re-approval
- **Cancel event** marks it as cancelled (remains visible with a "Cancelled" badge)

### Deleting Events

Swipe left on an event in My Events to delete. Deleted events are removed from the map immediately.

## Multi-Day Events

For events spanning multiple days (e.g., Hamvention, Dayton):

- **Start and end dates** define the event span
- **Daily schedule** can be added for each day
- **Map pin** remains visible for the entire duration
- **"Happening Now"** badge appears during the event

## Push Notifications

### Notification Types

- **Event starting soon** - Alert 1 hour before an event you've bookmarked
- **New event nearby** - Alert when a new event is approved within your radius
- **Event update** - Alert when an event you've bookmarked changes details
- **Submission status** - Alert when your submitted event is approved or rejected

### Configuring Notifications

In **Settings -> Events**:

- Toggle each notification type on/off
- Set the "nearby" radius for new event alerts
- Set reminder time before bookmarked events (15 min, 30 min, 1 hour, 1 day)

## See Also

- [Map View](/reference/map/) - Map features and overlays
- [Community & Activity](/reference/community/) - Social features and clubs
- [Settings & Services](/reference/settings/) - Event notification settings
