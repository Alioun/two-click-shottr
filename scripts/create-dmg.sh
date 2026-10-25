#!/bin/bash
set -euo pipefail
if [[ $# != 2 || ! -d "$1/Contents" ]]; then
    printf 'Usage: %s APP_BUNDLE OUTPUT_DMG\n' "$0" >&2
    exit 1
fi
app="$1"
output="$2"
codesign --verify --strict --all-architectures "$app"
mkdir -p "$(dirname "$output")"
stage=$(mktemp -d "$(dirname "$output")/.dmg.XXXXXX")
trap 'rm -rf "$stage"' EXIT
mkdir "$stage/payload"
ditto "$app" "$stage/payload/Two Click Shottr.app"
ln -s /Applications "$stage/payload/Applications"
hdiutil create -volname 'Two Click Shottr' -srcfolder "$stage/payload" -format UDZO -fs HFS+ "$stage/app.dmg"
hdiutil verify "$stage/app.dmg"
mv "$stage/app.dmg" "$output"
shasum -a 256 "$output" | awk -v name="$(basename "$output")" '{ print $1 "  " name }' > "$output.sha256"
printf 'Packaged %s\n' "$output"
