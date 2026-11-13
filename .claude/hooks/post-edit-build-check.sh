#!/bin/bash
# Post-edit build check: runs appropriate build for edited Swift files
# CWSweep files → cw-sweep build, everything else → xc build
INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# Only process Swift files
[[ "$FILE_PATH" =~ \.swift$ ]] || exit 0

cd "$(git rev-parse --show-toplevel)" || exit 0

if [[ "$FILE_PATH" == *CWSweep/* ]]; then
    ~/.claude/skills/cw-sweep-build/scripts/cw-sweep build 2>&1 | tail -5
else
    ~/.claude/skills/xcode-build/scripts/xc build 2>&1 | tail -20
fi
