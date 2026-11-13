#!/usr/bin/env bash
# PreToolUse(Bash) guard: deny any command that invokes `cd`.
#
# Rationale: the Bash tool's working directory persists between calls and is
# already the repo root, so `cd` is never needed. Worse, chaining `cd ...; cmd`
# makes the command "compound", which trips a permission-approval prompt.
# Blocking `cd` outright forces absolute/relative paths instead.
#
# Detection: `cd` appearing at the start of the command or right after a shell
# separator (; & | && || ` (), allowing leading whitespace). This avoids false
# positives like `lcd`, `mkdir cd_test`, or `cd` inside a quoted string.

cmd="$(jq -r '.tool_input.command // empty')"

if printf '%s' "$cmd" | grep -qE '(^|[;&|`(]|&&|\|\|)[[:space:]]*cd[[:space:]]'; then
  cat <<'JSON'
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"This command uses `cd`. The Bash working directory persists between calls and is already the project root — drop the `cd` and run the command directly with absolute/relative paths. Chaining `cd ...; cmd` also trips an approval prompt."}}
JSON
fi
