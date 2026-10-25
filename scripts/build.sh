#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
CODE_SIGN_IDENTITY=${CODE_SIGN_IDENTITY-'Two Click Shottr Local'}
signing_help='Run ./scripts/repair-permission.command to set up or repair the local signing certificate, then retry. CODE_SIGN_IDENTITY may specify an exact certificate label or full SHA-1 hash.'
if [[ -z "$CODE_SIGN_IDENTITY" || "$CODE_SIGN_IDENTITY" == '-' ]]; then
    printf 'A stable code signing identity is required; empty and ad-hoc identities are not allowed.\n%s\n' "$signing_help" >&2
    exit 1
fi
source "$PWD/scripts/signing-support.sh"
if ! signing_identity=$(security find-identity -p codesigning | resolve_signing_identity "$CODE_SIGN_IDENTITY"); then
    printf 'Could not resolve one unique code signing identity. No build was started.\n%s\n' "$signing_help" >&2
    exit 1
fi
./scripts/swift.sh build -c release
binary_dir=$(./scripts/swift.sh build -c release --show-bin-path)
mkdir -p "$PWD/dist"
build_stage=$(mktemp -d "$PWD/dist/.two-click-build.XXXXXX")
trap 'rm -rf "$build_stage"' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
app="$build_stage/Two Click Shottr.app"
mkdir -p "$app/Contents/MacOS"
cp "$binary_dir/TwoClickShottr" "$app/Contents/MacOS/TwoClickShottr"
cp "$PWD/Resources/Info.plist" "$app/Contents/Info.plist"
codesign --force --sign "$signing_identity" --timestamp=none --identifier local.two-click-shottr "$app"
codesign --verify --strict "$app"
requirement=$(stable_requirement "$app")
replace_signed_app "$app" "$PWD/dist/Two Click Shottr.app" "$requirement"
printf 'Built %s\n' "$PWD/dist/Two Click Shottr.app"
