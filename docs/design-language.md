# Carrier Wave Design Language Specification

This document defines the visual and interaction design patterns used throughout Carrier Wave. Follow these guidelines to ensure consistency across all views.

## Table of Contents

1. [Design Principles](#design-principles)
2. [Color System](#color-system)
3. [Typography](#typography)
4. [Spacing & Layout](#spacing--layout)
5. [Components](#components)
6. [Iconography](#iconography)
7. [Animation & Motion](#animation--motion)
8. [Accessibility](#accessibility)
9. [Platform Adaptations](#platform-adaptations)

---

## Design Principles

### 1. Amateur Radio First
The interface prioritizes the unique needs of amateur radio operators:
- **Callsigns are monospaced** for easy reading and pattern recognition
- **Frequencies show appropriate precision** (sub-kHz when relevant)
- **RST reports default intelligently** (599 for CW/digital, 59 for phone)
- **Band/mode badges provide quick visual scanning**

### 2. Progressive Disclosure
Complex functionality is hidden until needed:
- "More Fields" expansion in the logger
- Collapsible disclosure groups in settings
- Detail views accessed via navigation links
- Command system for power users (FREQ, MODE, SPOT, etc.)

### 3. Performance Over Polish
Large datasets (50k+ QSOs) must remain responsive:
- Progressive loading with skeleton states
- Deferred computation with placeholder values ("--")
- Reduced opacity (0.6) while loading
- Background computation with cooperative yielding

### 4. Defensive Design
Destructive actions require confirmation:
- Type "delete" to confirm session deletion
- Confirmation dialogs for data clearing
- Clear distinction between "End" and "Delete"

---

## Color System

### Background Hierarchy

| Context | Color | Usage |
|---------|-------|-------|
| Base background | `Color(.systemGroupedBackground)` | Main view backgrounds (ScrollView, TabView) |
| Card background | `Color(.systemGray6)` | Card containers, stat boxes parent |
| Field background | `Color(.systemGray5)` | Stat boxes, input field backgrounds |
| Input field | `Color(.tertiarySystemGroupedBackground)` | Text fields within cards |
| Secondary card | `Color(.secondarySystemGroupedBackground)` | Session headers, QSO lists |

### Semantic Colors

| Color | Usage |
|-------|-------|
| `.blue` | Default accent, stat icons, band/mode badges, informational states |
| `.green` | Success, QSO logged, session QSO count, POTA first contact |
| `.red` | Destructive actions, errors, END session button |
| `.orange` | Warnings, POTA duplicate band |
| `.purple` | Commands (FREQ, MODE, SPOT, etc.) |
| `.yellow` | Friend spotted alerts |

### Badge Colors

```swift
// Band/Mode badges
.padding(.horizontal, 6)
.padding(.vertical, 2)
.background(Color.blue.opacity(0.2))
.clipShape(Capsule())

// License class badge
.background(Color.accentColor.opacity(0.2))
.clipShape(Capsule())

// Status badges (e.g., NEW BAND, DUPE)
.background(Color.blue) // or .orange for warnings
.foregroundStyle(.white)
.clipShape(RoundedRectangle(cornerRadius: 3))
```

### State Colors

| State | Implementation |
|-------|----------------|
| Loading | Opacity 0.6, "--" placeholder |
| Disabled | System-provided disabled state |
| Focused | Purple stroke for command input |
| Error | Red background opacity 0.15 |
| Success | Green background opacity 0.15 |

---

## Typography

### Font Hierarchy

| Element | Style | Example |
|---------|-------|---------|
| View title | `.headline` | "Activity", "Statistics", "Favorites" |
| Card subtitle | `.subheadline.weight(.semibold)` | "Session Log" |
| Body text | `.body` or `.subheadline` | List items, descriptions |
| Caption | `.caption` | Secondary info, timestamps |
| Tiny caption | `.caption2` | Tertiary info, footer text |

### Monospaced Usage

**Always monospaced:**
- Callsigns: `.font(.headline.monospaced())` or `.font(.subheadline.weight(.semibold).monospaced())`
- Frequencies: `.font(.caption.monospaced())` or `.font(.title3.monospaced())`
- RST reports: `.font(.caption2.monospaced())`
- UTC times: `.font(.caption.monospaced())`
- Grids: `.font(.subheadline.monospaced())`
- Version numbers

**Never monospaced:**
- Names, locations, notes
- UI labels and descriptions
- Navigation titles

### Weight Guidelines

| Weight | Usage |
|--------|-------|
| `.bold` | Stat values, streak numbers |
| `.semibold` | Card titles, callsigns in lists, section headers |
| `.medium` | Action buttons, badge text |
| Regular | Body text, descriptions |

### Number Formatting

```swift
// Frequencies with unit
FrequencyFormatter.formatWithUnit(freq) // "14.060 MHz"

// Frequencies without unit
FrequencyFormatter.format(freq) // "14.060"

// RST reports
"\(qso.rstSent ?? "599")/\(qso.rstReceived ?? "599")"

// QSO counts
"\(count) QSO\(count == 1 ? "" : "s")"

// Relative time
Text(lastSync, style: .relative) + Text(" ago")
```

---

## Spacing & Layout

### Spacing Scale

| Value | Usage |
|-------|-------|
| 2 | Activity grid cell spacing |
| 4 | Between icon and text in tight layouts, vertical spacing in VStacks |
| 6 | Badge padding vertical, small list item padding |
| 8 | Standard horizontal spacing in HStacks, field margins |
| 12 | Card internal padding, standard VStack spacing |
| 16 | Between cards, page-level VStack spacing |
| 24 | Large section separation, tour content padding |

### Card Pattern

```swift
VStack(alignment: .leading, spacing: 12) {
    // Header row
    HStack {
        Text("Title")
            .font(.headline)
        Spacer()
        Text("Secondary")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    // Content
    ...
}
.padding() // 16pt default
.background(Color(.systemGray6))
.clipShape(RoundedRectangle(cornerRadius: 12))
```

### Stat Box Pattern

```swift
VStack(spacing: 4) {
    Image(systemName: icon)
        .font(.title3)
        .foregroundStyle(.blue)
    Text(value)
        .font(.title2)
        .fontWeight(.bold)
    Text(title)
        .font(.caption)
        .foregroundStyle(.secondary)
}
.frame(maxWidth: .infinity)
.padding(.vertical, 8)
.background(Color(.systemGray5))
.clipShape(RoundedRectangle(cornerRadius: 8))
```

### List Row Pattern

```swift
HStack(spacing: 12) {
    // Leading content (icon or time)
    Image(systemName: icon)
        .font(.title3)
        .foregroundStyle(.blue)
        .frame(width: 32) // Fixed width for alignment

    // Main content
    VStack(alignment: .leading, spacing: 2) {
        Text(primary)
            .font(.subheadline)
            .fontWeight(.medium)
        Text(secondary)
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    Spacer()

    // Trailing content
    Image(systemName: "chevron.right")
        .font(.caption)
        .foregroundStyle(.tertiary)
}
.padding(.vertical, 8)
```

### Grid Layouts

```swift
// iPhone: 3 columns
// iPad: 6 columns
var statsGridColumns: [GridItem] {
    if horizontalSizeClass == .regular {
        Array(repeating: GridItem(.flexible()), count: 6)
    } else {
        Array(repeating: GridItem(.flexible()), count: 3)
    }
}
```

---

## Components

### Buttons

**Primary action (Log QSO, Save):**
```swift
Button { ... } label: {
    Text("Log QSO")
        .font(.headline)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
}
.buttonStyle(.borderedProminent)
.tint(.green)
```

**Secondary action (Start session):**
```swift
Button { ... } label: {
    Label("Start", systemImage: "play.fill")
        .font(.subheadline.weight(.medium))
}
.buttonStyle(.borderedProminent)
```

**Destructive action:**
```swift
Button(role: .destructive) { ... } label: {
    Text("Delete")
}
.buttonStyle(.borderedProminent)
.tint(.red)
```

**Toolbar button:**
```swift
Button { ... } label: {
    Image(systemName: "arrow.triangle.2.circlepath")
}
// No explicit style needed in toolbar
```

**Plain button (inline actions):**
```swift
Button { ... } label: {
    Label("Restore", systemImage: "arrow.uturn.backward")
        .font(.subheadline)
}
.buttonStyle(.bordered)
```

**Session END button:**
```swift
Text("END")
    .font(.subheadline.weight(.semibold))
    .foregroundStyle(.white)
    .padding(.horizontal, 12)
    .padding(.vertical, 6)
    .background(Color.red)
    .clipShape(RoundedRectangle(cornerRadius: 6))
```

### Text Fields

**Primary input (callsign):**
```swift
TextField("Callsign or command...", text: $callsignInput)
    .font(.title3.monospaced())
    .textInputAutocapitalization(.characters)
    .autocorrectionDisabled()
```

**Compact field with label:**
```swift
VStack(alignment: .leading, spacing: 2) {
    Text(label)
        .font(.caption2)
        .foregroundStyle(.secondary)
    TextField(placeholder, text: $text)
        .font(.subheadline.monospaced())
        .textInputAutocapitalization(.characters)
        .autocorrectionDisabled()
        .padding(.horizontal, 8)
        .frame(height: 36)
        .background(Color(.tertiarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
}
```

### Badges

**Band/Mode badge:**
```swift
Text(band)
    .font(.caption.weight(.medium))
    .padding(.horizontal, 6)
    .padding(.vertical, 2)
    .background(Color.blue.opacity(0.2))
    .clipShape(Capsule())
```

**Status badge (solid):**
```swift
Text("NEW BAND")
    .font(.caption2.weight(.bold))
    .padding(.horizontal, 4)
    .padding(.vertical, 1)
    .background(Color.blue)
    .foregroundStyle(.white)
    .clipShape(RoundedRectangle(cornerRadius: 3))
```

### Banners

**Warning/info banner:**
```swift
HStack(spacing: 8) {
    Image(systemName: "star.fill")
        .foregroundStyle(.blue)
    VStack(alignment: .leading, spacing: 2) {
        Text("New Band!")
            .font(.subheadline.weight(.semibold))
        Text("Previously worked on 20m, 40m")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
    Spacer()
}
.padding()
.background(Color.blue.opacity(0.15))
.clipShape(RoundedRectangle(cornerRadius: 12))
```

### Toasts

```swift
HStack(spacing: 12) {
    Image(systemName: icon)
        .font(.system(size: 20))
        .foregroundStyle(color)

    VStack(alignment: .leading, spacing: 2) {
        Text(title)
            .font(.subheadline)
            .fontWeight(.semibold)
        Text(message)
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    Spacer()

    Button(action: dismiss) {
        Image(systemName: "xmark")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
    }
}
.padding()
.background(.ultraThinMaterial)
.clipShape(RoundedRectangle(cornerRadius: 12))
.shadow(color: .black.opacity(0.15), radius: 8, y: 4)
```

### Sheets

**Standard presentation:**
```swift
.sheet(isPresented: $showSheet) {
    SheetContent()
}
// Default detent

.presentationDetents([.medium]) // For smaller sheets
.presentationDetents([.height(200)]) // For fixed height
.presentationDragIndicator(.visible)
.interactiveDismissDisabled() // For required completion (tours)
```

### Activity Grid (GitHub-style)

```swift
RoundedRectangle(cornerRadius: 2)
    .fill(colorFor(count: count))
    .frame(width: cellSize, height: cellSize)

func colorFor(count: Int) -> Color {
    if count == 0 {
        return Color(.systemGray5)
    }
    let intensity = min(Double(count) / Double(maxCount), 1.0)
    return Color.green.opacity(0.3 + intensity * 0.7)
}
```

### Chat Bubbles (CW Transcription)

```swift
VStack(alignment: isMe ? .trailing : .leading, spacing: 6) {
    // Header, content, footer
}
.padding(12)
.background(isMe ? Color.accentColor.opacity(0.15) : Color(.systemGray5))
.clipShape(RoundedRectangle(cornerRadius: 12))
```

---

## Iconography

### SF Symbols Usage

All icons use SF Symbols. Common icons:

| Icon | Usage |
|------|-------|
| `square.grid.2x2` | Dashboard |
| `pencil.and.list.clipboard` | Logger |
| `list.bullet` | Logs |
| `waveform` | CW decoder |
| `map` | Map view |
| `person.2` | Activity/Friends |
| `ellipsis` | More menu |
| `arrow.triangle.2.circlepath` | Sync |
| `checkmark.circle.fill` | Connected/Success |
| `exclamationmark.triangle.fill` | Warning |
| `xmark.circle.fill` | Error/Clear |
| `antenna.radiowaves.left.and.right` | Radio/Spot |
| `leaf` | POTA activations |
| `globe` | DXCC entities |
| `square.grid.3x3` | Grids |
| `dial.medium.fill` | Frequency |
| `person.2.fill` | Best friend |
| `scope` | Best hunter |

### Icon Sizing

| Context | Font |
|---------|------|
| Tab bar | System default |
| Stat box | `.title3` |
| List row leading | `.title3` with `.frame(width: 32)` |
| Badge/inline | `.caption` or `.caption2` |
| Large decorative | `.system(size: 48)` |
| Toast | `.system(size: 20)` |

### Icon Colors

- Primary action icons: `.blue`
- Success icons: `.green`
- Warning icons: `.orange`
- Error icons: `.red`
- Command icons: `.purple`
- Secondary/navigation: `.secondary` or `.tertiary`

---

## Animation & Motion

### Standard Transitions

**Card/panel entry:**
```swift
.transition(.move(edge: .top).combined(with: .opacity))
// or
.transition(.move(edge: .bottom).combined(with: .opacity))
```

**Asymmetric (different in/out):**
```swift
.transition(
    .asymmetric(
        insertion: .move(edge: .top).combined(with: .opacity),
        removal: .opacity
    )
)
```

### Spring Animation

**Panel appearance:**
```swift
.animation(.spring(response: 0.3, dampingFraction: 0.7), value: showPanel)
```

**Toast appearance:**
```swift
withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
    currentToast = toast
}
```

### Ease Animations

**Dismissal:**
```swift
withAnimation(.easeOut(duration: 0.2)) {
    currentToast = nil
}
```

**Expand/collapse:**
```swift
withAnimation(.easeInOut(duration: 0.2)) {
    showMoreFields.toggle()
}
```

### Gesture-driven Animations

**Swipe to dismiss:**
```swift
DragGesture()
    .onEnded { value in
        if value.translation.height > 80 || value.predictedEndTranslation.height > 150 {
            withAnimation(.easeOut(duration: 0.2)) {
                isPresented = false
            }
        }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            dragOffset = 0
        }
    }
```

### Disabled Animations

For form resets after logging:
```swift
var transaction = Transaction()
transaction.disablesAnimations = true
withTransaction(transaction) {
    // Reset form fields
}
```

---

## Accessibility & HIG Compliance

### Icon-Only Buttons MUST Have Accessibility Labels

Every button that shows only an SF Symbol (no visible text) **must** have an `.accessibilityLabel`. VoiceOver users cannot interact with unlabeled icon buttons.

```swift
// REQUIRED — icon-only buttons always need a label
Button { ... } label: {
    Image(systemName: "square.and.arrow.up")
}
.accessibilityLabel("Share daily activity")

// Navigation links with icon-only labels too
NavigationLink { SettingsView() } label: {
    Image(systemName: "gearshape")
}
.accessibilityLabel("Activity log settings")
```

### Decorative Images Must Be Hidden

Icons used purely for decoration (empty state illustrations, separator dots, status indicators with adjacent text) must be hidden from VoiceOver:

```swift
Image(systemName: "antenna.radiowaves.left.and.right")
    .accessibilityHidden(true)
```

For status indicators where color alone conveys meaning (e.g., age dots), wrap in a combined element with a text label:

```swift
HStack {
    Circle().fill(ageColor).frame(width: 8, height: 8)
        .accessibilityHidden(true)
    Text(timeAgo)
}
.accessibilityElement(children: .combine)
.accessibilityLabel("Spotted \(timeAgo) ago")
```

### Minimum Touch Targets: 44×44pt

All interactive elements must meet the 44×44pt minimum. This is a hard HIG requirement.

```swift
// Small icon buttons — enforce minimum frame
Button { ... } label: {
    Image(systemName: "line.3.horizontal.decrease")
        .font(.subheadline)
}
.frame(minWidth: 44, minHeight: 44)

// Text fields and form controls — use 44pt height
TextField("599", text: $rst)
    .frame(width: rstFieldWidth, height: 44)

// Filter chips / capsules — use enough padding
Text(label)
    .padding(.horizontal, 10)
    .padding(.vertical, 8)  // Ensures ≥44pt height with text
```

### Dynamic Type with @ScaledMetric

Fixed-width columns (time, frequency, RST) must scale with Dynamic Type. Use `@ScaledMetric` instead of hardcoded `CGFloat`:

```swift
// REQUIRED for fixed-width columns
@ScaledMetric(relativeTo: .caption) private var timeColumnWidth: CGFloat = 44
@ScaledMetric(relativeTo: .subheadline) private var frequencyColumnWidth: CGFloat = 80

// Use in layout
Text(formattedTime)
    .frame(width: timeColumnWidth, alignment: .trailing)
```

General Dynamic Type rules:
- Use system fonts that scale automatically
- Avoid fixed heights that would clip text at large sizes
- Test with largest accessibility text sizes

### Semantic Colors Only — No Hardcoded White/Black

Never use `.white` or `.black` directly. These break in dark mode / high contrast.

```swift
// BANNED
.foregroundStyle(.white)
.foregroundStyle(.black)

// REQUIRED — use semantic equivalents
.foregroundStyle(Color(.systemBackground))  // adapts to light/dark
.foregroundStyle(Color(.label))             // adapts to light/dark
```

### Reduce Motion Support

```swift
@Environment(\.accessibilityReduceMotion) private var reduceMotion

.animation(reduceMotion ? .none : .easeInOut, value: currentPage)
```

### Static DateFormatters

DateFormatter allocation is expensive. Never create formatters as computed properties or inside view bodies. Use `private static let`:

```swift
// REQUIRED
private static let timeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm"
    formatter.timeZone = TimeZone(identifier: "UTC")
    return formatter
}()

// BANNED — creates a new formatter every render
private var timeFormatter: DateFormatter {
    let formatter = DateFormatter()
    ...
}
```

### Haptic Feedback on Primary Actions

Primary actions (logging a QSO, confirming a change) should provide haptic feedback:

```swift
// Success confirmation (log QSO, save profile)
UINotificationFeedbackGenerator().notificationOccurred(.success)

// Impact for quick actions (quick log button)
UIImpactFeedbackGenerator(style: .medium).impactOccurred()
```

### Sheets Must Have Navigation Structure

All `.sheet` presentations must wrap content in `NavigationStack` with a title and dismiss button:

```swift
.sheet(isPresented: $showing) {
    NavigationStack {
        MySheetContent()
            .navigationTitle("Sheet Title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { showing = false }
                }
            }
    }
}

---

## Platform Adaptations

### iPhone vs iPad

**Navigation:**
- iPhone: `TabView` with visible tabs
- iPad: `NavigationSplitView` with sidebar

**Grid columns:**
```swift
if horizontalSizeClass == .regular {
    // iPad: 6 columns
    Array(repeating: GridItem(.flexible()), count: 6)
} else {
    // iPhone: 3 columns
    Array(repeating: GridItem(.flexible()), count: 3)
}
```

**Landscape iPhone:**
```swift
if verticalSizeClass == .compact {
    // Combined layout
    combinedStreaksAndStatsCard
} else {
    // Separate cards
    streaksCard
    summaryCard
}
```

### Dark Mode

Use semantic colors (`Color(.systemGray5)`, `.primary`, `.secondary`) that automatically adapt. Never hardcode light/dark specific colors.

### Safe Areas

```swift
.safeAreaInset(edge: .bottom) {
    // Keyboard accessory content
}
```

---

## Implementation Checklist

When creating new views, verify:

**Visual:**
- [ ] Uses `Color(.systemGray6)` for cards, not custom grays
- [ ] Callsigns use `.monospaced()` font
- [ ] Frequencies use appropriate formatter
- [ ] Badges use `Capsule()` or `RoundedRectangle(cornerRadius: 3)`
- [ ] Cards use `RoundedRectangle(cornerRadius: 12)`
- [ ] Spacing follows 4/8/12/16 scale
- [ ] Loading states show "--" with 0.6 opacity
- [ ] Icons from SF Symbols only
- [ ] No hardcoded `.white` or `.black` — use `Color(.systemBackground)` / `Color(.label)`
- [ ] Adapts to iPad/landscape where appropriate

**Accessibility (MANDATORY):**
- [ ] All icon-only buttons have `.accessibilityLabel`
- [ ] Decorative images use `.accessibilityHidden(true)`
- [ ] Color-only status indicators have text alternatives
- [ ] All interactive elements meet 44×44pt minimum touch target
- [ ] Fixed-width columns use `@ScaledMetric` (not hardcoded `CGFloat`)
- [ ] DateFormatters are `private static let` (not computed properties)

**Interaction:**
- [ ] Destructive actions have confirmation
- [ ] Primary actions (log QSO, save) provide haptic feedback
- [ ] Animations respect reduce motion
- [ ] Sheets wrapped in `NavigationStack` with title and dismiss button
