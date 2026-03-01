#!/bin/bash
# App Store Screenshot Capture Script
# Captures main app screens across required device sizes

set -e

SCRIPTS_DIR="/Library/Application Support/ClaudeCode/.claude/skills/ios-simulator-skill/scripts"
SIM_APP="$HOME/Library/Developer/Xcode/DerivedData/CarrierWave-clzphkluqykxrydgfkwcfwxwdykw/Build/Products/Debug-iphonesimulator/CarrierWave.app"
BUNDLE_ID="com.jsvana.FullDuplex"
OUTPUT_DIR="/Users/jsvana/projects/carrier_wave/screenshots"

# Device configurations: name|udid|folder_name
DEVICES=(
    "iPhone 17 Pro Max|4536C96C-EB26-4B78-AA68-82A155E304AF|iphone_6.9"
    "iPhone 16 Plus|414802F3-A7AE-476C-BF10-309FD6AACDC3|iphone_6.7"
    "iPad Pro 13-inch (M5)|048C7D67-8FB5-436F-A205-63AA1E0B7340|ipad_13"
)

# Tab bar labels to tap for each screenshot
TABS=("Dashboard" "Sessions" "Logs" "Map" "More")

for device_config in "${DEVICES[@]}"; do
    IFS='|' read -r DEVICE_NAME UDID FOLDER <<< "$device_config"
    echo ""
    echo "=========================================="
    echo "📱 $DEVICE_NAME ($FOLDER)"
    echo "=========================================="

    # Create output directory
    mkdir -p "$OUTPUT_DIR/$FOLDER"

    # Boot simulator
    echo "Booting $DEVICE_NAME..."
    xcrun simctl boot "$UDID" 2>/dev/null || true

    # Wait for boot
    echo "Waiting for device to be ready..."
    sleep 5
    xcrun simctl bootstatus "$UDID" -b 2>/dev/null || true
    sleep 3

    # Set clean status bar
    echo "Setting clean status bar..."
    xcrun simctl status_bar "$UDID" override \
        --time "9:41" \
        --batteryState charged \
        --batteryLevel 100 \
        --wifiBars 3 \
        --cellularBars 4 \
        --dataNetwork "5g" 2>/dev/null || true

    # Install and launch app
    echo "Installing app..."
    xcrun simctl install "$UDID" "$SIM_APP"

    echo "Launching app..."
    xcrun simctl launch "$UDID" "$BUNDLE_ID"
    sleep 5  # Wait for app to load

    # Capture each tab
    TAB_NUM=1
    for TAB in "${TABS[@]}"; do
        echo "  Capturing: $TAB..."

        # Tap the tab
        python3 "$SCRIPTS_DIR/navigator.py" --udid "$UDID" --find-text "$TAB" --tap 2>/dev/null || true
        sleep 2  # Wait for content to load

        # Capture screenshot
        FILENAME=$(printf "%02d_%s" $TAB_NUM "$(echo "$TAB" | tr '[:upper:]' '[:lower:]' | tr ' ' '_')")
        xcrun simctl io "$UDID" screenshot "$OUTPUT_DIR/$FOLDER/${FILENAME}.png"
        echo "    Saved: $FOLDER/${FILENAME}.png"

        TAB_NUM=$((TAB_NUM + 1))
    done

    # Shut down simulator
    echo "Shutting down $DEVICE_NAME..."
    xcrun simctl shutdown "$UDID" 2>/dev/null || true
    sleep 2
done

echo ""
echo "=========================================="
echo "Screenshot capture complete!"
echo "Output: $OUTPUT_DIR"
echo "=========================================="
ls -la "$OUTPUT_DIR"/*/
