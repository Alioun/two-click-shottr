# Native API audit

Audit date: 2026-10-24. Every explicitly declared application function and initializer was inspected, including diagnostic helpers. Synthesized Codable, Equatable, RawRepresentable, and CaseIterable implementations remain compiler-provided. Computed properties and AppKit overrides were checked with their owning types. Tests remain behavioral verification, not candidates for replacing the behavior they assert.

The audit replaced the handwritten Shottr continuation bridge with the native async document-open API and consolidated actual repeated decisions. Retained custom code below expresses app policy or lifecycle guarantees beyond a single SDK call. No claim is made that every newer API is a behavioral equivalent.

## SDK contracts

- [Filtered screenshots](https://developer.apple.com/documentation/screencapturekit/scscreenshotmanager) and [application exclusion](https://developer.apple.com/documentation/screencapturekit/sccontentfilter).
- [Native document handoff](https://developer.apple.com/documentation/appkit/nsworkspace/open(_:withapplicationat:configuration:completionhandler:)). The async overload was also typechecked against the installed SDK with a macOS 13 deployment target.
- [Screen capture preflight](https://developer.apple.com/documentation/coregraphics/cgpreflightscreencaptureaccess()) and [request](https://developer.apple.com/documentation/coregraphics/cgrequestscreencaptureaccess()). The SDK header states that preflight does not prompt and previous denial requires Settings.
- [System cursor probe](https://developer.apple.com/documentation/appkit/nscursor/currentsystem) and [application cursor](https://developer.apple.com/documentation/appkit/nscursor/current). These are different observations.
- [Layer scale](https://developer.apple.com/documentation/quartzcore/calayer/contentsscale), [backing changes](https://developer.apple.com/documentation/appkit/nsview/viewdidchangebackingproperties()), and [screen observations](https://developer.apple.com/documentation/appkit/nsscreen/screens).
- Carbon global-hotkey options and thread restrictions are documented in the installed SDK headers `CarbonEvents.h` and `CarbonEventsCore.h`. The reviewed contracts support exclusive registration and require serialized access.
- [Process termination](https://developer.apple.com/documentation/foundation/process/terminate()) sends SIGTERM; [waiting](https://developer.apple.com/documentation/foundation/process/waituntilexit()) blocks. Neither supplies the complete runner lifecycle.

## Application inventory

### App.swift

Native AppKit orchestration. Menu and lifecycle adapters use NSApplication, NSMenu, NSAlert, and NSWorkspace. Permission presentation, activity serialization, and capture sequencing remain app policy.

Checked declarations: `applicationDidFinishLaunching`, `configureMenu`, `updateShortcutItems`, `changeShortcut`, `changeMode`, `updateModeItems`, `applicationDidBecomeActive`, `refreshPermission`, `updatePermissionItem`, `beginCapture`, `requestPermission`, `startSelection`, `finishSelection`, `permissionHelp`, `applicationShouldTerminate`, `applicationWillTerminate`, `showError`, `main`.

### AppIdentity.swift

Shared native file destination. FileManager resolves the user caches directory. Both capture backends share unique destination creation; identifiers remain explicit stable values.

Checked declarations: `makeURL`.

### Capture/Capture.swift

Native SDK and required compatibility. Filtered SCScreenshotManager, ImageIO, and the verified native async NSWorkspace API handle SDK work. Availability routing, exclusions, output policy, topology validation, and stage-specific recovery remain explicit. The macOS 13 CLI is retained.

Checked declarations: `capture`, `captureLegacy`, `captureNative`, `validateDisplays`, `writePNG`, `openInShottr`.

### Capture/CaptureFailure.swift

Structured native errors plus app policy. NSError and ScreenCaptureKit supply domain/code/underlying errors. Bounded traversal and nonmodal presentation classification are app policy; arbitrary error codes alone never establish denial.

Checked declarations: `native`.

### Capture/CapturePlan.swift

Native geometry and raster APIs. CGRect supplies intersections; CGContext supplies composition. Coordinate conventions, one-pixel-per-point spanning output, transparent gaps, and deterministic placement remain settled app policy.

Checked declarations: `init`, `compose`.

### Capture/ProcessRunner.swift

Native process APIs plus owned lifecycle. Foundation Process/Pipe and POSIX signaling are already native. Deadline enforcement, cancellation, escalation, bounded nonblocking stderr, and reaping are additional guarantees. No equivalent single SDK operation was established.

Checked declarations: `run`, `cancel`, `cancelAndWait`, `execute`, `drain`.

### Capture/ScreenCaptureAccess.swift

Native permission observation plus ordering. CGPreflightScreenCaptureAccess supplies nonprompting access observation. Background execution, coalescing, and revision-safe cache updates have no equivalent established in the reviewed SDK contracts.

Checked declarations: `init`, `refresh`, `record`.

### Diagnostics/CaptureFixture.swift

Native image/view APIs plus independent fixture. CGImage/CGDataProvider/NSImage/NSView supply rendering. The deterministic asymmetric pixel pattern and expected crop remain independent oracle logic. Reusing production geometry would weaken the test.

Checked declarations: `windowFrame`, `color`, `raster`, `init`, `init?`, `draw`.

### Diagnostics/CursorProbe.swift

Shared best-effort native probe. The two cursor verifiers share observation and polling. NSCursor.currentSystem is deprecated and may be unavailable. NSCursor.current observes the application cursor and is not an equivalent proof of the displayed system cursor.

Checked declarations: `waitForCrosshair`.

### Diagnostics/HotKeyVerification.swift

Native registration checked across processes. The production exclusive-registration method and ProcessRunner are reused. A parent and child establish conflict/release behavior without injecting keyboard input.

Checked declarations: `contend`, `run`.

### Diagnostics/ResourceProfile.swift

Native process measurements plus workload. getrusage and monotonic uptime supply process measurements. The production event workload and phase reporting are diagnostic policy; peak RSS is a lifetime high-water mark.

Checked declarations: `init`, `report`, `seconds`, `run`.

### Diagnostics/TriggerVerification.swift

Native Carbon injection plus observation. The production handler is exercised with a local event and capture disabled. Timings and pointer stability remain diagnostic logic; physical input dispatch is not measured.

Checked declarations: `triggerLatency`.

### Diagnostics/Verification.swift

Native event/report/image APIs plus test oracle. JSONSerialization, NSEvent, NSWindow, and NSBitmapImageRep supply native operations. Scenario assertions, independent pixel comparisons, and cleanup before terminal reporting remain required verification logic.

Checked declarations: `finish`, `cursor`, `diagnose`, `frameFacts`, `inject`, `escape`, `selection`, `check`, `capture`, `inspect`.

### LaunchMode.swift

Application policy. One enum parses established flags and prevents observation-only workloads from capturing. Foundation supplies arguments, not this dispatch contract.

Checked declarations: `init`.

### Selection/Overlay.swift

Native AppKit and Core Animation. Responder overrides, view/window conversion, shape layers, and cursor APIs are native. Shared state, prewarming, observer cleanup, coordinate labels, and selective redraw remain app policy. Activation is availability-guarded.

Checked declarations: `sendEvent`, `keyDown`, `hitTest`, `draw`, `acceptsFirstMouse`, `init`, `init?`, `prewarm`, `mouseDown`, `mouseUp`, `mouseMoved`, `mouseDragged`, `cancelOperation`, `globalPoint`, `updateLayer`, `viewDidChangeBackingProperties`, `layout`, `updateOverlay`, `init`, `prepare`, `discardPreparedWindows`, `start`, `refreshCursor`, `receive`, `hide`, `activateCompanion`.

### Selection/Selection.swift

Interaction policy using native CGRect. The state machine preserves first/second release semantics, drag completion, terminal-event suppression, and zero-area retries. Native gestures do not establish these complete semantics.

Checked declarations: `receive`, `rectangle`, `quartzRect`, `argument`.

### Shortcuts/CaptureShortcut.swift

Native events, settings, and modal controls. NSEvent, UserDefaults, Codable, NSAlert, and a scoped local monitor perform SDK work. One modifier table is reused for Carbon conversion, menu flags, and labels. Save-on-success, rollback, and validation remain app policy.

Checked declarations: `init`, `init?`, `load`, `persist`, `init`, `activate`, `beginRecording`, `finishRecording`, `failure`, `record`.

### Shortcuts/GlobalHotKey.swift

Native Carbon ownership. One owner centralizes event identity, handler installation, exclusive registration, dispatch, and release. No equivalent AppKit global-hotkey registration contract was established. Verification uses the same registration policy.

Checked declarations: `init`, `install`, `register`, `register`, `unregister`, `invalidate`, `deliverPress`.

## Tooling inventory

| File | Checked functions | Native boundary and retained policy |
| --- | --- | --- |
| `build.sh` | Top-level entrypoint | Native Swift compiler and codesign; staged, verified local bundle construction. |
| `check-source.py` | Top-level entrypoint | Shared repository validator; no second file-discovery implementation. |
| `check.sh` | Top-level entrypoint | Native formatter, Bash parser, and existing test entrypoints. No app or permission interaction. |
| `package-experimental.sh`, `publish-release.sh` | Top-level entrypoints | Native universal Swift build, lipo, otool, codesign, ditto and shasum; GitHub CLI publishes a new version after CI. |
| `profile-resources.py` | `run`, `main` | Standard-library subprocess, JSON, time, statistics, and argparse; visible workload sequencing and metric aggregation are diagnostic policy. |
| `repair-input.sh` | `repair_read`, `repair_confirm`, `repair_pause` | Bash read/printf with terminal and EOF checks. The confirmation gate is app setup policy. |
| `repair-permission.command` | `stage`, `say`, `warn`, `run_wizard` | Native openssl, security, codesign, open, tccutil and filesystem tools; app-specific human-driven stages. The unrelated copied wizard library was removed. |
| `repository.py` | `source_files`, `validate_source` | Standard-library Git/file enumeration and validation shared by hygiene and packaging. This checks specific publishing hazards, not arbitrary credentials or history. |
| `signing-support.sh` | `resolve_signing_identity`, `designated_requirement`, `stable_requirement`, `cleanup_replacement`, `reserve_signing_setup` | Native security, codesign, ditto, and mv; exact identity selection, requirement evaluation, rollback and failed-import recovery remain script policy. |
| `source-archive.py` | `public_metadata`, `main` | Standard-library tarfile and argparse; source-only packaging strips workstation ownership metadata and excludes its own output. |
| `swift.sh` | Top-level entrypoint | One exec of native swift with shared build/cache flags. |
| `test-script-regressions.py` | `setUp`, `tearDown`, `shell`, `helper`, `commands`, `test_identity_suffix_duplicate_and_ambiguity`, `test_actual_codesign_requirement_stdout`, `test_stable_requirement_accepts_default_certificate_anchors`, `test_prompt_rejects_nonterminal_and_tty_eof`, `test_json_false_ready_and_timeout`, `replacement`, `test_replacement_removes_leftovers`, `test_replacement_rolls_back_all_failures`, `test_replacement_failure_without_prior_install`, `test_failed_rollback_retains_previous_bundle`, `build_fixture`, `test_missing_certificate_leaves_dist_and_never_builds`, `test_build_signing_failure_leaves_dist`, `test_build_success_replaces_dist`, `test_failed_import_marker_refuses_regeneration`, `test_installed_cli_diagnosis_denial_capture_and_timeout` | All regression cases and fixture helpers retained except the unused confirm-no helper scenario. These assert rollback, failure isolation, identity parsing and report completion using stubs. |
| `verification-support.sh` | `report_boolean`, `wait_for_report`, `launch_installed_report` | Native plutil JSON extraction and LaunchServices open; complete-report polling and distinct exit statuses remain protocol logic. |
| `verify-installed.sh` | `usage` | Argument handling and orchestration through shared report helpers. No direct-executable permission attribution assumption. |

The initial cleanup inventory contained 108 explicit function/initializer declarations. The later appearance settings are documented in [appearance settings](appearance.md). Computed properties covered above include selection previews and titles, shortcut validation/labels/menu flags, cursor matching, backend naming, capture failure presentation, fixture dimensions, process identity, and native responder/drawing overrides.

## Retained limits

The macOS 13 command-line backend retains its empirical compositor allowance and helper-attribution limits. A short SCStream fallback would be a separate feature with additional lifecycle obligations, not an equivalent cleanup.

The native screenshot API does not document cancellation of in-flight acquisition. Cancellation discards late results and prevents handoff; it does not promise to abort framework work. Per-display capture is not simultaneous.

No public binary signing, notarization, publication, Git-history rewrite, Keychain mutation, or privacy-grant change is part of this audit.
