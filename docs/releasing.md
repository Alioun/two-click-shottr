# Releases

This public repository starts with a clean source snapshot. Its MIT license covers the companion. Shottr, private signing material, workstation diagnostics, and earlier development history are excluded.

## Automated app releases

Every push and pull request runs `scripts/check.sh` on macOS 15, then builds a universal arm64 and x86_64 app with `scripts/package-experimental.sh`. The app deployment target remains macOS 13. CI uploads the ZIP, DMG, and their SHA-256 files as workflow artifacts.

On `main`, a successful build publishes a GitHub Release when `CFBundleShortVersionString` in `Resources/Info.plist` has not been released before. The initial version is 1.1.0. Existing releases and their assets remain unchanged. A manual workflow run can retry a failed publication without changing the version.

To release an update:

1. Set a new `major.minor.patch` version and increment `CFBundleVersion` in `Resources/Info.plist`.
2. Run `./scripts/check.sh` and the applicable live checks in [verification](verification.md).
3. Push the update to `main`. CI must pass before publication.
4. Download the ZIP or DMG and its matching `.sha256` file from the GitHub Release. From the download directory, verify the format you chose:

   ```sh
   shasum -a 256 -c TwoClickShottr-VERSION-universal-experimental.zip.sha256
   # For the DMG instead:
   shasum -a 256 -c TwoClickShottr-VERSION-universal-experimental.dmg.sha256
   ```

`scripts/create-dmg.sh APP OUTPUT` builds the DMG window. `scripts/dmg-layout.swift` draws the background with AppKit and lays out the icons through Finder AppleScript on a temporary writable image. The window puts the app on the left, an arrow and drag instruction in the middle, and an `Applications` link on the right. The script then converts the image to compressed UDZO. It reads the icon view and icon positions back from Finder on a read-only mount, and it fails instead of shipping an unstyled DMG. Finder must accept Apple events from the build shell; a refusal fails packaging. The readback check covers the icon layout. Open the finished DMG to inspect its background.

For a DMG content check, mount it read-only with `hdiutil attach -nobrowse -readonly IMAGE.dmg`. Verify the app with `codesign --verify --strict --all-architectures "/Volumes/Two Click Shottr/Two Click Shottr.app"`, confirm that `Applications` links to `/Applications`, then detach with `hdiutil detach "/Volumes/Two Click Shottr"`. Use the actual mount path printed by `hdiutil` if that volume name is already in use.

The release tag points to the exact built commit. Version numbers must be unique; reusing a released version does not update its download. GitHub supplies source archives for each tag. The workflow uses the repository's temporary token and requires no private signing credentials. Only the release job has repository write permission. Fork pull requests cannot publish releases.

## Experimental signing

Downloads are explicitly labeled experimental. They are ad-hoc signed, not Developer ID signed or notarized. Gatekeeper may block them, and updates can invalidate Screen Recording permission. Checksums detect download corruption but do not provide a Developer ID identity. There is no automatic updater.

`./scripts/package-experimental.sh` produces the same universal ZIP and DMG locally. It does not install the app or change Keychain or privacy settings. Keep this path separate from `build.sh` and `repair-permission.command`, which use a stable local certificate and reject ad-hoc identities.

Developer ID signing, hardened runtime, notarization, and validation must be configured before offering notarized downloads. See [Apple's notarization documentation](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).

## Source archives

Run `python3 scripts/source-archive.py` to package eligible current source in `.build/TwoClickShottr-source.tar.gz`. It excludes Git history and ignored build or diagnostic files. Extract it into a fresh directory and run `./scripts/check.sh` before publishing it separately. The script includes uncommitted source; inspect the result.

Keep a compatible designated requirement across certificate-signed updates. See [TN3127](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements). Signing does not grant screen access or guarantee permission continuity. Keychain, trust, and Screen Recording changes remain person-driven steps.
