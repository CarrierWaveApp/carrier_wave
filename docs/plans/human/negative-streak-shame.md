# Negative Streak / Activation Shame Mode

A "Carrot Weather"-style feature that playfully shames the user for not completing activations.

## Concept

The reverse of streak awards/icons. For every day without an activation, the app progressively roasts the user with increasingly harsh (but funny) messages. The streak counter goes negative to show days since last activation.

## Visual Progression

Icons decay over time without activations:

| Days Since Activation | Icon | Severity |
|-----------------------|------|----------|
| 1-3 days | Coffin | Mild shade |
| 4-7 days | Skeleton | Medium roast |
| 8-14 days | Decayed skeleton | Heavy roast |
| 15-30 days | Dust/bones | Brutal |
| 30+ days | Ghost/void | Maximum shame |

## Example Messages

**Mild (1-3 days):**
- "Your radio misses you."
- "The bands are calling. You're not answering."

**Medium (4-7 days):**
- "Remember when you used to be an activator?"
- "Your callsign is becoming a distant memory on the air."

**Heavy (8-14 days):**
- "At this point your radio is just an expensive paperweight."
- "POTA probably forgot you exist."

**Brutal (15-30 days):**
- "Your antenna is crying."
- "Did you sell your rig? Be honest."

**Maximum (30+ days):**
- "We've started forwarding your callsign to someone who actually uses it."
- "The FCC is considering reassigning your license to someone with a pulse."

## UI Placement

- Could appear on the Statistics tab or Dashboard
- Show alongside existing streak displays as a "negative streak" counter
- Maybe a toggle in settings to enable/disable (some users won't appreciate the humor)

## Personality Levels (like Carrot Weather)

Could have configurable sass levels:
- **Friendly**: Gentle reminders, encouraging
- **Snarky**: Light teasing
- **Brutal**: Full roast mode
- **Unhinged**: No filter, maximum chaos

## Notes

- This is a fun/novelty feature, not critical
- Should be opt-in or easily dismissable
- Messages should be genuinely funny, not mean-spirited
- Could tie into the social features - "shame" friends who haven't activated?
