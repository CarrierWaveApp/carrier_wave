# Design Spec: Hunt-First POTA Session Flow

**Date:** 2025-02-14
**Status:** Draft
**Linear Issue:** TBD

## Problem Statement

Many POTA activators arrive at a park without knowing their run frequency. Their natural workflow is:

1. Set up station at the park
2. **Hunt other activators first** -- work other POTA stations across various bands/frequencies
3. Find a clear frequency and begin calling CQ (running)

The current `SessionStartSheet` requires a frequency for POTA/SOTA sessions (`SessionStartValidation.canStart` returns `false` without one). This blocks activators from starting a session to log their hunted QSOs, forcing them to either pick an arbitrary frequency or skip logging hunts entirely.

## Goals

- Allow POTA/SOTA activators to start a session without a frequency
- Preserve the existing flow for users who already know their frequency
- Make the "no frequency yet" state visible and easy to resolve
- Ensure QSOs logged without a frequency still work for POTA upload (hunted QSOs need park reference, not necessarily a frequency)
- Do not require any model changes -- `LoggingSession.frequency` is already `Double?`

## Non-Goals

- Changing how the FREQ command works (it already sets frequency mid-session)
- Modifying the QSO model or POTA upload pipeline
- Automatically detecting when the user starts running

---

## 1. Session Start Sheet Changes

### 1.1 Remove Frequency as a Hard Requirement for POTA/SOTA

**File:** `SessionStartHelperViews.swift` (`SessionStartValidation`)

Change `canStart` and `disabledReason` so that POTA and SOTA no longer require `frequency != nil`. The only requirements become:

| Activation Type | Requirements |
|-----------------|-------------|
| POTA | Callsign + Park reference |
| SOTA | Callsign + Summit reference |
| Casual | Callsign |

The frequency field remains in the form and is still prominently shown. Users who know their frequency enter it as before -- nothing changes for them. The "Start" button simply no longer grays out when frequency is empty for POTA/SOTA.

### 1.2 Frequency Section Footer Update

**File:** `SessionStartSheet.swift` (`frequencySection`)

When activation type is POTA or SOTA and the frequency field is empty, show an additional footer hint below the existing format help text:

```
Optional for POTA -- you can set your frequency later with the FREQ command or the band picker.
```

For SOTA:
```
Optional for SOTA -- you can set your frequency later with the FREQ command or the band picker.
```

This uses `.foregroundStyle(.secondary)` with `.font(.caption)`, consistent with existing section footers.

When activation type is `.casual` or frequency is already filled in, do not show this extra footer.

### 1.3 No Toggle, No Extra Entry Point

There is no "Hunt First" toggle, radio button, or separate button. The design relies on progressive disclosure: the frequency field is present and obvious, but simply not mandatory. Users who know their frequency fill it in. Users who do not leave it blank. The system adapts.

**Rationale:** Adding a toggle or mode selector would increase cognitive load and require users to understand an abstract concept ("hunt mode") before they can start logging. The simpler approach -- just making frequency optional -- matches how other fields (power, equipment, notes) already work.

---

## 2. In-Session Experience: No Frequency Set

### 2.1 Session Header: Frequency Placeholder

**File:** `LoggerView.swift` (`activeSessionHeader`)

Currently, when `session.frequency` is `nil`, the frequency text is simply absent from the header. After this change, show a tappable placeholder instead:

**Current behavior (frequency set):**
```
[US-1234 Park Name]  14.060 MHz  [20m v]  [CW v]  [23m]
```

**New behavior (no frequency):**
```
[US-1234 Park Name]  [Set Freq v]  [CW v]  [23m]
```

The `[Set Freq v]` element replaces both the frequency text and the band badge. It is a single tappable capsule styled as an attention-drawing element:

```swift
Button {
    showBandEditSheet = true
} label: {
    HStack(spacing: 2) {
        Text("Set Freq")
        Image(systemName: "chevron.up.chevron.down")
            .font(.system(size: 8))
            .foregroundStyle(.secondary)
    }
    .font(.caption.weight(.medium))
    .padding(.horizontal, 6)
    .padding(.vertical, 2)
    .background(Color.orange.opacity(0.2))
    .clipShape(Capsule())
}
.buttonStyle(.plain)
```

The orange background (`Color.orange.opacity(0.2)`) distinguishes it from the normal blue band/mode badges, signaling "action needed" without being alarming. Tapping it opens the existing `SessionBandEditSheet`.

Once a frequency is set, this reverts to the standard frequency text + blue band badge behavior.

### 2.2 Hunting Banner

**File:** `LoggerView.swift` (new view, positioned below `FrequencyWarningBannerContainer`)

When the session is POTA/SOTA, has no frequency set, and the user has not dismissed the banner, show a contextual info banner:

