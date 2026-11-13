#!/usr/bin/env bash
#
# Sign a notarized CW Sweep DMG, append a new entry to the Sparkle appcast,
# and upload both to carrierwave.app/sweep/.
#
# Run AFTER the cw-sweep-release workflow has produced a notarized + stapled
# DMG (typically ~/Desktop/CWSweep-<version>.dmg). This script:
#
#   1. Verifies Sparkle CLI tools are cached locally (downloads release tarball
#      from GitHub on first run).
#   2. Reads the Ed25519 signature for the DMG using the private key already
#      stored in the macOS login keychain by `generate_keys`.
#   3. Prepends a new <item> to website/sweep/appcast.xml with version, DMG
#      length, edSignature, minimum system version, and (optional) release
#      notes pulled from the latest [<version>] section of CHANGELOG.md.
#   4. scp's the versioned DMG, the "latest" alias, and the updated appcast.xml
#      to the production server.
#
# Re-run safely: prepending the same version twice is detected and aborts.
#
# Usage:
#   ./sign-and-publish.sh --version 0.11.0 --dmg ~/Desktop/CWSweep-0.11.0.dmg
#
# Required:
#   --version X.Y.Z         marketing version, must match the bundle
#   --dmg <path>            path to the notarized + stapled DMG
#
# Optional:
#   --notes-html <path>     HTML file with release-notes body (no <html>/<body>)
#   --min-system <ver>      minimum macOS version (default: 14.0)
#   --skip-upload           sign + update appcast locally only; no scp
#   --dry-run               print actions without executing them
#
# Environment overrides:
#   SWEEP_SSH_HOST          default: activities.carrierwave.app
#   SWEEP_SSH_USER          default: root
#   SWEEP_SSH_KEY           default: ~/.ssh/id_hetzner_github
#   SWEEP_REMOTE_DIR        default: /var/www/carrierwave.app/sweep
#   SPARKLE_VERSION         default: 2.9.1

set -euo pipefail

# ---- Defaults --------------------------------------------------------------
SPARKLE_VERSION="${SPARKLE_VERSION:-2.9.1}"
SPARKLE_TOOLS_DIR="${HOME}/.cache/sparkle-tools/${SPARKLE_VERSION}"
SWEEP_SSH_HOST="${SWEEP_SSH_HOST:-activities.carrierwave.app}"
SWEEP_SSH_USER="${SWEEP_SSH_USER:-root}"
SWEEP_SSH_KEY="${SWEEP_SSH_KEY:-${HOME}/.ssh/id_hetzner_github}"
SWEEP_REMOTE_DIR="${SWEEP_REMOTE_DIR:-/var/www/carrierwave.app/sweep}"
APPCAST_BASE_URL="https://carrierwave.app/sweep"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APPCAST_PATH="${REPO_ROOT}/website/sweep/appcast.xml"
CHANGELOG_PATH="${REPO_ROOT}/CHANGELOG.md"

# ---- Args ------------------------------------------------------------------
VERSION=""
DMG_PATH=""
NOTES_HTML=""
MIN_SYSTEM="14.0"
SKIP_UPLOAD=0
DRY_RUN=0

usage() {
    sed -n '2,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version) VERSION="$2"; shift 2 ;;
        --dmg) DMG_PATH="$2"; shift 2 ;;
        --notes-html) NOTES_HTML="$2"; shift 2 ;;
        --min-system) MIN_SYSTEM="$2"; shift 2 ;;
        --skip-upload) SKIP_UPLOAD=1; shift ;;
        --dry-run) DRY_RUN=1; shift ;;
        -h|--help) usage 0 ;;
        *) echo "Unknown argument: $1" >&2; usage 1 ;;
    esac
done

[[ -z "$VERSION" ]] && { echo "ERROR: --version required" >&2; usage 1; }
[[ -z "$DMG_PATH" ]] && { echo "ERROR: --dmg required" >&2; usage 1; }
[[ ! -f "$DMG_PATH" ]] && { echo "ERROR: DMG not found: $DMG_PATH" >&2; exit 1; }
[[ ! -f "$APPCAST_PATH" ]] && { echo "ERROR: appcast missing: $APPCAST_PATH" >&2; exit 1; }

