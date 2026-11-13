#!/bin/bash
# Install SwiftLint and SwiftFormat Linux binaries if not present
TOOLS_DIR="$HOME/.local/bin"
mkdir -p "$TOOLS_DIR"

if [ ! -f "$TOOLS_DIR/swiftlint" ]; then
    curl -sL https://github.com/realm/SwiftLint/releases/download/0.63.2/swiftlint_linux_amd64.zip \
        -o /tmp/swiftlint.zip
    unzip -o /tmp/swiftlint.zip -d /tmp/swiftlint_bin
    cp /tmp/swiftlint_bin/swiftlint-static "$TOOLS_DIR/swiftlint"
    chmod +x "$TOOLS_DIR/swiftlint"
    rm -rf /tmp/swiftlint.zip /tmp/swiftlint_bin
fi

if [ ! -f "$TOOLS_DIR/swiftformat" ]; then
    curl -sL https://github.com/nicklockwood/SwiftFormat/releases/download/0.60.1/swiftformat_linux.zip \
        -o /tmp/swiftformat.zip
    unzip -o /tmp/swiftformat.zip -d /tmp/swiftformat_bin
    cp /tmp/swiftformat_bin/swiftformat_linux "$TOOLS_DIR/swiftformat"
    chmod +x "$TOOLS_DIR/swiftformat"
    rm -rf /tmp/swiftformat.zip /tmp/swiftformat_bin
fi

echo "SwiftLint and SwiftFormat are installed at $TOOLS_DIR."
echo "Run swiftformat on Swift files after editing. Run swiftlint to check for violations."
