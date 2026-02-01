#!/usr/bin/env bash
# Release script: creates git tag and notifies Discord
#
# Usage: ./scripts/release.sh <version>
# Example: ./scripts/release.sh 1.15.0
#
# Requires:
#   - DISCORD_WEBHOOK_URL environment variable (or in .env file)
#   - Version must match format: X.Y.Z

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Load .env file if it exists
if [[ -f .env ]]; then
    # shellcheck disable=SC1091
    source .env
fi

# Validate arguments
if [[ $# -ne 1 ]]; then
    echo -e "${RED}Error: Version argument required${NC}"
    echo "Usage: $0 <version>"
    echo "Example: $0 1.15.0"
    exit 1
fi

VERSION="$1"

# Validate version format (X.Y.Z)
if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo -e "${RED}Error: Invalid version format '$VERSION'${NC}"
    echo "Version must be in format X.Y.Z (e.g., 1.15.0)"
    exit 1
fi

TAG_NAME="v$VERSION"

# Check if tag already exists
if git rev-parse "$TAG_NAME" >/dev/null 2>&1; then
    echo -e "${RED}Error: Tag $TAG_NAME already exists${NC}"
    exit 1
fi

# Check for uncommitted changes
if ! git diff-index --quiet HEAD --; then
    echo -e "${RED}Error: You have uncommitted changes${NC}"
    echo "Please commit or stash your changes before releasing."
    exit 1
fi

# Extract changelog for this version
echo -e "${YELLOW}Extracting changelog for version $VERSION...${NC}"
CHANGELOG_CONTENT=$(awk "/^## \[$VERSION\]/{found=1; next} /^## \[/{found=0} found" CHANGELOG.md | sed '/^$/d')

if [[ -z "$CHANGELOG_CONTENT" ]]; then
    echo -e "${RED}Error: No changelog entry found for version $VERSION${NC}"
    echo "Please update CHANGELOG.md with the release notes first."
    exit 1
fi

# Create annotated git tag
echo -e "${YELLOW}Creating git tag $TAG_NAME...${NC}"
git tag -a "$TAG_NAME" -m "Release $VERSION

$CHANGELOG_CONTENT"

echo -e "${GREEN}Created tag $TAG_NAME${NC}"

# Push tag to remote
echo -e "${YELLOW}Pushing tag to origin...${NC}"
git push origin "$TAG_NAME"
echo -e "${GREEN}Pushed tag $TAG_NAME to origin${NC}"

# Send Discord notification
if [[ -n "${DISCORD_WEBHOOK_URL:-}" ]]; then
    echo -e "${YELLOW}Sending Discord notification...${NC}"

    # Truncate changelog if it exceeds Discord's 1024 character field limit
    MAX_LENGTH=1000  # Leave room for truncation message
    if [[ ${#CHANGELOG_CONTENT} -gt $MAX_LENGTH ]]; then
        CHANGELOG_CONTENT="${CHANGELOG_CONTENT:0:$MAX_LENGTH}..."
        echo -e "${YELLOW}Changelog truncated to fit Discord field limit${NC}"
    fi

    # Build Discord webhook payload using jq for proper JSON escaping
    PAYLOAD=$(jq -n \
        --arg title "Carrier Wave $TAG_NAME Released" \
        --arg changelog "$CHANGELOG_CONTENT" \
        '{
            embeds: [{
                title: $title,
                color: 5814783,
                fields: [{
                    name: "What'\''s New",
                    value: $changelog
                }],
                footer: {
                    text: "Carrier Wave - Amateur Radio QSO Logger"
                }
            }]
        }'
    )

    # Send to Discord
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
        -H "Content-Type: application/json" \
        -d "$PAYLOAD" \
        "$DISCORD_WEBHOOK_URL")

    if [[ "$HTTP_CODE" -ge 200 && "$HTTP_CODE" -lt 300 ]]; then
        echo -e "${GREEN}Discord notification sent successfully${NC}"
    else
        echo -e "${RED}Warning: Discord notification failed (HTTP $HTTP_CODE)${NC}"
        echo "You may need to check your DISCORD_WEBHOOK_URL"
    fi
else
    echo -e "${YELLOW}Skipping Discord notification (DISCORD_WEBHOOK_URL not set)${NC}"
    echo "To enable, set DISCORD_WEBHOOK_URL in your environment or .env file"
fi

echo ""
echo -e "${GREEN}Release $VERSION complete!${NC}"
