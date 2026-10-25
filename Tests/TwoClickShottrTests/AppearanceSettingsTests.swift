import AppKit
import Testing

@testable import TwoClickShottr

@Suite(.serialized)
@MainActor
struct AppearanceSettingsTests {
    private func descendants(of view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }

    @Test func nativeSettingsControlsApplyChangesAndKeepPreviewInsideWindow() throws {
        let app = NSApplication.shared
        var changes: [CapturePreferences] = []
        var shortcutRequested = false
        var permissionRequested = false
        let controller = AppearanceSettingsController(
            preferences: CapturePreferences(), onChange: { changes.append($0) },
            changeShortcut: { shortcutRequested = true }, permissionHelp: { permissionRequested = true })
        let window = try #require(controller.window)
        defer { window.close() }
        let content = try #require(window.contentView)
        content.layoutSubtreeIfNeeded()
        let views = descendants(of: content)
        let sliders = views.compactMap { $0 as? NSSlider }
        #expect(sliders.count == 3)
        for slider in sliders {
            let title = slider.accessibilityLabel()
            slider.doubleValue = title == "Crosshair size" ? 64 : title == "Line thickness" ? 4 : 24
            #expect(app.sendAction(try #require(slider.action), to: slider.target, from: slider))
        }
        let position = try #require(views.compactMap { $0 as? NSPopUpButton }.first)
        position.selectItem(withTitle: "Lower left")
        #expect(app.sendAction(try #require(position.action), to: position.target, from: position))
        let checkbox = try #require(
            views.compactMap { $0 as? NSButton }.first { $0.title == "Show in menu bar" })
        checkbox.performClick(nil)
        let changed = try #require(changes.last)
        #expect(changed.crosshairSize == 64 && changed.lineWidth == 4 && changed.coordinateFontSize == 24)
        #expect(changed.coordinatePosition == .lowerLeft && !changed.showInMenuBar)
        checkbox.performClick(nil)
        #expect(changes.last?.showInMenuBar == true)
        for button in views.compactMap({ $0 as? NSButton }) {
            if button.title == "Change shortcut…" || button.title == "Screen Recording…" {
                button.performClick(nil)
            }
        }
        #expect(shortcutRequested && permissionRequested)
        controller.updateStatus("Screen Recording access is required.")
        content.layoutSubtreeIfNeeded()
        for control in views where control is NSControl {
            let rect = content.convert(control.bounds, from: control)
            #expect(content.bounds.insetBy(dx: -1, dy: -1).contains(rect))
        }

    }
    @Test func reopeningHiddenAppOffersSettingsAndPersistsIconRecovery() throws {
        let name = "TwoClickShottrTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(false, forKey: "showInMenuBar")
        let app = NSApplication.shared
        let previousApp = NSWorkspace.shared.frontmostApplication
        let previousWindows = Set(app.windows.map(ObjectIdentifier.init))
        let delegate = AppDelegate(defaults: defaults)
        #expect(!delegate.applicationShouldHandleReopen(app, hasVisibleWindows: false))
        let window = try #require(app.windows.first { !previousWindows.contains(ObjectIdentifier($0)) })
        defer {
            window.close()
            previousApp?.activate(options: [])
        }
        #expect(window.isVisible)
        let controls = descendants(of: try #require(window.contentView))
        let checkbox = try #require(
            controls.compactMap { $0 as? NSButton }.first { $0.title == "Show in menu bar" })
        #expect(checkbox.state == .off)
        checkbox.performClick(nil)
        #expect(defaults.bool(forKey: "showInMenuBar"))
    }

}
