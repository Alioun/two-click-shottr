import AppKit
import Carbon

@MainActor
enum ExclusiveHotKeyVerification {
    private static let shortcut = CaptureShortcut(
        keyCode: UInt32(kVK_F19),
        modifiers: UInt32(controlKey | optionKey | shiftKey | cmdKey), menuEquivalent: "\u{F716}")

    static func contend(expected: OSStatus) -> Never {
        var reference: EventHotKeyRef?
        let status = GlobalHotKey.register(shortcut, reference: &reference)
        if let reference { UnregisterEventHotKey(reference) }
        Verification.finish(
            [
                "verification": "exclusive-hotkey-child", "status": status, "expected": expected,
                "passed": status == expected,
            ], success: status == expected)
    }

    static func run() async -> Never {
        var reference: EventHotKeyRef?
        let status = GlobalHotKey.register(shortcut, reference: &reference)
        guard status == noErr, let held = reference else {
            Verification.finish(
                [
                    "verification": "exclusive-hotkey", "passed": false, "status": status,
                    "error": "Could not reserve the obscure test shortcut. No user shortcut was changed.",
                ], success: false)
        }
        var released = false
        do {
            guard let executable = Bundle.main.executableURL else {
                throw CaptureFailure(message: "The verification executable could not be located.")
            }
            let conflict = try await ProcessRunner().run(
                executable: executable,
                arguments: ["--verify-hotkey-conflict-child"], timeout: 10)
            let releaseStatus = UnregisterEventHotKey(held)
            released = true
            let free = try await ProcessRunner().run(
                executable: executable,
                arguments: ["--verify-hotkey-free-child"], timeout: 10)
            let passed =
                conflict.reason == .exit && conflict.status == 0 && releaseStatus == noErr
                && free.reason == .exit && free.status == 0
            Verification.finish(
                [
                    "verification": "exclusive-hotkey", "passed": passed,
                    "shortcut": "Control+Option+Shift+Command+F19",
                    "conflictChildExitStatus": conflict.status,
                    "releaseStatus": releaseStatus, "freeChildExitStatus": free.status,
                    "injection":
                        "Two real processes register the production exclusive hotkey. No keyboard input is synthesized.",
                ], success: passed)
        } catch {
            if !released { UnregisterEventHotKey(held) }
            Verification.finish(
                [
                    "verification": "exclusive-hotkey", "passed": false,
                    "error": error.localizedDescription,
                ], success: false)
        }
    }
}
