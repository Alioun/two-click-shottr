#!/bin/bash
set -euo pipefail
if [[ $# != 2 || ! -d "$1/Contents" ]]; then
    printf 'Usage: %s APP_BUNDLE OUTPUT_DMG\n' "$0" >&2
    exit 1
fi
app="$1"
output="$2"
layout="$(cd "$(dirname "$0")" && pwd)/dmg-layout.swift"
codesign --verify --strict --all-architectures "$app"
mkdir -p "$(dirname "$output")"
stage=$(mktemp -d "$(dirname "$output")/.dmg.XXXXXX")
# The background alias records the writable image and mount paths. Keep the builder's paths out of it.
layout_stage=$(mktemp -d /tmp/two-click-shottr-dmg.XXXXXX)
volume="$layout_stage/volume"
mkdir "$volume"

is_mounted() {
    [[ $(stat -f %d "$volume") != $(stat -f %d "$volume/..") ]]
}
detach() {
    local attempt
    for ((attempt=0; attempt<5; attempt++)); do
        hdiutil detach "$volume" -quiet && return
        sleep 2
    done
    hdiutil detach "$volume" -force
}
cleanup() {
    if is_mounted && ! detach; then
        printf 'Left %s and %s because the disk image is still mounted.\n' "$stage" "$layout_stage" >&2
        return
    fi
    rm -rf "$stage" "$layout_stage"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

mkdir "$stage/payload"
ditto "$app" "$stage/payload/Two Click Shottr.app"
ln -s /Applications "$stage/payload/Applications"
hdiutil create -volname 'Two Click Shottr' -srcfolder "$stage/payload" -format UDRW -fs HFS+ "$layout_stage/layout.dmg"
hdiutil attach -readwrite -noverify -noautoopen -mountpoint "$volume" "$layout_stage/layout.dmg"
xcrun swift "$layout" apply "$volume"
for _ in {1..30}; do
    [[ -f "$volume/.DS_Store" ]] && break
    sleep 1
done
detach

hdiutil convert "$layout_stage/layout.dmg" -format UDZO -imagekey zlib-level=9 -o "$stage/app.dmg"
hdiutil verify "$stage/app.dmg"
hdiutil attach -readonly -nobrowse -noverify -noautoopen -mountpoint "$volume" "$stage/app.dmg"
diff -r "$app" "$volume/Two Click Shottr.app"
codesign --verify --strict --all-architectures "$volume/Two Click Shottr.app"
[[ $(readlink "$volume/Applications") == /Applications ]]
[[ -s "$volume/.DS_Store" ]]
xcrun swift "$layout" check "$volume"
detach

mv "$stage/app.dmg" "$output"
shasum -a 256 "$output" | awk -v name="$(basename "$output")" '{ print $1 "  " name }' > "$output.sha256"
printf 'Packaged %s\n' "$output"
