# Architecture

`AppDelegate` owns menu actions, the current activity, permission presentation, and the capture task. A capture command uses the cached permission observation to show the prepared selector immediately. After selection, it rechecks access, acquires a PNG, and asks Shottr to open it. Permission denial and capture failures stay nonmodal; save and handoff errors retain recovery details.

| Area | Ownership |
| --- | --- |
| `App.swift`, `LaunchMode.swift` | AppKit lifecycle, menu actions, serialized activity, diagnostic dispatch |
| `AppIdentity.swift` | Stable application identifiers and shared capture-file destination creation |
| `Selection/Selection.swift` | Pure two-click and drag state transitions, normalized rectangles, AppKit-to-capture conversion |
| `Selection/Overlay.swift` | Prepared reusable windows, shared input routing, shape layers, coordinates, cursor and cancellation observers |
| `Shortcuts/CaptureShortcut.swift` | Shortcut value, modifier mapping, persistence, recorder, registration transaction and rollback |
| `Shortcuts/GlobalHotKey.swift` | One Carbon handler, one registration, event identity, exclusive registration, explicit cleanup |
| `Capture/Capture.swift` | Availability routing, filtered screenshots, macOS 13 compatibility capture, PNG encoding, async Shottr handoff |
| `Capture/CapturePlan.swift` | Display intersections and one-pixel-per-point multi-display composition |
| `Capture/CaptureFailure.swift` | Structured native error classification and presentation stages |
| `Capture/ScreenCaptureAccess.swift` | Nonprompting background preflight, coalescing, revision-safe cache |
| `Capture/ProcessRunner.swift` | Direct-child execution, bounded stderr, deadlines, cancellation, escalation and reaping |
| `Diagnostics/` | Event injection, cursor probing, capture fixture and pixel oracle, hotkey verification, resource workload |

The native screenshot path excludes this process and captures each participating display through a filter. It creates no persistent stream and needs no compositor delay. The macOS 13 subprocess retains a 200 ms empirical allowance after hiding overlays. Native failures never retry through the compatibility backend.

Selection geometry stays in global AppKit points until one conversion at the capture boundary. Native source rectangles are display-local points; configured image dimensions are pixels. One display retains its native scale. Multiple displays use one output pixel per point, sRGB composition, and transparent gaps. Display tiles are not an atomic desktop exposure.

`ProcessRunner` is intentionally more than an async wrapper around Foundation `Process`. It must bound stderr and deadlines, avoid waiting for inherited pipes to reach EOF, escalate beyond SIGTERM when needed, and reap the direct child. Normal cancellation signals without joining on AppKit's thread. Termination waits on a worker before replying to AppKit.

The setup scripts share signing, input, and installed-report helpers. `swift.sh` centralizes package build flags. `repository.py` supplies the same candidate file set to source validation and source packaging. The local signing wizard remains person-driven.
