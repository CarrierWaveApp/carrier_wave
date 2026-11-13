#!/bin/bash
INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# Only process Rust files
[[ "$FILE_PATH" =~ \.rs$ ]] || exit 0

# Find the Cargo.toml for this file (walk up from file)
DIR=$(dirname "$FILE_PATH")
CARGO_DIR=""
while [ "$DIR" != "/" ]; do
    if [ -f "$DIR/Cargo.toml" ]; then
        CARGO_DIR="$DIR"
        break
    fi
    DIR=$(dirname "$DIR")
done

[ -z "$CARGO_DIR" ] && exit 0

# Source ESP toolchain if this is the firmware crate
if [[ "$CARGO_DIR" == *"/firmware"* ]] && [ -f "$HOME/export-esp.sh" ]; then
    source "$HOME/export-esp.sh" 2>/dev/null
fi

cd "$CARGO_DIR" || exit 0

# Format
if command -v cargo >/dev/null 2>&1; then
    cargo fmt -- "$FILE_PATH" 2>/dev/null
fi

# Clippy (warnings only, don't block)
CLIPPY_OUT=$(cargo clippy --message-format=short 2>&1)
CLIPPY_EXIT=$?
if [ "$CLIPPY_EXIT" -ne 0 ]; then
    # Filter to only errors (not warnings)
    ERRORS=$(echo "$CLIPPY_OUT" | grep "^error" || true)
    if [ -n "$ERRORS" ]; then
        echo "Clippy errors in $CARGO_DIR:" >&2
        echo "$ERRORS" >&2
        exit 2
    fi
fi

exit 0
