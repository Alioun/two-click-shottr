import AppKit

@MainActor
enum Verification {
    static func finish(_ report: [String: Any], success: Bool) -> Never {
        let data: Data
        do {
            data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        } catch {
            FileHandle.standardOutput.write(
                Data("{\"passed\":false,\"error\":\"Diagnostic report could not be encoded.\"}\n".utf8))
            exit(1)
        }
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
        exit(success ? 0 : 1)
    }

    static func cursor() async -> Never {
        let previousApp = NSWorkspace.shared.frontmostApplication
        try? await Task.sleep(nanoseconds: 300_000_000)
        let initialPointer = NSEvent.mouseLocation
        let selection = SelectionController(mode: .twoClick, reuseWindows: true) { _ in }
        let warmupStarted = ProcessInfo.processInfo.systemUptime
        selection.prepare()
        let warmupDuration = ProcessInfo.processInfo.systemUptime - warmupStarted
        NSCursor.arrow.set()
        let started = ProcessInfo.processInfo.systemUptime
        selection.start()
        let startReturned = ProcessInfo.processInfo.systemUptime
        let presentOnReturn = CursorProbe(expected: selection.cursor).matchesCrosshair
        let probe = await CursorProbe.waitForCursor(selection.cursor)
        let observed = ProcessInfo.processInfo.systemUptime
        let active = probe.applicationActive
        let unchangedPointer = NSEvent.mouseLocation == initialPointer
        let matches = probe.matchesCrosshair
        selection.receive(.cancel)
        selection.discardPreparedWindows()
        previousApp?.activate(options: [])
        let permissionStarted = ProcessInfo.processInfo.systemUptime
        let allowed = CGPreflightScreenCaptureAccess()
        let permissionDuration = ProcessInfo.processInfo.systemUptime - permissionStarted
        finish(
            [
                "verification": "cursor", "passed": active && unchangedPointer && matches,
                "applicationActive": active, "pointerUnchanged": unchangedPointer,
                "systemCursorMatchesCrosshair": matches,
                "systemCursorProbeAvailable": probe.cursor != nil,
                "cursorProbeLimit":
                    "Apple deprecates currentSystem. A nil probe cannot verify the displayed cursor.",
                "crosshairPresentOnStartReturn": presentOnReturn,
                "warmupMilliseconds": warmupDuration * 1000,
                "startMilliseconds": (startReturned - started) * 1000,
                "crosshairMilliseconds": (observed - started) * 1000,
                "permissionPreflightMilliseconds": permissionDuration * 1000,
                "screenCapturePermission": allowed,
                "injection":
                    "Visible production overlays with no injected mouse events. Checks the system cursor after activation and requires an unchanged pointer.",
            ],
            success: active && unchangedPointer && matches)
    }

    static func diagnose() -> Never {
        finish(
            [
                "screenCapturePermission": CGPreflightScreenCaptureAccess(),
                "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
                    ?? "development",
                "build": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
                    ?? "development",
                "executable": Bundle.main.executableURL?.path ?? "unknown",
                "captureBackend": CaptureService.backendName,
                "screens": NSScreen.screens.map { screen in
                    ["frame": frameFacts(screen.frame), "backingScaleFactor": screen.backingScaleFactor]
                        as [String: Any]
                },
            ], success: true)
    }

    private static func frameFacts(_ frame: CGRect) -> [String: CGFloat] {
        ["x": frame.minX, "y": frame.minY, "width": frame.width, "height": frame.height]
    }

    static func inject(_ type: NSEvent.EventType, at global: CGPoint, into window: SelectionWindow) {
        let event = NSEvent.mouseEvent(
            with: type, location: window.convertPoint(fromScreen: global),
            modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil,
            eventNumber: 1, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0)!
        window.sendEvent(event)
    }

