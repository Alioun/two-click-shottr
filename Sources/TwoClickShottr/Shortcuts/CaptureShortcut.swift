import AppKit
import Carbon

struct CaptureShortcut: Codable, Equatable {
    let keyCode: UInt32
    let modifiers: UInt32
    let menuEquivalent: String

    static let defaultShortcut = CaptureShortcut(
        keyCode: UInt32(kVK_ANSI_4), modifiers: UInt32(shiftKey | cmdKey), menuEquivalent: "4")
    private static let requiredModifiers = UInt32(cmdKey | controlKey | optionKey)
    private static let allowedModifiers = requiredModifiers | UInt32(shiftKey)
    private static let modifierKeyCodes: Set<UInt32> = [
        UInt32(kVK_Command), UInt32(kVK_RightCommand), UInt32(kVK_Shift), UInt32(kVK_RightShift),
        UInt32(kVK_Option), UInt32(kVK_RightOption), UInt32(kVK_Control), UInt32(kVK_RightControl),
        UInt32(kVK_CapsLock), UInt32(kVK_Function),
    ]

    var isValid: Bool {
        keyCode <= 127 && !Self.modifierKeyCodes.contains(keyCode)
            && modifiers & Self.requiredModifiers != 0 && modifiers & ~Self.allowedModifiers == 0
            && menuEquivalent.count == 1
    }

    private static let modifierMapping: [(carbon: UInt32, appKit: NSEvent.ModifierFlags, symbol: String)] = [
        (UInt32(controlKey), .control, "⌃"), (UInt32(optionKey), .option, "⌥"),
        (UInt32(shiftKey), .shift, "⇧"), (UInt32(cmdKey), .command, "⌘"),
    ]

    var menuModifiers: NSEvent.ModifierFlags {
        Self.modifierMapping.reduce(into: []) { flags, modifier in
            if modifiers & modifier.carbon != 0 { flags.insert(modifier.appKit) }
        }
    }

    var displayText: String {
        let prefix = Self.modifierMapping.filter { modifiers & $0.carbon != 0 }.map(\.symbol).joined()
        let key: String
        switch Int(keyCode) {
        case kVK_Return, kVK_ANSI_KeypadEnter: key = "↩"
        case kVK_Escape: key = "⎋"
        case kVK_Space: key = "Space"
        case kVK_Tab: key = "⇥"
        case kVK_Delete: key = "⌫"
        case kVK_ForwardDelete: key = "⌦"
        case kVK_LeftArrow: key = "←"
        case kVK_RightArrow: key = "→"
        case kVK_UpArrow: key = "↑"
        case kVK_DownArrow: key = "↓"
        case kVK_Home: key = "↖"
        case kVK_End: key = "↘"
        case kVK_PageUp: key = "⇞"
        case kVK_PageDown: key = "⇟"
        default:
            if let scalar = menuEquivalent.unicodeScalars.first,
                (NSF1FunctionKey...NSF35FunctionKey).contains(Int(scalar.value))
            {
                key = "F\(Int(scalar.value) - NSF1FunctionKey + 1)"
            } else {
                key = menuEquivalent.uppercased()
            }
        }
        return prefix + key
    }

    init(keyCode: UInt32, modifiers: UInt32, menuEquivalent: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.menuEquivalent = menuEquivalent
    }

    init?(event: NSEvent) {
        guard event.type == .keyDown, !event.isARepeat,
            let equivalent = event.characters(byApplyingModifiers: []) ?? event.charactersIgnoringModifiers
        else { return nil }
        let modifiers = Self.modifierMapping.reduce(UInt32(0)) { value, modifier in
            event.modifierFlags.contains(modifier.appKit) ? value | modifier.carbon : value
        }
        self.init(keyCode: UInt32(event.keyCode), modifiers: modifiers, menuEquivalent: equivalent)
        guard isValid else { return nil }
    }

