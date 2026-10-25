import AppKit
import Carbon
import Testing

@testable import TwoClickShottr

@MainActor
struct CaptureShortcutTests {
    private func withDefaults(_ body: (UserDefaults) throws -> Void) rethrows {
        let name = "local.two-click-shottr.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        try body(defaults)
    }

    private let alternative = CaptureShortcut(
        keyCode: UInt32(kVK_ANSI_K), modifiers: UInt32(controlKey | optionKey), menuEquivalent: "k")

    @Test func absentSelectionDefaultsToShiftCommand4() {
        withDefaults { defaults in
            let shortcut = CaptureShortcut.load(from: defaults)
            #expect(shortcut.keyCode == UInt32(kVK_ANSI_4))
            #expect(shortcut.modifiers == UInt32(shiftKey | cmdKey))
            #expect(shortcut.menuEquivalent == "4")
            #expect(shortcut.menuModifiers == [.shift, .command])
            #expect(shortcut.displayText == "⇧⌘4")
            #expect(defaults.object(forKey: CaptureShortcut.defaultsKey) == nil)
        }
    }

    @Test func savedSelectionRoundTripsPhysicalKeyAndMenuEquivalent() {
        withDefaults { defaults in
            alternative.persist(in: defaults)
            let restored = CaptureShortcut.load(from: defaults)
            #expect(restored == alternative)
            #expect(restored.displayText == "⌃⌥K")
            #expect(restored.menuModifiers == [.control, .option])
        }
    }

    @Test func invalidOrDamagedSavedSelectionFallsBackWithoutOverwriting() {
        withDefaults { defaults in
            let invalid = CaptureShortcut(
                keyCode: UInt32(kVK_Shift), modifiers: UInt32(cmdKey), menuEquivalent: "x")
            invalid.persist(in: defaults)
            let original = defaults.data(forKey: CaptureShortcut.defaultsKey)
            #expect(CaptureShortcut.load(from: defaults) == .defaultShortcut)
            #expect(defaults.data(forKey: CaptureShortcut.defaultsKey) == original)
            defaults.set(Data("invalid JSON".utf8), forKey: CaptureShortcut.defaultsKey)
            #expect(CaptureShortcut.load(from: defaults) == .defaultShortcut)
        }
    }

    @Test func saveRegistersBeforePersistingAndSurvivesNewController() {
        withDefaults { defaults in
            var active: CaptureShortcut?
            let controller = CaptureShortcutController(
                defaults: defaults,
                register: { shortcut in
                    #expect(active == nil)
                    #expect(CaptureShortcut.load(from: defaults) == .defaultShortcut)
                    active = shortcut
                    return noErr
                }, unregister: { active = nil })
            controller.activate()
            #expect(active == .defaultShortcut)
            controller.beginRecording()
            #expect(active == nil)
            #expect(controller.finishRecording(with: alternative) == nil)
            #expect(active == alternative)
            let reopened = CaptureShortcutController(
                defaults: defaults, register: { _ in noErr }, unregister: {})
            #expect(reopened.selected == alternative)
            #expect(controller.selected == alternative)
        }
    }

    @Test func cancelRestoresPreviousRegistrationAndSavedSelection() {
        withDefaults { defaults in
            alternative.persist(in: defaults)
            let saved = defaults.data(forKey: CaptureShortcut.defaultsKey)
            var active: CaptureShortcut?
            let controller = CaptureShortcutController(
                defaults: defaults,
                register: {
                    active = $0
                    return noErr
                },
                unregister: { active = nil })
            controller.activate()
            controller.beginRecording()
            #expect(active == nil)
            #expect(controller.finishRecording(with: nil) == nil)
            #expect(active == alternative)
            #expect(controller.selected == alternative)
            #expect(defaults.data(forKey: CaptureShortcut.defaultsKey) == saved)
        }
    }

    @Test func conflictRestoresOldBindingAndNeverOverwritesSavedSelection() {
        withDefaults { defaults in
            alternative.persist(in: defaults)
            let saved = defaults.data(forKey: CaptureShortcut.defaultsKey)
            let proposed = CaptureShortcut.defaultShortcut
            var active: CaptureShortcut?
            let controller = CaptureShortcutController(
                defaults: defaults,
                register: { shortcut in
                    #expect(active == nil)
                    #expect(CaptureShortcut.load(from: defaults) == alternative)
                    guard shortcut != proposed else { return OSStatus(eventHotKeyExistsErr) }
                    active = shortcut
                    return noErr
                }, unregister: { active = nil })
            controller.activate()
            controller.beginRecording()
            let error = controller.finishRecording(with: proposed)
            #expect(error?.contains("⇧⌘4") == true)
            #expect(error?.contains("restored") == true)
            #expect(active == alternative)
            #expect(controller.selected == alternative)
            #expect(controller.registrationError == nil)
            #expect(defaults.data(forKey: CaptureShortcut.defaultsKey) == saved)
        }
    }

