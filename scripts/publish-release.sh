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
disk_image="TwoClickShottr-$version-universal-experimental.dmg"
(cd dist && shasum -a 256 -c "$archive.sha256" && shasum -a 256 -c "$disk_image.sha256")
notes=$(mktemp)
trap 'rm -f "$notes"' EXIT
cat > "$notes" <<'NOTES'
Experimental universal app for Apple Silicon and Intel Macs, requiring macOS 13 or later and Shottr installed.

Download the DMG, open it, and drag Two Click Shottr.app to Applications. You can also download and extract the ZIP. Release Shift-Command-4 in Shottr and macOS screenshot shortcuts before using it here. Grant Screen Recording access when requested.

Open Settings from the menu to change crosshair size and line thickness, coordinate text size and position, or menu-bar visibility. If you hide the icon, reopen the app from Finder or Spotlight to reach Settings. The capture shortcut keeps working.

This build is ad-hoc signed and is not Apple-notarized. macOS may block it with Gatekeeper. Use Apple's documented security override only if you trust this download, or build from source with your own stable signing identity. Updates may require granting Screen Recording access again. No automatic updater is included.

Each download has a SHA-256 file to verify its integrity. It does not replace Developer ID signing or notarization. Shottr is not included.
NOTES
gh release create "$tag" "dist/$archive" "dist/$archive.sha256" "dist/$disk_image" "dist/$disk_image.sha256" \
    --target "$GITHUB_SHA" --title "Two Click Shottr $version (experimental)" \
    --notes-file "$notes"
