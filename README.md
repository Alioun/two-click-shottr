# Two Click Shottr

A macOS menu bar companion that selects a screenshot rectangle with two clicks and opens the image in [Shottr](https://shottr.cc/).

Click the first corner, move the pointer, then click the opposite corner. Capture completes when you release the second click. Escape cancels. A crosshair and live coordinates appear as soon as selection starts. Drag selection is also available.

Requires macOS 13 or later and Shottr installed. Native filtered capture is used on macOS 14 and later. macOS 13 uses Apple's `screencapture` utility. The app has no third-party package dependencies and runs no capture stream while idle.

## Download

Download the latest universal app from [GitHub Releases](https://github.com/Alioun/two-click-shottr/releases/latest). Extract the ZIP and move `Two Click Shottr.app` to Applications. The app supports Apple Silicon and Intel Macs.

These downloads are experimental, ad-hoc signed, and not Apple-notarized. Gatekeeper may block them. Consult [Apple's instructions for opening an app from an unidentified developer](https://support.apple.com/guide/mac-help/open-a-mac-app-from-an-unknown-developer-mh40616/mac) before deciding whether to allow it. Updates may require granting Screen Recording access again. For a stable local signing identity, use the source setup below. There is no automatic updater.

## Build and install

Use Xcode or Command Line Tools with Swift 6 or later. The Swift Testing runtime requires macOS 14 or later to run the tests.

From the checkout, run the interactive local setup:

```sh
./scripts/repair-permission.command
```

It creates or reuses a local signing identity, builds the app, offers to install it in `~/Applications`, and guides you through Screen Recording access. You control Keychain and privacy prompts. It preserves the saved shortcut and selection mode.

For later builds with that identity:

```sh
./scripts/build.sh
```

The verified bundle appears at `dist/Two Click Shottr.app`. Quit the installed app before replacing it. To use an existing signing identity, set `CODE_SIGN_IDENTITY` to its exact label or full certificate SHA-1 fingerprint. Ad-hoc signing is rejected because its identity changes with the executable. Certificate signing supplies a stable identity but does not guarantee that macOS retains privacy grants.

This is a local build workflow. The experimental release workflow uses ad-hoc signing separately. Developer ID signing and notarization are not configured. See [release preparation](docs/releasing.md).

## Capture

1. Release **Shift-Command-4** in Shottr. If macOS also uses it, release it in **System Settings > Keyboard > Keyboard Shortcuts > Screenshots**.
2. Launch the companion and press **Shift-Command-4**, or choose **Capture** from its menu.
3. Click both corners. The PNG opens in Shottr.

Choose **Change shortcut…** to record another combination with Command, Control, or Option. Shift is optional. The shortcut is saved only after successful registration. A conflict preserves the previous saved shortcut and attempts to restore it. Capture remains available in the menu.

Choose **Selection mode > Drag** for press, drag, and release. A zero-area two-click selection keeps its first corner for another click. Display changes or switching apps cancel selection.

Screen Recording denial updates the menu without an app alert. The permission menu opens System Settings; navigate to **Privacy & Security > Screen Recording**. macOS may call it Screen & System Audio Recording. Saving and Shottr handoff errors report a recovery path.

A single-display image keeps that display's native resolution. A selection spanning displays uses one pixel per screen point, with transparent display gaps. Separate displays are captured sequentially. Protected content may be unavailable.

Images remain in `~/Library/Caches/local.two-click-shottr/Captures`. The companion never deletes them or uploads them. Cache-cleaning tools may remove them, so save images elsewhere for long-term storage. Shottr handles any actions you take after opening the image.

## Development

```sh
./scripts/check.sh
```

This checks source-release hygiene, shell syntax, isolated script regressions, Swift tests, and release compilation. It needs no signing certificate, captures no desktop pixels, and requests no permission. CI runs the same command on macOS, then packages a universal experimental app. A new app version on `main` publishes a GitHub Release.

Use Apple's formatter before contributing:

```sh
xcrun swift-format format --in-place --recursive Sources Tests
```

See [architecture](docs/architecture.md), [native API audit](docs/native-api-audit.md), [verification](docs/verification.md), and [contributing](CONTRIBUTING.md).

## License

[MIT](LICENSE). This project is independent of Shottr. Shottr is a separate application and is not included in this repository.
