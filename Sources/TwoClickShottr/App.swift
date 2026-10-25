import AppKit
import Carbon
import OSLog

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private enum Activity {
        case idle
        case selecting
        case capturing
        case recordingShortcut
        case checkingPermission
        case presentingError
    }

    private let launchMode = LaunchMode()
    private var activity = Activity.idle
    private var statusItem: NSStatusItem?
    private var modeItems: [NSMenuItem] = []
    private var captureItem: NSMenuItem?
    private var shortcutStatusItem: NSMenuItem?
    private lazy var globalHotKey = GlobalHotKey { [weak self] in self?.beginCapture() }
    private var captureTask: Task<Void, Never>?
    private var captureRunner: ProcessRunner?
    private let screenCaptureAccess = ScreenCaptureAccess()
    private var permissionTask: Task<Void, Never>?
    private var permissionItem: NSMenuItem?
    private var captureStatusItem: NSMenuItem?
    private lazy var selectionController = SelectionController(mode: mode, reuseWindows: true) {
        [weak self] rect in
        self?.finishSelection(rect)
    }
    private var isShuttingDown = false
    private let defaults = UserDefaults.standard
    private lazy var shortcutController = CaptureShortcutController(
        defaults: defaults,
        register: { [weak self] shortcut in
            self?.globalHotKey.register(shortcut) ?? OSStatus(eventNotHandledErr)
        }, unregister: { [weak self] in self?.globalHotKey.unregister() })
    private var mode: SelectionMode {
        get { SelectionMode(rawValue: defaults.string(forKey: "selectionMode") ?? "") ?? .twoClick }
        set { defaults.set(newValue.rawValue, forKey: "selectionMode") }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        switch launchMode {
        case .exclusiveHotKey:
            captureTask = Task { await ExclusiveHotKeyVerification.run() }
            return
        case .hotKeyConflictChild:
            ExclusiveHotKeyVerification.contend(expected: OSStatus(eventHotKeyExistsErr))
        case .hotKeyFreeChild: ExclusiveHotKeyVerification.contend(expected: noErr)
        case .diagnose: Verification.diagnose()
        case .selection: Verification.selection()
        case .cursor:
            captureTask = Task { await Verification.cursor() }
            return
        case .capture:
            captureTask = Task { await Verification.capture() }
            return
        case .triggerLatency, .resourceProfile, .application: break
        }
        configureMenu()
        selectionController.prepare()
        if launchMode == .triggerLatency {
            globalHotKey.install()
            captureTask = Task {
                await Verification.triggerLatency(
                    selection: selectionController,
                    trigger: {
                        self.screenCaptureAccess.record(true)
                        return GlobalHotKey.deliverPress()
                    },
                    isSelecting: {
                        if case .selecting = self.activity { return true }
                        return false
                    })
            }
            return
        }
        if launchMode == .resourceProfile {
            captureTask = Task { await ResourceProfile.run(selection: selectionController) }
            return
        }
        refreshPermission()
        globalHotKey.install()
        shortcutController.activate()
        updateShortcutItems()
    }

    private func configureMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(
            systemSymbolName: "viewfinder", accessibilityDescription: "Two Click Shottr")
        item.button?.toolTip = "Two Click Shottr"
        let menu = NSMenu()
        let capture = NSMenuItem(title: "Capture", action: #selector(beginCapture), keyEquivalent: "")
        captureItem = capture
        capture.target = self
        menu.addItem(capture)
        let changeShortcut = NSMenuItem(
            title: "Change shortcut…", action: #selector(changeShortcut), keyEquivalent: "")
        changeShortcut.target = self
        menu.addItem(changeShortcut)
        let shortcutStatus = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        shortcutStatus.isEnabled = false
        menu.addItem(shortcutStatus)
        shortcutStatusItem = shortcutStatus
        let modes = NSMenu()
        for mode in SelectionMode.allCases {
            let choice = NSMenuItem(title: mode.title, action: #selector(changeMode(_:)), keyEquivalent: "")
            choice.target = self
            choice.representedObject = mode.rawValue
            modeItems.append(choice)
            modes.addItem(choice)
        }
        let modeMenu = NSMenuItem(title: "Selection mode", action: nil, keyEquivalent: "")
        modeMenu.submenu = modes
        menu.addItem(modeMenu)
        let captureStatus = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        captureStatus.isEnabled = false
        captureStatus.isHidden = true
        captureStatusItem = captureStatus
        menu.addItem(captureStatus)
        menu.addItem(.separator())
        let help = NSMenuItem(
            title: "Screen recording permission…", action: #selector(permissionHelp), keyEquivalent: "")
        help.target = self
        permissionItem = help
        menu.addItem(help)
        let quit = NSMenuItem(
            title: "Quit Two Click Shottr", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"
        )
        menu.addItem(quit)
        item.menu = menu
        statusItem = item
        updateModeItems()
    }

    private func updateShortcutItems() {
        let shortcut = shortcutController.selected
        captureItem?.keyEquivalent = shortcut.menuEquivalent
        captureItem?.keyEquivalentModifierMask = shortcut.menuModifiers
        shortcutStatusItem?.title = "Shortcut unavailable (\(shortcut.displayText))"
        shortcutStatusItem?.toolTip = shortcutController.registrationError
        shortcutStatusItem?.isHidden = shortcutController.registrationError == nil
    }

    @objc private func changeShortcut() {
        guard case .idle = activity else { return }
        activity = .recordingShortcut
        shortcutController.beginRecording()
        let proposed = CaptureShortcutRecorder.record(shortcutController.selected)
        let error = shortcutController.finishRecording(with: proposed)
        activity = .idle
        updateShortcutItems()
        if let error { showError(error) }
    }

    @objc private func changeMode(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String, let mode = SelectionMode(rawValue: rawValue)
        else { return }
        self.mode = mode
        updateModeItems()
    }

    private func updateModeItems() {
        for item in modeItems {
            item.state = (item.representedObject as? String) == mode.rawValue ? .on : .off
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        refreshPermission()
    }

    private func refreshPermission() {
        guard permissionTask == nil else { return }
        permissionTask = Task {
            _ = await screenCaptureAccess.refresh()
            updatePermissionItem()
            permissionTask = nil
        }
    }

    private func updatePermissionItem() {
        permissionItem?.toolTip =
            "System Settings > Privacy & Security > Screen Recording. Allow Two Click Shottr, then reopen it if macOS asks."
        permissionItem?.title =
            screenCaptureAccess.cached == false
            ? "Screen recording permission required…" : "Screen recording permission…"
    }

    @objc private func beginCapture() {
        if launchMode == .resourceProfile { return }
        if launchMode == .triggerLatency, screenCaptureAccess.cached != true { return }
        guard case .idle = activity, NSApp.modalWindow == nil else { return }
        captureStatusItem?.isHidden = true
        switch screenCaptureAccess.cached {
        case true?: startSelection()
        case false?: requestPermission()
        case nil:
            activity = .checkingPermission
            captureTask = Task {
                let allowed = await screenCaptureAccess.refresh()
                captureTask = nil
                activity = .idle
                guard !Task.isCancelled, !isShuttingDown else { return }
                updatePermissionItem()
                if allowed { startSelection() } else { requestPermission() }
            }
        }
    }

    private func requestPermission() {
        activity = .checkingPermission
        let allowed = CGRequestScreenCaptureAccess()
        screenCaptureAccess.record(allowed)
        activity = .idle
        guard !isShuttingDown else { return }
        updatePermissionItem()
        if allowed { startSelection() }
    }

    private func startSelection() {
        guard !NSScreen.screens.isEmpty else {
            showError("No display is available.")
            return
        }
        activity = .selecting
        selectionController.start(mode: mode)
    }

    private func finishSelection(_ rect: CGRect?) {
        if launchMode.preventsCapture {
            activity = .idle
            return
        }
        guard let rect else {
            activity = .idle
            return
        }
        if screenCaptureAccess.cached == false {
            activity = .idle
            requestPermission()
            return
        }
        activity = .capturing
        let runner: ProcessRunner?
        if #available(macOS 14.0, *) { runner = nil } else { runner = ProcessRunner() }
        captureRunner = runner
        let quartzRect = CaptureGeometry.quartzRect(rect, primaryTop: selectionController.primaryTop)
        let displays = selectionController.displayBounds
        captureTask = Task {
            defer {
                activity = .idle
                captureTask = nil
                captureRunner = nil
            }
            do {
                guard await screenCaptureAccess.refresh() else {
                    updatePermissionItem()
                    return
                }
                try Task.checkCancellation()
                let file = try await CaptureService.capture(
                    quartzRect, runner: runner, expectedDisplays: displays)
                try Task.checkCancellation()
                try await CaptureService.openInShottr(file)
            } catch is CancellationError {
            } catch let failure as CaptureFailure where failure.kind == .screenRecordingDenied {
                screenCaptureAccess.record(false)
                updatePermissionItem()
            } catch let failure as CaptureFailure where failure.isCaptureFailure {
                guard !Task.isCancelled, !isShuttingDown else { return }
                _ = await screenCaptureAccess.refresh()
                updatePermissionItem()
                captureStatusItem?.title = "Capture failed. Try again."
                captureStatusItem?.toolTip = failure.localizedDescription
                captureStatusItem?.isHidden = false
                Logger(subsystem: AppIdentity.bundleIdentifier, category: "capture")
                    .error("\(failure.localizedDescription, privacy: .public)")
            } catch {
                if !Task.isCancelled && !isShuttingDown { showError(error.localizedDescription) }
            }
        }
    }

    @objc private func permissionHelp() {
        guard case .idle = activity else { return }
        guard
            let settings = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: "com.apple.systempreferences")
        else {
            showError(
                "Open System Settings > Privacy & Security > Screen Recording and allow Two Click Shottr.")
            return
        }
        NSWorkspace.shared.openApplication(at: settings, configuration: NSWorkspace.OpenConfiguration()) {
            _, _ in
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        isShuttingDown = true
        captureTask?.cancel()
        permissionTask?.cancel()
        guard let runner = captureRunner else { return .terminateNow }
        DispatchQueue.global(qos: .userInitiated).async {
            runner.cancelAndWait()
            DispatchQueue.main.async { sender.reply(toApplicationShouldTerminate: true) }
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        isShuttingDown = true
        captureTask?.cancel()
        permissionTask?.cancel()
        captureRunner?.cancel()
        if case .selecting = activity { selectionController.hide() }
        selectionController.discardPreparedWindows()
        globalHotKey.invalidate()
    }

    private func showError(_ message: String) {
        guard NSApp.modalWindow == nil else { return }
        let previousActivity = activity
        activity = .presentingError
        defer { activity = previousActivity }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Two Click Shottr"
        alert.informativeText = message
        activateCompanion()
        alert.runModal()
    }
}

@main
struct TwoClickShottrApp {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
