import AppKit

@MainActor
extension Verification {
    static func triggerLatency(
        selection: SelectionController, trigger: () -> OSStatus,
        isSelecting: () -> Bool
    ) async -> Never {
        let previousApp = NSWorkspace.shared.frontmostApplication
        try? await Task.sleep(nanoseconds: 300_000_000)
        let initialPointer = NSEvent.mouseLocation
        let started = ProcessInfo.processInfo.systemUptime
        let delivery = trigger()
        let returned = ProcessInfo.processInfo.systemUptime
        let probe = await CursorProbe.waitForCrosshair()
        let observed = ProcessInfo.processInfo.systemUptime
        let unchangedPointer = NSEvent.mouseLocation == initialPointer
        let matches = probe.matchesCrosshair
        let selecting = isSelecting()
        let passed = delivery == noErr && selecting && NSApp.isActive && matches && unchangedPointer
        selection.receive(.cancel)
        selection.discardPreparedWindows()
        previousApp?.activate(options: [])
        Verification.finish(
            [
                "verification": "trigger-latency", "passed": passed,
                "hotkeyHandlerMilliseconds": (returned - started) * 1000,
                "crosshairMilliseconds": (observed - started) * 1000,
                "systemCursorMatchesCrosshair": matches, "systemCursorProbeAvailable": probe.cursor != nil,
                "pointerUnchanged": unchangedPointer,
                "deliveryStatus": delivery,
                "injection":
                    "App-local Carbon event through the production hotkey handler with a test-only cached permission. Image capture is disabled. No global keyboard input or permission request.",
            ], success: passed)
    }

}
