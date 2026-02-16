# Investigation Traces

**When debugging or investigating any non-trivial issue, create a markdown artifact to document the investigation.**

**Location:** `docs/investigations/YYYY-MM-DD-<short-description>.md`

**When to create:**
- Debugging a bug that requires exploring multiple files or hypotheses
- Investigating user-reported issues
- Diagnosing build failures, crashes, or unexpected behavior
- Any investigation taking more than a few minutes

## Template

```markdown
# Investigation: <Short Description>

**Date:** YYYY-MM-DD
**Status:** In Progress | Resolved | Blocked | Abandoned
**Outcome:** <One-line summary of resolution, if resolved>

## Problem Statement

<What triggered this investigation? User report, error message, etc.>

## Hypotheses

### Hypothesis 1: <Brief description>
- **Evidence for:** <What supports this theory>
- **Evidence against:** <What contradicts it>
- **Tested:** Yes/No
- **Result:** <What we learned>

### Hypothesis 2: <Brief description>
...

## Investigation Log

### <Timestamp or step number>
<What was checked, what was found, what was tried>

### <Next step>
...

## Files Examined

| File | Relevance | Finding |
|------|-----------|---------|
| `path/to/file.swift` | <Why looked here> | <What was found> |

## Root Cause

<If found: detailed explanation of the root cause>

## Resolution

<If resolved: what fix was applied, or why issue was closed without fix>

## Lessons Learned

<Optional: patterns to watch for, documentation to update, etc.>
```

## Guidelines

- Create the file at the START of the investigation, not the end
- Update incrementally as you discover new information
- Document dead ends too — they prevent re-investigating the same paths
- Mark the status as **Resolved** and add **Outcome** when done
- Link to related bugs/plans if applicable
