# Verification

Run the noninteractive checks from a checkout:

```sh
./scripts/check.sh
```

The Swift tests cover selection, shortcut persistence and rollback, prepared-window reuse, layer rendering, permission-cache ordering, native error classification, composition, pixel verification, and subprocess lifecycle. Script regressions isolate signing and installation behavior with command stubs. They do not modify Keychain, trust, TCC, or the installed app.

## Release executable checks

After `./scripts/swift.sh build -c release`, locate the executable with `./scripts/swift.sh build -c release --show-bin-path`.

| Argument | Behavior and limit |
| --- | --- |
| `--verify-selection` | Injects NSEvents through hidden production windows. Checks release timing, retries, Escape, deactivation, topology changes, and shared selection state. It does not prove physical cross-display event delivery. |
| `--verify-exclusive-hotkey` | Uses two real processes to check conflict and release for Control-Option-Shift-Command-F19. No keyboard input is injected or saved shortcut changed. |
| `--diagnose` | Reports effective permission, version, backend, executable path, and display geometry. It never requests access. |
| `--verify-cursor` | Briefly shows the selector and requires an unchanged pointer. The deprecated system-cursor probe is best effort; an unavailable probe cannot establish displayed cursor identity. |
| `--verify-trigger-latency` | Sends an app-local Carbon event through the production handler with a test-only permission cache. Image capture is disabled. It excludes physical keyboard dispatch latency. |
| `--profile-resources` | Exercises idle, stationary selection, and injected pointer updates. Measures process CPU and peak RSS, excluding WindowServer and GPU resources. |

Cursor and latency checks compare cursor image data as an observation, not an Apple guarantee of canonical cursor identity. Activation is asynchronous and may fail to become effective. A failed probe needs inspection; it is not automatically proof of a capture defect.

## Installed capture acceptance

Use LaunchServices to check the actual installed bundle:

```sh
./scripts/verify-installed.sh --diagnose
./scripts/verify-installed.sh --capture
```

The capture check requires an existing grant. It briefly displays an asymmetric fixture and production overlays, selects through the real handlers, validates the PNG's origin and every expected pixel, and opens it in Shottr. On macOS 14+ it also leaves a magenta companion window over the target to verify app exclusion. Only the fixture is excepted from the filter. Presentation waits belong to this fixture; they are not production capture delays or compositor fences.

A successful workspace handoff establishes that macOS accepted opening the PNG in Shottr, not that its editor completed rendering. Inspect the result. Failed verification preserves the image. Direct executable results do not establish the installed app's permission.

Run live acceptance on the intended negative-origin, multi-display, mixed-density, and display-gap configurations. The automated composition tests do not replace those setups. Consent-dialog interaction, revoked access, and privacy continuity after a signed update require person-driven checks.

The resource comparison tool accepts two prepared app bundles:

```sh
python3 scripts/profile-resources.py BASELINE.app CANDIDATE.app --output .build/comparison
```

Keep raw reports and report failed workloads. Peak resident memory is a process lifetime high-water mark, not memory allocated by one phase. Do not attach captures or raw workstation diagnostics publicly without inspecting them.

## Appearance and hidden-icon recovery

`./scripts/check.sh` runs the two native Settings-window tests in a separate test process. They activate and close AppKit windows, so they must not share the other tests' application lifecycle. They do not request screen capture access. The appearance tests cover saved values, numeric bounds, all four quadrants at screen edges, font changes in reused overlays, native control actions, and reopening Settings with a saved hidden-icon preference.

For a visible check, open Settings, change each slider and position, then start a capture without moving the pointer. Confirm that the custom cursor appears immediately. Cancel, hide the menu icon, and confirm the shortcut still starts capture. Reopen the app from Finder or Spotlight and restore the icon. Confirm the preferences survive a relaunch. A locked desktop cannot verify visible cursor activation.

The cursor probe compares native bitmap renders at a shared resolution, plus logical image size and hot spot. TIFF-container equality is insufficient for custom cursors because AppKit may return different image representations for the same rendered shape. The probe still uses Apple's deprecated `currentSystem` observation API, so a missing probe is unavailable evidence. Automated checks must have foreground activation before verifying the displayed cursor.