```swift
HStack(spacing: 12) {
    Image(systemName: "scope")
        .font(.system(size: 20))
        .foregroundStyle(.blue)

    VStack(alignment: .leading, spacing: 2) {
        Text("Hunting Mode")
            .font(.subheadline)
            .fontWeight(.semibold)
        Text("Log hunted QSOs now. Set your run frequency when ready.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    Spacer()

    Button {
        showBandEditSheet = true
    } label: {
        Text("Set Freq")
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.blue)
            .foregroundStyle(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
    .buttonStyle(.plain)
}
.padding()
.background(Color.blue.opacity(0.1))
.clipShape(RoundedRectangle(cornerRadius: 10))
.overlay(
    RoundedRectangle(cornerRadius: 10)
        .stroke(Color.blue.opacity(0.3), lineWidth: 1)
)
.padding(.horizontal)
.padding(.top, 8)
```

The banner includes a "Set Freq" action button that opens `SessionBandEditSheet`, giving the user a one-tap path to set their frequency without needing to know the FREQ command.

**Dismissal:** The banner has no explicit dismiss button. It disappears automatically when a frequency is set. This is intentional -- the banner is guidance, not a warning, and its removal is the reward for completing the action.

**State tracking:** Use a simple `@State private var` -- no persistence needed. The banner reappears if the user removes their frequency (unlikely but handled correctly).

### 2.3 QSO Behavior Without Frequency

When QSOs are logged without a session frequency:

- **Band:** "Unknown" (existing behavior from `LoggingSessionManager.logQSO`)
- **Frequency:** `nil` on the QSO record (existing behavior)
- **Park reference:** Still set from session (hunted QSOs get proper `parkReference` for POTA two-fer credit)
- **POTA upload:** QSOs with band "Unknown" or no frequency are flagged in `SyncService+Upload` with a warning but are not blocked from upload. The POTA system accepts QSOs without explicit frequency.

**No changes needed** to `logQSO` or the QSO model. The existing code already handles `nil` frequency gracefully.

### 2.4 Per-QSO Frequency Override (Future Enhancement)

A future enhancement could allow setting frequency per-QSO during hunting (since each hunted station is on a different frequency). This is out of scope for this design but worth noting. The QSO model already has its own `frequency` field that could differ from the session frequency. Currently, `logQSO` always copies `session.frequency` to the QSO.

---

## 3. Transition to Running

### 3.1 Setting Frequency Mid-Session

There are three ways to set a frequency mid-session, all of which already exist:

1. **FREQ command:** Type `FREQ 14.060` in the callsign input field. The existing command handler in `LoggerView` calls `sessionManager.updateFrequency()`.

2. **Band picker button:** Tap the `[Set Freq v]` capsule (or the existing band badge if frequency was set). Opens `SessionBandEditSheet` with band options for the current mode.

3. **Band edit sheet:** Already wired to the header. Selecting a band sets the frequency.

**No new UI is needed for the transition.** The existing mechanisms are sufficient. The hunting banner's "Set Freq" button provides a discoverable path to `SessionBandEditSheet`.

### 3.2 Post-Frequency-Set Confirmation

When the user sets a frequency for the first time during a session that started without one, show a toast confirmation:

```swift
LoggerToastView(
    icon: "checkmark.circle.fill",
    color: .green,
    title: "Frequency Set",
    message: "Now on \(FrequencyFormatter.formatWithUnit(freq)) (\(band))"
)
```

This uses the existing `LoggerToastView` system. The toast auto-dismisses after 3 seconds (standard toast behavior).

### 3.3 Backfill Previously Logged QSOs

When a frequency is first set on a session that had no frequency, **do not** retroactively update the band/frequency on previously logged QSOs. Hunted QSOs were legitimately logged without a specific frequency (the user was tuning across bands). Backfilling would incorrectly assign a single run frequency to QSOs that were actually made on different frequencies.

**Rationale:** This matches real-world behavior. When hunting, each QSO is on a different frequency. The session's run frequency is only relevant to QSOs logged after it is set.

---

## 4. Ending a Session Without Frequency

### 4.1 End Session Behavior

If the user ends a POTA/SOTA session that never had a frequency set:

- **Session ends normally.** No blocking confirmation.
- **QSOs remain with band "Unknown" and no frequency.** This is valid data -- the user was hunting only.
- **POTA upload prompt** (`POTAUploadPromptSheet`) still appears if there are unuploaded QSOs. The QSOs still have park references and are valid for POTA upload.

### 4.2 Soft Nudge on End

When the user taps "END" and the session has no frequency and has logged QSOs, add a note to the existing confirmation dialog message:

**Current message:**
```
End keeps your 5 QSOs for sync. Delete hides them permanently.
```

**Updated message (when no frequency was ever set):**
```
End keeps your 5 QSOs for sync. QSOs were logged without a frequency and will show as "Unknown" band. Delete hides them permanently.
```

This is informational, not blocking. The user can still end the session.

### 4.3 Sessions With Mixed QSOs

If the user hunted 3 QSOs without a frequency, then set their frequency and logged 5 more running QSOs:

- The first 3 QSOs have band "Unknown" and no frequency
- The last 5 QSOs have the correct band and frequency
- Both sets have the park reference
- All 8 QSOs are valid for POTA upload
- The end-session dialog shows the standard message (frequency is now set)

---

## 5. Self-Spotting Considerations

### 5.1 POTA Spot Timer