# Marketing version must match a sane semver-ish pattern
if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "ERROR: --version must be X.Y.Z (got: $VERSION)" >&2
    exit 1
fi

# ---- Sparkle tools cache ---------------------------------------------------
ensure_sparkle_tools() {
    if [[ -x "${SPARKLE_TOOLS_DIR}/sign_update" && -x "${SPARKLE_TOOLS_DIR}/generate_keys" ]]; then
        return 0
    fi
    echo "==> Caching Sparkle ${SPARKLE_VERSION} CLI tools to ${SPARKLE_TOOLS_DIR}"
    mkdir -p "${SPARKLE_TOOLS_DIR}"
    local tarball="/tmp/Sparkle-${SPARKLE_VERSION}.tar.xz"
    local extract_dir="/tmp/sparkle-extract-${SPARKLE_VERSION}"
    rm -rf "${extract_dir}"
    mkdir -p "${extract_dir}"
    curl -fL -o "${tarball}" \
        "https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-${SPARKLE_VERSION}.tar.xz"
    tar -xJf "${tarball}" -C "${extract_dir}"
    cp "${extract_dir}/bin/sign_update" "${SPARKLE_TOOLS_DIR}/"
    cp "${extract_dir}/bin/generate_keys" "${SPARKLE_TOOLS_DIR}/"
    cp "${extract_dir}/bin/generate_appcast" "${SPARKLE_TOOLS_DIR}/" 2>/dev/null || true
    rm -rf "${extract_dir}" "${tarball}"
}

# ---- Stamp signature -------------------------------------------------------
sign_dmg() {
    # sign_update prints e.g.:
    #   sparkle:edSignature="..." length="12345"
    "${SPARKLE_TOOLS_DIR}/sign_update" "${DMG_PATH}"
}

# ---- Optional: extract release notes from CHANGELOG.md ---------------------
# Matches headers of the form `## [<X.Y.Z>] - DATE` and `## [CW Sweep <X.Y.Z>] - DATE`.
read_notes_from_changelog() {
    [[ ! -f "${CHANGELOG_PATH}" ]] && return 0
    awk -v v="${VERSION}" '
        BEGIN { inblock=0; pat="\\[(CW Sweep )?" v "\\]" }
        /^## / {
            if (inblock) { exit }
            if (match($0, pat)) { inblock=1; next }
        }
        inblock { print }
    ' "${CHANGELOG_PATH}"
}

# Quick-and-dirty Markdown -> HTML for the kind of notes we ship in the
# changelog: ### headers and "- " bullet lists. Anything richer should be
# handed in via --notes-html.
markdown_to_html() {
    python3 - <<'PY'
import sys, re, html
md = sys.stdin.read().strip()
out = []
in_list = False
for raw in md.splitlines():
    line = raw.rstrip()
    m = re.match(r'^### (.+)$', line)
    if m:
        if in_list:
            out.append('</ul>')
            in_list = False
        out.append(f'<h3>{html.escape(m.group(1))}</h3>')
        continue
    m = re.match(r'^- (.+)$', line)
    if m:
        if not in_list:
            out.append('<ul>')
            in_list = True
        out.append(f'<li>{html.escape(m.group(1))}</li>')
        continue
    if not line:
        if in_list:
            out.append('</ul>')
            in_list = False
        continue
    if in_list:
        out.append('</ul>')
        in_list = False
    out.append(f'<p>{html.escape(line)}</p>')
if in_list:
    out.append('</ul>')
print('\n'.join(out))
PY
}

# ---- Main ------------------------------------------------------------------
ensure_sparkle_tools

# Reject double-publish.
if grep -q "<sparkle:version>${VERSION}</sparkle:version>" "${APPCAST_PATH}" \
   || grep -q "sparkle:shortVersionString=\"${VERSION}\"" "${APPCAST_PATH}"; then
    echo "ERROR: appcast already contains an entry for ${VERSION}" >&2
    echo "       Bump the version or remove the existing <item> first." >&2
    exit 1
