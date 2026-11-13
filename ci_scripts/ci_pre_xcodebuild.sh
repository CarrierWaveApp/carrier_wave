#!/bin/bash
# Xcode Cloud pre-xcodebuild shim — delegates to swift/ios/ci_scripts/ci_pre_xcodebuild.sh

set -euo pipefail

REPO_ROOT="${CI_PRIMARY_REPOSITORY_PATH:-$(cd "$(dirname "$0")/.." && pwd)}"

exec "$REPO_ROOT/swift/ios/ci_scripts/ci_pre_xcodebuild.sh"