    static func escape(into window: SelectionWindow) {
        let event = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}",
            isARepeat: false, keyCode: 53)!
        window.sendEvent(event)
    }

    static func selection() -> Never {
        var results: [[String: Any]] = []
        func check(_ name: String, _ passed: Bool) { results.append(["name": name, "passed": passed]) }
        let frame = CGRect(x: 100, y: 100, width: 500, height: 400)
        let a = CGPoint(x: 180, y: 180)
        let b = CGPoint(x: 340, y: 280)
        var completions: [CGRect?] = []
        let twoClick = SelectionController(mode: .twoClick) { completions.append($0) }
        twoClick.start(frames: [frame], visible: false)
        let window = twoClick.windows[0]
        inject(.leftMouseDown, at: a, into: window)
        inject(.leftMouseDragged, at: b, into: window)
        inject(.leftMouseUp, at: a, into: window)
        check(
            "first release leaves overlay and no result", completions.isEmpty && twoClick.windows.count == 1)
        inject(.mouseMoved, at: b, into: window)
        check("movement previews rectangle", twoClick.state.preview == CaptureGeometry.rectangle(a, b))
        inject(.leftMouseDown, at: b, into: window)
        check("second press does not finish", completions.isEmpty && twoClick.windows.count == 1)
        inject(.leftMouseUp, at: b, into: window)
        check(
            "second release finishes and removes overlay",
            completions.count == 1 && completions[0] == CaptureGeometry.rectangle(a, b)
                && twoClick.windows.isEmpty && !window.isVisible)
        inject(.leftMouseUp, at: b, into: window)
        check("completion occurs once", completions.count == 1)

        var reversed: CGRect?
        let drag = SelectionController(mode: .drag) { reversed = $0 }
        drag.start(frames: [frame], visible: false)
        let dragWindow = drag.windows[0]
        inject(.leftMouseDown, at: b, into: dragWindow)
        inject(.leftMouseDragged, at: a, into: dragWindow)
        check("drag waits for release", reversed == nil)
        inject(.leftMouseUp, at: a, into: dragWindow)
        check("reverse drag normalizes on release", reversed == CaptureGeometry.rectangle(a, b))

        var retries: [CGRect?] = []
        let retry = SelectionController(mode: .twoClick) { retries.append($0) }
        retry.start(frames: [frame], visible: false)
        let retryWindow = retry.windows[0]
        for _ in 0..<2 {
            inject(.leftMouseDown, at: a, into: retryWindow)
            inject(.leftMouseUp, at: a, into: retryWindow)
        }
        check("zero area keeps waiting", retries.isEmpty && retry.windows.count == 1)
        inject(.leftMouseDown, at: b, into: retryWindow)
        inject(.leftMouseUp, at: b, into: retryWindow)
        check("zero area can retry", retries.count == 1 && retries[0] == CaptureGeometry.rectangle(a, b))

        var cancelled = false
        let cancel = SelectionController(mode: .twoClick) { cancelled = $0 == nil }
        cancel.start(frames: [frame], visible: false)
        let cancelWindow = cancel.windows[0]
        inject(.leftMouseDown, at: a, into: cancelWindow)
        inject(.leftMouseUp, at: a, into: cancelWindow)
        escape(into: cancelWindow)
        check("escape cancels and removes overlay", cancelled && cancel.windows.isEmpty)

        var displayCancelled = false
        let display = SelectionController(mode: .drag) { displayCancelled = $0 == nil }
        display.start(frames: [frame], visible: false)
        NotificationCenter.default.post(
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        check("display change cancels", displayCancelled && display.windows.isEmpty)

        for mode in SelectionMode.allCases {
            for anchored in [false, true] {
                var deactivations: [CGRect?] = []
                let deactivate = SelectionController(mode: mode) { deactivations.append($0) }
                deactivate.start(frames: [frame], visible: false)
                let deactivateWindow = deactivate.windows[0]
                if anchored {
                    inject(.leftMouseDown, at: a, into: deactivateWindow)
                    if mode == .twoClick { inject(.leftMouseUp, at: a, into: deactivateWindow) }
                }
                NotificationCenter.default.post(
                    name: NSApplication.didResignActiveNotification, object: NSApp)
                check(
                    "deactivation cancels \(mode) with anchor \(anchored) and removes overlays",
                    deactivations.count == 1 && deactivations[0] == nil && deactivate.state == .cancelled
                        && deactivate.windows.isEmpty && !deactivateWindow.isVisible)
                NotificationCenter.default.post(
                    name: NSApplication.didResignActiveNotification, object: NSApp)
                escape(into: deactivateWindow)
                inject(.leftMouseUp, at: b, into: deactivateWindow)
                check(
                    "deactivation completion occurs once for \(mode) with anchor \(anchored)",
                    deactivations.count == 1)
            }
        }

        var across: CGRect?
        let shared = SelectionController(mode: .twoClick) { across = $0 }
        shared.start(frames: [CGRect(x: -500, y: 100, width: 500, height: 400), frame], visible: false)
        let left = shared.windows[0]
        let right = shared.windows[1]
        let negative = CGPoint(x: -180, y: 240)
        inject(.leftMouseDown, at: negative, into: left)
        inject(.leftMouseUp, at: negative, into: left)
        inject(.mouseMoved, at: b, into: right)
        inject(.leftMouseDown, at: b, into: right)
        inject(.leftMouseUp, at: b, into: right)
        check(
            "windows share anchor across negative origin",
            across == CaptureGeometry.rectangle(negative, b) && shared.windows.isEmpty)

        let success = results.allSatisfy { $0["passed"] as? Bool == true }
        finish(
            [
                "verification": "selection", "passed": success, "checks": results,
                "injection":
                    "NSWindow.sendEvent routes NSEvents into production handlers. Display-change and deactivation notifications exercise production cleanup observers. No global input or live app switching.",
            ], success: success)
    }

    static func capture() async -> Never {
        guard CGPreflightScreenCaptureAccess() else {
            finish(
                [
                    "verification": "capture", "passed": false,
                    "error":
                        "Screen recording permission is missing. Launch the app and choose Capture to request it, then rerun this command.",
                ], success: false)
        }
        guard let screen = NSScreen.screens.first else {
            finish(
                ["verification": "capture", "passed": false, "error": "No display is available."],
                success: false)
        }
        let fixture = CaptureFixture(scale: screen.backingScaleFactor)
        let fixtureView: CaptureFixtureView
        do {
            fixtureView = try CaptureFixtureView(fixture: fixture)
        } catch {
            finish(
                ["verification": "capture", "passed": false, "error": error.localizedDescription],
                success: false)
        }
        let frame = CaptureFixture.windowFrame(in: screen.visibleFrame)
        let testWindow = NSWindow(
            contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        testWindow.isReleasedWhenClosed = false
        testWindow.colorSpace = .sRGB
        testWindow.contentView = fixtureView
        testWindow.isOpaque = true
        testWindow.hasShadow = false
        testWindow.level = .floating
        testWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        testWindow.orderFrontRegardless()
        activateCompanion()
        var exclusionProbe: NSWindow?
        defer {
            exclusionProbe?.close()
            testWindow.close()
        }
        do {
            try await Task.sleep(nanoseconds: 300_000_000)
            let desired = CaptureFixture.selection.offsetBy(
                dx: testWindow.frame.minX, dy: testWindow.frame.minY)
            var selected: CGRect?
            let controller = SelectionController(mode: .twoClick) { selected = $0 }
            controller.start()
            let overlays = controller.windows
            defer { controller.hide() }
            guard let window = overlays.first else {
                throw CaptureFailure(message: "No overlay was created.")
            }
            let a = desired.origin
            let b = CGPoint(x: desired.maxX, y: desired.maxY)
            inject(.leftMouseDown, at: a, into: window)
            inject(.leftMouseUp, at: a, into: window)
            inject(.mouseMoved, at: b, into: window)
            for overlay in overlays { overlay.displayIfNeeded() }
            // Give the compositor time to show the yellow selection border before testing its removal.
            try await Task.sleep(nanoseconds: 300_000_000)
            inject(.leftMouseDown, at: b, into: window)
            guard selected == nil else {
                throw CaptureFailure(message: "Capture completed before the second release.")
            }
            inject(.leftMouseUp, at: b, into: window)
            guard selected == desired, overlays.allSatisfy({ !$0.isVisible }), controller.windows.isEmpty
            else {
                throw CaptureFailure(message: "The selection handlers did not finish and hide all overlays.")
            }
            if #available(macOS 14.0, *) {
                let probe = NSWindow(
                    contentRect: desired, styleMask: .borderless, backing: .buffered, defer: false)
                probe.isReleasedWhenClosed = false
                probe.backgroundColor = .magenta
                probe.isOpaque = true
                probe.hasShadow = false
                probe.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
                probe.orderFrontRegardless()
                exclusionProbe = probe
                try await Task.sleep(nanoseconds: 200_000_000)
            }
            let quartz = CaptureGeometry.quartzRect(desired, primaryTop: screen.frame.maxY)
            let file = try await CaptureService.capture(
                quartz, exceptingWindows: [CGWindowID(testWindow.windowNumber)])
            do {
                let pixels = try inspect(file, fixture: fixture)
                try await CaptureService.openInShottr(file)
                exclusionProbe?.close()
                testWindow.close()
                finish(
                    [
                        "verification": "capture", "passed": true, "capturePath": file.path,
                        "quartzRect": frameFacts(quartz), "pixels": pixels,
                        "overlayWindowsHidden": true, "openedInShottr": true,
                        "visibleOwnWindowExcluded": exclusionProbe != nil,
                        "captureBackend": CaptureService.backendName,
                    ], success: true)
            } catch {
                throw CaptureFailure(
                    message: "\(error.localizedDescription)\nCapture retained at \(file.path)")
            }
        } catch {
            exclusionProbe?.close()
            testWindow.close()
            finish(
                ["verification": "capture", "passed": false, "error": error.localizedDescription],
                success: false)
        }
    }

    static func inspect(_ file: URL, fixture: CaptureFixture) throws -> [String: Any] {
        let data = try Data(contentsOf: file)
        guard let bitmap = NSBitmapImageRep(data: data) else {
            throw CaptureFailure(message: "The PNG could not be decoded.")
        }
        let crop = fixture.cropPixels
        let expectedWidth = Int(crop.width.rounded())
        let expectedHeight = Int(crop.height.rounded())
        guard bitmap.pixelsWide == expectedWidth, bitmap.pixelsHigh == expectedHeight else {
            throw CaptureFailure(
                message:
                    "Unexpected PNG dimensions \(bitmap.pixelsWide)x\(bitmap.pixelsHigh), expected \(expectedWidth)x\(expectedHeight)."
            )
        }
        guard let normalized = bitmap.converting(to: .sRGB, renderingIntent: .default),
            normalized.bitsPerSample == 8, normalized.samplesPerPixel >= 3
        else {
            throw CaptureFailure(message: "The PNG could not be normalized to 8-bit sRGB.")
        }
        var mismatches = 0
        var maxError: CGFloat = 0
        var components = [Int](repeating: 0, count: normalized.samplesPerPixel)
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                // colorAt reports calibrated RGB even for tagged P3 data. Normalize the bitmap before reading samples.
                normalized.getPixel(&components, atX: x, y: y)
                let expected = fixture.color(x: Int(crop.minX) + x, y: Int(crop.minY) + y)
                let error =
                    max(
                        abs(CGFloat(components[0]) - CGFloat(expected.red)),
                        abs(CGFloat(components[1]) - CGFloat(expected.green)),
                        abs(CGFloat(components[2]) - CGFloat(expected.blue))) / 255
                maxError = max(maxError, error)
                if error > 0.035 { mismatches += 1 }
            }
        }
        guard mismatches == 0 else {
            throw CaptureFailure(
                message:
                    "\(mismatches) pixels differ from the coordinate fixture. Maximum channel error \(maxError). The crop origin or orientation is wrong, or an overlay or another window contaminated the capture."
            )
        }
        return [
            "width": bitmap.pixelsWide, "height": bitmap.pixelsHigh,
            "checkedPixels": bitmap.pixelsWide * bitmap.pixelsHigh, "mismatches": mismatches,
            "maximumChannelError": maxError,
            "pattern": "asymmetric sRGB coordinate tiles", "cropOriginVerified": true,
            "fixturePixelOrigin": ["x": Int(crop.minX), "y": Int(crop.minY)],
        ]
    }
}