fi

echo "==> Signing ${DMG_PATH}"
SIGN_LINE="$(sign_dmg)"
echo "    ${SIGN_LINE}"

# Parse "sparkle:edSignature=\"...\" length=\"...\"" — sign_update is stable.
ED_SIG="$(echo "${SIGN_LINE}" | sed -E 's/.*edSignature="([^"]+)".*/\1/')"
DMG_LEN="$(echo "${SIGN_LINE}" | sed -E 's/.*length="([^"]+)".*/\1/')"
[[ -z "${ED_SIG}" || -z "${DMG_LEN}" ]] && { echo "ERROR: failed to parse sign_update output" >&2; exit 1; }

# Get bundle build number from the DMG so Sparkle's version comparison works.
# We assume the DMG layout: /CW Sweep.app/Contents/Info.plist
echo "==> Mounting DMG to read CFBundleVersion"
TMP_MNT="$(mktemp -d)/sweep-mnt"
mkdir -p "${TMP_MNT}"
hdiutil attach "${DMG_PATH}" -mountpoint "${TMP_MNT}" -nobrowse -quiet
trap 'hdiutil detach "${TMP_MNT}" -quiet 2>/dev/null || true' EXIT
INFO_PLIST="${TMP_MNT}/CW Sweep.app/Contents/Info.plist"
[[ ! -f "${INFO_PLIST}" ]] && { echo "ERROR: Info.plist not found inside DMG" >&2; exit 1; }
BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "${INFO_PLIST}")"
DMG_SHORT_VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "${INFO_PLIST}")"
hdiutil detach "${TMP_MNT}" -quiet
trap - EXIT
[[ "${DMG_SHORT_VERSION}" != "${VERSION}" ]] && {
    echo "ERROR: DMG bundle version (${DMG_SHORT_VERSION}) != --version (${VERSION})" >&2
    exit 1
}
echo "    build ${BUILD_NUMBER}, length ${DMG_LEN}"

# ---- Compose <item> --------------------------------------------------------
PUB_DATE="$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")"
DMG_FILENAME="CWSweep-${VERSION}.dmg"
ENCLOSURE_URL="${APPCAST_BASE_URL}/${DMG_FILENAME}"

NOTES_BODY=""
if [[ -n "${NOTES_HTML}" ]]; then
    [[ ! -f "${NOTES_HTML}" ]] && { echo "ERROR: --notes-html not found: ${NOTES_HTML}" >&2; exit 1; }
    NOTES_BODY="$(cat "${NOTES_HTML}")"
else
    NOTES_MD="$(read_notes_from_changelog)"
    if [[ -n "${NOTES_MD}" ]]; then
        NOTES_BODY="$(echo "${NOTES_MD}" | markdown_to_html)"
    fi
fi

ITEM_TMP="$(mktemp)"
{
    printf '        <item>\n'
    printf '            <title>Version %s</title>\n' "${VERSION}"
    printf '            <pubDate>%s</pubDate>\n' "${PUB_DATE}"
    printf '            <sparkle:version>%s</sparkle:version>\n' "${BUILD_NUMBER}"
    printf '            <sparkle:shortVersionString>%s</sparkle:shortVersionString>\n' "${VERSION}"
    printf '            <sparkle:minimumSystemVersion>%s</sparkle:minimumSystemVersion>\n' "${MIN_SYSTEM}"
    if [[ -n "${NOTES_BODY}" ]]; then
        printf '            <description><![CDATA[\n'
        printf '%s\n' "${NOTES_BODY}"
        printf '            ]]></description>\n'
    fi
    printf '            <enclosure url="%s" sparkle:edSignature="%s" length="%s" type="application/octet-stream" />\n' \
        "${ENCLOSURE_URL}" "${ED_SIG}" "${DMG_LEN}"
    printf '        </item>\n'
} >"${ITEM_TMP}"

# ---- Splice into appcast.xml ----------------------------------------------
# Insert immediately before </channel>. If we ever inherit a <description>
# inside the channel, this splice still works — it targets the closing tag.
echo "==> Updating ${APPCAST_PATH}"
NEW_APPCAST="$(mktemp)"
python3 - "${APPCAST_PATH}" "${ITEM_TMP}" "${NEW_APPCAST}" <<'PY'
import sys
appcast_path, item_path, out_path = sys.argv[1], sys.argv[2], sys.argv[3]
with open(appcast_path, 'r', encoding='utf-8') as f:
    src = f.read()
with open(item_path, 'r', encoding='utf-8') as f:
    item = f.read()
needle = '</channel>'
idx = src.rfind(needle)
if idx < 0:
    sys.exit("appcast missing </channel>")
# Insert the new <item> before any pre-existing items (newest first).
# Find first existing <item> if any; otherwise insert before </channel>.
existing = src.find('<item>')
if existing >= 0 and existing < idx:
    out = src[:existing] + item + src[existing:]
else:
    out = src[:idx] + item + src[idx:]
with open(out_path, 'w', encoding='utf-8') as f:
    f.write(out)
PY
mv "${NEW_APPCAST}" "${APPCAST_PATH}"
rm -f "${ITEM_TMP}"

# ---- Upload ----------------------------------------------------------------
if [[ "${SKIP_UPLOAD}" -eq 1 ]]; then
    echo "==> --skip-upload set; not uploading. Local appcast updated."
    exit 0
fi

SSH_OPTS="-i ${SWEEP_SSH_KEY} -o StrictHostKeyChecking=accept-new"
SSH_TARGET="${SWEEP_SSH_USER}@${SWEEP_SSH_HOST}"

run() {
    if [[ "${DRY_RUN}" -eq 1 ]]; then
        echo "DRY-RUN: $*"
    else
        eval "$@"
    fi
}

echo "==> Uploading DMG to ${SSH_TARGET}:${SWEEP_REMOTE_DIR}/${DMG_FILENAME}"
run "scp ${SSH_OPTS} \"${DMG_PATH}\" \"${SSH_TARGET}:${SWEEP_REMOTE_DIR}/${DMG_FILENAME}\""

echo "==> Updating ${SWEEP_REMOTE_DIR}/CWSweep-latest.dmg alias"
run "ssh ${SSH_OPTS} ${SSH_TARGET} \"cp -f '${SWEEP_REMOTE_DIR}/${DMG_FILENAME}' '${SWEEP_REMOTE_DIR}/CWSweep-latest.dmg' && chown www-data:www-data '${SWEEP_REMOTE_DIR}/${DMG_FILENAME}' '${SWEEP_REMOTE_DIR}/CWSweep-latest.dmg' && chmod 0644 '${SWEEP_REMOTE_DIR}/${DMG_FILENAME}' '${SWEEP_REMOTE_DIR}/CWSweep-latest.dmg'\""

echo "==> Uploading appcast.xml"
run "scp ${SSH_OPTS} \"${APPCAST_PATH}\" \"${SSH_TARGET}:${SWEEP_REMOTE_DIR}/appcast.xml\""
run "ssh ${SSH_OPTS} ${SSH_TARGET} \"chown www-data:www-data '${SWEEP_REMOTE_DIR}/appcast.xml' && chmod 0644 '${SWEEP_REMOTE_DIR}/appcast.xml'\""

echo
echo "==> Done."
echo "    DMG:      ${APPCAST_BASE_URL}/${DMG_FILENAME}"
echo "    Latest:   ${APPCAST_BASE_URL}/CWSweep-latest.dmg"
echo "    Appcast:  ${APPCAST_BASE_URL}/appcast.xml"
echo
echo "Commit the appcast change:"
echo "    git add website/sweep/appcast.xml"
echo "    git commit -m 'Sparkle: publish CW Sweep ${VERSION}'"
echo "    git push origin main"