    @Test func startupConflictCanBeReassignedWithoutSavingFailedDefault() {
        withDefaults { defaults in
            var active: CaptureShortcut?
            let controller = CaptureShortcutController(
                defaults: defaults,
                register: { shortcut in
                    guard shortcut != .defaultShortcut else { return OSStatus(eventHotKeyExistsErr) }
                    active = shortcut
                    return noErr
                }, unregister: { active = nil })
            controller.activate()
            #expect(controller.registrationError?.contains("⇧⌘4") == true)
            #expect(defaults.object(forKey: CaptureShortcut.defaultsKey) == nil)
            controller.beginRecording()
            #expect(controller.finishRecording(with: alternative) == nil)
            #expect(active == alternative)
            #expect(controller.registrationError == nil)
            #expect(CaptureShortcut.load(from: defaults) == alternative)
        }
    }

    @Test func failedRestorationReportsUnavailableOldBindingWithoutChangingSavedSelection() {
        withDefaults { defaults in
            alternative.persist(in: defaults)
            var conflict = false
            let controller = CaptureShortcutController(
                defaults: defaults,
                register: { _ in
                    conflict ? OSStatus(eventHotKeyExistsErr) : noErr
                }, unregister: {})
            controller.activate()
            controller.beginRecording()
            conflict = true
            let error = controller.finishRecording(with: .defaultShortcut)
            #expect(error?.contains("⇧⌘4") == true)
            #expect(error?.contains("⌃⌥K") == true)
            #expect(controller.registrationError != nil)
            #expect(CaptureShortcut.load(from: defaults) == alternative)
        }
    }

    @Test func closingRecordingTwiceDoesNotRegisterOrSaveAgain() {
        withDefaults { defaults in
            var registrations = 0
            let controller = CaptureShortcutController(
                defaults: defaults,
                register: { _ in
                    registrations += 1
                    return noErr
                }, unregister: {})
            controller.activate()
            controller.beginRecording()
            #expect(controller.finishRecording(with: nil) == nil)
            #expect(controller.finishRecording(with: alternative) == nil)
            #expect(registrations == 2)
            #expect(CaptureShortcut.load(from: defaults) == .defaultShortcut)
            #expect(defaults.object(forKey: CaptureShortcut.defaultsKey) == nil)
        }
    }

    private func event(
        keyCode: Int, modifiers: NSEvent.ModifierFlags, characters: String, repeatKey: Bool = false
    ) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: 0,
            context: nil, characters: characters, charactersIgnoringModifiers: characters,
            isARepeat: repeatKey, keyCode: UInt16(keyCode))!
    }

    @Test func recorderUsesUnmodifiedCharacterAndPhysicalKeyCode() {
        let shifted = event(keyCode: kVK_ANSI_4, modifiers: [.command, .shift], characters: "$")
        let shortcut = CaptureShortcut(event: shifted)
        #expect(shortcut?.keyCode == UInt32(kVK_ANSI_4))
        #expect(shortcut?.modifiers == UInt32(cmdKey | shiftKey))
        #expect(shortcut?.menuEquivalent == "4")
        #expect(shortcut?.displayText == "⇧⌘4")
    }

    @Test func recorderAcceptsCommandControlOptionButIgnoresBareKeysAndRepeats() {
        for flags: NSEvent.ModifierFlags in [.command, .control, .option, [.control, .option, .shift]] {
            #expect(
                CaptureShortcut(event: event(keyCode: kVK_ANSI_K, modifiers: flags, characters: "k")) != nil)
        }
        for flags: NSEvent.ModifierFlags in [[], .shift, .capsLock] {
            #expect(
                CaptureShortcut(event: event(keyCode: kVK_ANSI_K, modifiers: flags, characters: "k")) == nil)
        }
        #expect(
            CaptureShortcut(
                event: event(keyCode: kVK_ANSI_K, modifiers: .command, characters: "k", repeatKey: true))
                == nil)
        #expect(CaptureShortcut(event: event(keyCode: kVK_Shift, modifiers: .command, characters: "")) == nil)
    }

    @Test func recorderRequiresModifiersForReturnAndEscape() {
        for (key, character, display) in [(kVK_Return, "\r", "⌘↩"), (kVK_Escape, "\u{1b}", "⌘⎋")] {
            #expect(CaptureShortcut(event: event(keyCode: key, modifiers: [], characters: character)) == nil)
            let modified = CaptureShortcut(
                event: event(keyCode: key, modifiers: .command, characters: character))
            #expect(modified?.displayText == display)
        }
    }
}
