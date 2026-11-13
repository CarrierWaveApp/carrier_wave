#!/bin/bash
INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# Only process Swift files
[[ "$FILE_PATH" =~ \.swift$ ]] || exit 0

LINUX_DIR="$HOME/.local/bin"

# Resolve tool paths: PATH first, then linux download location
resolve_tool() {
    local name="$1"
    local path
    path=$(command -v "$name" 2>/dev/null)
    if [ -n "$path" ] && [ -x "$path" ]; then
        echo "$path"
    elif [ -x "$LINUX_DIR/$name" ]; then
        echo "$LINUX_DIR/$name"
    fi
}

SWIFTFORMAT=$(resolve_tool swiftformat)
SWIFTLINT=$(resolve_tool swiftlint)

# Auto-format in place (fix, don't just lint)
if [ -n "$SWIFTFORMAT" ]; then
    "$SWIFTFORMAT" "$FILE_PATH" 2>/dev/null
fi

# Lint and report violations to stderr (Claude sees this as feedback)
if [ -n "$SWIFTLINT" ]; then
    # SwiftLint emits "Skipping enabled rule X because it requires SourceKit"
    # warnings to stderr when SourceKit is unavailable (e.g. sandboxed Claude
    # Code on Linux). Those are environment noise, not violations. Real
    # violations go to stdout and swiftlint exits non-zero in --strict mode,
    # so we rely on the exit code as the authoritative signal.
    #
    # Capture stderr to a tempfile rather than piping through grep: piping
    # into a subshell via $(...) hides the inner pipeline's PIPESTATUS, so
    # grep's exit code (1 when all lines are filtered out) would leak
    # through and be mistaken for a lint failure.
    LINT_STDERR_FILE=$(mktemp)
    LINT_STDOUT=$("$SWIFTLINT" lint --strict --quiet "$FILE_PATH" 2>"$LINT_STDERR_FILE")
    LINT_EXIT=$?
    LINT_STDERR=$(grep -v 'Skipping enabled rule .* because it requires SourceKit' \
        "$LINT_STDERR_FILE" 2>/dev/null || true)
    rm -f "$LINT_STDERR_FILE"
    if [ "$LINT_EXIT" -ne 0 ]; then
        echo "SwiftLint violations in $FILE_PATH:" >&2
        [ -n "$LINT_STDOUT" ] && echo "$LINT_STDOUT" >&2
        [ -n "$LINT_STDERR" ] && echo "$LINT_STDERR" >&2
        # Exit 2 blocks the action and sends feedback to Claude to fix
        exit 2
    fi
fi

exit 0
