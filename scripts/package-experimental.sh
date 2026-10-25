#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo 'Release versions must use major.minor.patch.' >&2
    exit 1
fi
./scripts/swift.sh build -c release --arch arm64 --arch x86_64
binary_dir=$(./scripts/swift.sh build -c release --arch arm64 --arch x86_64 --show-bin-path)
mkdir -p dist
stage=$(mktemp -d "$PWD/dist/.experimental.XXXXXX")
trap 'rm -rf "$stage"' EXIT
app="$stage/Two Click Shottr.app"
mkdir -p "$app/Contents/MacOS"
cp "$binary_dir/TwoClickShottr" "$app/Contents/MacOS/TwoClickShottr"
cp Resources/Info.plist "$app/Contents/Info.plist"
architectures=$(lipo -archs "$app/Contents/MacOS/TwoClickShottr")
if [[ "$architectures" != 'arm64 x86_64' && "$architectures" != 'x86_64 arm64' ]]; then
    printf 'Expected arm64 and x86_64; found %s\n' "$architectures" >&2
    exit 1
fi
otool -l "$app/Contents/MacOS/TwoClickShottr" | awk '
    $1 == "minos" { count++; if ($2 != "13.0") failed = 1 }
    END { exit (count != 2 || failed) }
'
plutil -lint "$app/Contents/Info.plist"
codesign --force --sign - --timestamp=none "$app"
codesign --verify --strict --all-architectures "$app"
archive="TwoClickShottr-$version-universal-experimental.zip"
ditto -c -k --sequesterRsrc --keepParent "$app" "$stage/$archive"
mv "$stage/$archive" "dist/$archive"
(cd dist && shasum -a 256 "$archive" > "$archive.sha256")
./scripts/create-dmg.sh "$app" "dist/TwoClickShottr-$version-universal-experimental.dmg"
printf 'Packaged dist/%s\n' "$archive"