    static let defaultsKey = "captureShortcut"

    static func load(from defaults: UserDefaults) -> CaptureShortcut {
        guard let data = defaults.data(forKey: defaultsKey),
            let shortcut = try? JSONDecoder().decode(Self.self, from: data), shortcut.isValid
        else { return .defaultShortcut }
        return shortcut
    }

    func persist(in defaults: UserDefaults) {
        defaults.set(try! JSONEncoder().encode(self), forKey: Self.defaultsKey)
    }
}

@MainActor
final class CaptureShortcutController {
    private enum State { case active, recording }
    private var state = State.active
    private let defaults: UserDefaults
    private let register: (CaptureShortcut) -> OSStatus
    private let unregister: () -> Void
    private(set) var selected: CaptureShortcut
    private(set) var registrationError: String?

    init(
        defaults: UserDefaults, register: @escaping (CaptureShortcut) -> OSStatus,
        unregister: @escaping () -> Void
    ) {
        self.defaults = defaults
        self.register = register
        self.unregister = unregister
        selected = CaptureShortcut.load(from: defaults)
    }

    func activate() {
        registrationError = failure(for: selected, status: register(selected))
    }

    func beginRecording() {
        guard case .active = state else { return }
        state = .recording
        unregister()
    }

    func finishRecording(with proposed: CaptureShortcut?) -> String? {
        guard case .recording = state else { return nil }
        state = .active
        guard let proposed else {
            activate()
            return registrationError
        }
        guard proposed.isValid else {
            activate()
            return
                "Choose a key with Command, Control, or Option. The saved shortcut is still \(selected.displayText)."
        }
        let status = register(proposed)
        guard status == noErr else {
            let message = failure(for: proposed, status: status)!
            activate()
            if let registrationError { return "\(message)\n\(registrationError)" }
            return "\(message)\nThe previous shortcut \(selected.displayText) has been restored."
        }
        proposed.persist(in: defaults)
        selected = proposed
        registrationError = nil
        return nil
    }

    private func failure(for shortcut: CaptureShortcut, status: OSStatus) -> String? {
        guard status != noErr else { return nil }
        return
            "\(shortcut.displayText) could not be registered, status \(status). Release this shortcut in Shottr, System Settings > Keyboard > Keyboard Shortcuts, or another app, then try again. You can also choose Change shortcut… to use a different combination. Capture remains available in the menu."
    }
}

@MainActor
enum CaptureShortcutRecorder {
    static func record(_ current: CaptureShortcut) -> CaptureShortcut? {
        let alert = NSAlert()
        alert.messageText = "Change capture shortcut"
        alert.informativeText =
            "Press a key with Command, Control, or Option. Shift is optional. Press Return to save or Escape to cancel."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        let display = NSTextField(labelWithString: current.displayText)
        display.font = .monospacedSystemFont(ofSize: 22, weight: .medium)
        display.alignment = .center
        display.frame = NSRect(x: 0, y: 0, width: 340, height: 40)
        display.setAccessibilityLabel("Chosen capture shortcut")
        alert.accessoryView = display
        var chosen = current
        let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard NSApp.modalWindow === alert.window else { return event }
            let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
            if modifiers.isEmpty && event.keyCode == UInt16(kVK_Escape) {
                alert.buttons[1].performClick(nil)
            } else if modifiers.isEmpty
                && [UInt16(kVK_Return), UInt16(kVK_ANSI_KeypadEnter)].contains(event.keyCode)
            {
                alert.buttons[0].performClick(nil)
            } else if let shortcut = CaptureShortcut(event: event) {
                chosen = shortcut
                display.stringValue = shortcut.displayText
            }
            return nil
        }
        defer {
            if let monitor { NSEvent.removeMonitor(monitor) }
            alert.window.orderOut(nil)
        }
        activateCompanion()
        return alert.runModal() == .alertFirstButtonReturn ? chosen : nil
    }
}
