#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo 'Release versions must use major.minor.patch.' >&2
    exit 1
fi
tag="v$version"
releases=$(gh api --paginate "repos/$GITHUB_REPOSITORY/releases" --jq '.[].tag_name')
if printf '%s\n' "$releases" | /usr/bin/grep -F -x -q "$tag"; then
    printf '%s already released; keeping its assets unchanged.\n' "$tag"
    exit 0
fi
archive="TwoClickShottr-$version-universal-experimental.zip"
(cd dist && shasum -a 256 -c "$archive.sha256")
notes=$(mktemp)
trap 'rm -f "$notes"' EXIT
cat > "$notes" <<'NOTES'
Experimental universal app for Apple Silicon and Intel Macs, requiring macOS 13 or later and Shottr installed.

Download the universal-experimental ZIP, extract it, and move Two Click Shottr.app to Applications. Release Shift-Command-4 in Shottr and macOS screenshot shortcuts before using it here. Grant Screen Recording access when requested.

This build is ad-hoc signed and is not Apple-notarized. macOS may block it with Gatekeeper. Use Apple's documented security override only if you trust this download, or build from source with your own stable signing identity. Updates may require granting Screen Recording access again. No automatic updater is included.

The SHA-256 file verifies download integrity. It does not replace Developer ID signing or notarization. Shottr is not included.
NOTES
gh release create "$tag" "dist/$archive" "dist/$archive.sha256" \
    --target "$GITHUB_SHA" --title "Two Click Shottr $version (experimental)" \
    --notes-file "$notes"
