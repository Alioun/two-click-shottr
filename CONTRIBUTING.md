# Contributing

Run `./scripts/check.sh` before submitting a change. Use Swift 6 or later and format Swift sources with `xcrun swift-format format --in-place --recursive Sources Tests`. The formatter configuration lives in `.swift-format`.

Keep the two-click and drag state transitions, zero-area retries, cancellation, shortcut rollback, and saved preferences compatible. Test user-visible behavior through the existing production event handlers where possible. Keep the fixture's pixel oracle independent of production geometry.

Use AppKit, ScreenCaptureKit, CoreGraphics, ImageIO, and Foundation directly where their contracts fit. Keep custom code for app policy and lifecycle guarantees the SDK does not provide. Share a real repeated decision or resource owner; avoid pass-through wrappers and backend protocols with no useful alternatives.

Preserve macOS 13 availability guards. Do not replace the macOS 14+ filtered screenshot API with an unfiltered global-rectangle call. Never discover shareable content or request Screen Recording access during startup or idle permission polling. Keep the positive-cache hotkey path synchronous and reuse prepared selector windows.

The command-line verifiers are development tools. They do not establish physical input delivery, permission continuity after an update, or behavior on display configurations that were not tested. Inspect diagnostic JSON and captures before attaching them publicly; reports can contain executable paths and display geometry.

Keep signing keys, certificates, build outputs, and workstation-specific research outside the source release. `scripts/check-source.py` checks for local paths and signing material in publishable files. It does not audit Git history or establish the absence of every possible credential.
