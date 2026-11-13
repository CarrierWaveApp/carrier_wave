#!/bin/bash
# Xcode Cloud post-clone shim — delegates to swift/ios/ci_scripts/ci_post_clone.sh
# Lives at the repo root so Xcode Cloud finds it before resolving dependencies.

set -euo pipefail

REPO_ROOT="${CI_PRIMARY_REPOSITORY_PATH:-$(cd "$(dirname "$0")/.." && pwd)}"

# Symlink the project so Xcode Cloud can find it at the repo root.
ln -sfn swift/ios/CarrierWave.xcodeproj "$REPO_ROOT/CarrierWave.xcodeproj"

exec "$REPO_ROOT/swift/ios/ci_scripts/ci_post_clone.sh"