The `LoggingSessionManager` starts an auto-spot timer for POTA activations in `startSession()`. Currently, spotting requires a frequency.

**Change:** Skip auto-spotting when `session.frequency == nil`. The spot timer can still start (for simplicity), but the spot-posting logic should check for a frequency and silently skip if none is set.

Once the user sets a frequency, the next auto-spot interval will post a spot with the correct frequency. Alternatively, if the user wants to spot immediately after setting their frequency, they can use the existing SPOT command.

### 5.2 Initial Spot on Frequency Set

When a POTA session first gets a frequency (was `nil`, now has a value), automatically trigger a POTA spot. This mimics what happens at session start for users who provide a frequency upfront.

**Implementation:** In `LoggingSessionManager.updateFrequency()`, check if the old frequency was `nil` and the session is POTA. If so, trigger a spot post (same logic as the initial spot in `startSession()`).

---

## 6. Visual Summary

### States and Their Visual Indicators

| State | Header | Banner | Badge Color |
|-------|--------|--------|------------|
| **Session not started** | "No Active Session" | -- | -- |
| **POTA, no frequency** | `[Park]  [Set Freq v]  [CW v]  [12m]` | Hunting Mode banner (blue) | Orange "Set Freq" capsule |
| **POTA, frequency set** | `[Park]  14.060 MHz  [20m v]  [CW v]  [12m]` | None | Blue band capsule (normal) |
| **Casual, no frequency** | `[Title]  [Band v]  [CW v]  [12m]` | None | Blue "Band" capsule (existing) |

### Color Semantics

| Color | Meaning in This Feature |
|-------|------------------------|
| `Color.orange.opacity(0.2)` | "Set Freq" capsule -- action needed |
| `Color.blue.opacity(0.1)` | Hunting banner background -- informational |
| `.blue` | "Set Freq" button in banner -- primary action |
| `.green` | Toast confirmation when frequency is set |

---

## 7. Implementation Plan

### Phase 1: Core Changes (Minimum Viable)

1. **`SessionStartHelperViews.swift`** -- Remove frequency requirement from `SessionStartValidation` for POTA/SOTA. Update `disabledReason` to not mention frequency.

2. **`SessionStartSheet.swift`** -- Add conditional footer text to `frequencySection` explaining frequency is optional for POTA/SOTA.

3. **`LoggerView.swift`** (`activeSessionHeader`) -- Add the orange "Set Freq" placeholder capsule when session has no frequency. Replace the current `if let freq = session.frequency` block with a conditional that shows either the frequency text + band badge (when set) or the "Set Freq" capsule (when nil and POTA/SOTA).

4. **`LoggerView.swift`** -- Add the Hunting Mode banner below `FrequencyWarningBannerContainer`, shown when POTA/SOTA session has no frequency.

### Phase 2: Polish

5. **`LoggerView.swift`** -- Show toast on first frequency set during a hunt-first session.

6. **`LoggingSessionManager+Spotting.swift`** -- Skip POTA spot posting when frequency is nil. Trigger initial spot when frequency is first set.

7. **`LoggerView.swift`** (`handleEndSession`) -- Update end-session confirmation message when session has no frequency.

### Phase 3: Future Enhancements (Out of Scope)

- Per-QSO frequency entry for hunted contacts
- POTA spot integration that auto-fills frequency from spotted station
- "Quick QSY" button that copies a spotted activator's frequency for hunting
- Backfill option to assign frequency/band to earlier QSOs

---

## 8. Files Changed

| File | Change |
|------|--------|
| `CarrierWave/Views/Logger/SessionStartHelperViews.swift` | Remove frequency from POTA/SOTA validation |
| `CarrierWave/Views/Logger/SessionStartSheet.swift` | Add optional-frequency footer hint |
| `CarrierWave/Views/Logger/LoggerView.swift` | Add "Set Freq" header placeholder, hunting banner, toast, end-session message update |
| `CarrierWave/Services/LoggingSessionManager+Spotting.swift` | Guard spot posting on frequency presence, trigger spot on first frequency set |

---

## 9. Testing Checklist

- [ ] POTA session can start without frequency (park reference still required)
- [ ] SOTA session can start without summit reference still blocks start
- [ ] SOTA session can start without frequency (summit reference still required)
- [ ] Casual session start is unchanged
- [ ] User who enters frequency at session start sees no difference
- [ ] "Set Freq" capsule appears in header when POTA session has no frequency
- [ ] Tapping "Set Freq" opens band picker
- [ ] Hunting banner appears below warning banners
- [ ] Hunting banner disappears when frequency is set
- [ ] FREQ command sets frequency and removes banner/placeholder
- [ ] QSOs logged without frequency have band "Unknown"
- [ ] QSOs logged without frequency still have park reference
- [ ] QSOs logged after frequency is set have correct band
- [ ] Toast appears on first frequency set
- [ ] POTA auto-spot skips when no frequency
- [ ] POTA spot fires when frequency is first set
- [ ] End session works with no frequency
- [ ] End session message mentions "Unknown" band when no frequency was set
- [ ] POTA upload prompt still appears for hunt-only sessions
- [ ] Save as Defaults works correctly with empty frequency
