import AppKit

@MainActor
final class AppearanceSettingsController: NSWindowController {
    private(set) var preferences: CapturePreferences
    private let onChange: (CapturePreferences) -> Void
    private let changeShortcut: () -> Void
    private let permissionHelp: () -> Void
    private let size = NSSlider()
    private let width = NSSlider()
    private let font = NSSlider()
    private let position = NSPopUpButton()
    private let menuBar = NSButton(checkboxWithTitle: "Show in menu bar", target: nil, action: nil)
    private let sizeValue = NSTextField(labelWithString: "")
    private let widthValue = NSTextField(labelWithString: "")
    private let fontValue = NSTextField(labelWithString: "")
    private let status = NSTextField(wrappingLabelWithString: "")
    private let preview = NSBox()
    private let previewCursor = NSImageView()
    private let previewCoordinates = NSTextField(labelWithString: "123\n456")

    init(
        preferences: CapturePreferences, onChange: @escaping (CapturePreferences) -> Void,
        changeShortcut: @escaping () -> Void, permissionHelp: @escaping () -> Void
    ) {
        self.preferences = preferences
        self.onChange = onChange
        self.changeShortcut = changeShortcut
        self.permissionHelp = permissionHelp
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 460, height: 540),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Two Click Shottr Settings"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        if !window.setFrameUsingName("AppearanceSettings") { window.center() }
        window.setFrameAutosaveName("AppearanceSettings")
        configureControls()
    }

    required init?(coder: NSCoder) { nil }

    private func configureControls() {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        window!.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: window!.contentView!.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: window!.contentView!.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: window!.contentView!.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(equalTo: window!.contentView!.bottomAnchor, constant: -24),
        ])
        func sliderRow(
            _ title: String, slider: NSSlider, value: NSTextField,
            range: ClosedRange<Double>
        ) -> [NSView] {
            slider.minValue = range.lowerBound
            slider.maxValue = range.upperBound
            slider.isContinuous = true
            slider.target = self
            slider.action = #selector(controlsChanged)
            slider.setAccessibilityLabel(title)
            slider.widthAnchor.constraint(equalToConstant: 150).isActive = true
            value.widthAnchor.constraint(equalToConstant: 50).isActive = true
            return [NSTextField(labelWithString: title), slider, value]
        }
        position.addItems(withTitles: CapturePreferences.CoordinatePosition.allCases.map(\.title))
        position.target = self
        position.action = #selector(controlsChanged)
        position.setAccessibilityLabel("Coordinate position")
        let grid = NSGridView(views: [
            sliderRow(
                "Crosshair size", slider: size, value: sizeValue, range: CapturePreferences.crosshairSizeRange
            ),
            sliderRow(
                "Line thickness", slider: width, value: widthValue, range: CapturePreferences.lineWidthRange),
            sliderRow(
                "Coordinate size", slider: font, value: fontValue, range: CapturePreferences.fontSizeRange),
            [NSTextField(labelWithString: "Coordinate position"), position, NSGridCell.emptyContentView],
        ])
        grid.rowSpacing = 12
        grid.columnSpacing = 10
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).xPlacement = .fill
        grid.column(at: 2).xPlacement = .leading
        stack.addArrangedSubview(grid)
        preview.boxType = .custom
        preview.borderWidth = 0
        preview.fillColor = .darkGray
        preview.cornerRadius = 6
        preview.contentViewMargins = .zero
        preview.widthAnchor.constraint(equalToConstant: 400).isActive = true
        preview.heightAnchor.constraint(equalToConstant: 160).isActive = true
        previewCursor.imageScaling = .scaleNone
        preview.contentView!.addSubview(previewCursor)
        previewCoordinates.textColor = .white
        previewCoordinates.isSelectable = false
        preview.contentView!.addSubview(previewCoordinates)
        stack.addArrangedSubview(preview)
        menuBar.target = self
        menuBar.action = #selector(controlsChanged)
        stack.addArrangedSubview(menuBar)
        let recovery = NSTextField(
            wrappingLabelWithString:
                "When the icon is hidden, reopen the app from Finder or Spotlight to change Settings. The capture shortcut still works."
        )
        recovery.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        recovery.textColor = .secondaryLabelColor
        recovery.widthAnchor.constraint(equalToConstant: 400).isActive = true
        stack.addArrangedSubview(recovery)
        status.textColor = .secondaryLabelColor
        status.maximumNumberOfLines = 2
        status.lineBreakMode = .byTruncatingTail
        status.widthAnchor.constraint(equalToConstant: 400).isActive = true
        stack.addArrangedSubview(status)
        let shortcut = NSButton(title: "Change shortcut…", target: self, action: #selector(recordShortcut))
        let permission = NSButton(title: "Screen Recording…", target: self, action: #selector(openPermission))
        let quit = NSButton(title: "Quit", target: NSApp, action: #selector(NSApplication.terminate(_:)))
        let actions = NSStackView(views: [shortcut, permission, quit])
        actions.spacing = 10
        stack.addArrangedSubview(actions)
        size.doubleValue = preferences.crosshairSize
        width.doubleValue = preferences.lineWidth
        font.doubleValue = preferences.coordinateFontSize
        position.selectItem(
            at: CapturePreferences.CoordinatePosition.allCases.firstIndex(of: preferences.coordinatePosition)!
        )
        menuBar.state = preferences.showInMenuBar ? .on : .off
        updatePreview()
    }

    @objc private func controlsChanged() {
        let previous = preferences
        preferences.crosshairSize = size.doubleValue.rounded()
        preferences.lineWidth = (width.doubleValue * 2).rounded() / 2
        preferences.coordinateFontSize = font.doubleValue.rounded()
        preferences.coordinatePosition =
            CapturePreferences.CoordinatePosition.allCases[position.indexOfSelectedItem]
        preferences.showInMenuBar = menuBar.state == .on
        size.doubleValue = preferences.crosshairSize
        width.doubleValue = preferences.lineWidth
        font.doubleValue = preferences.coordinateFontSize
        guard preferences != previous else { return }
        updatePreview(
            cursorChanged: preferences.crosshairSize != previous.crosshairSize
                || preferences.lineWidth != previous.lineWidth)
        onChange(preferences)
    }

    private func updatePreview(cursorChanged: Bool = false) {
        sizeValue.stringValue = String(format: "%.0f pt", preferences.crosshairSize)
        widthValue.stringValue = String(format: "%.1f pt", preferences.lineWidth)
        fontValue.stringValue = String(format: "%.0f pt", preferences.coordinateFontSize)
        if cursorChanged || previewCursor.image == nil {
            previewCursor.image = preferences.makeCursor().image
        }
        let image = previewCursor.image!
        let point = CGPoint(x: 200, y: 80)
        previewCursor.frame = CGRect(
            x: point.x - image.size.width / 2, y: point.y - image.size.height / 2,
            width: image.size.width, height: image.size.height)
        previewCoordinates.font = .monospacedSystemFont(
            ofSize: preferences.coordinateFontSize, weight: .medium)
        previewCoordinates.sizeToFit()
        previewCoordinates.frame = preferences.coordinatePosition.frame(
            at: point, size: previewCoordinates.frame.size,
            in: CGRect(x: 4, y: 4, width: 392, height: 152), gap: image.size.width / 2 + 4)
    }

    func updateStatus(_ message: String) {
        status.stringValue = message
        status.toolTip = message.isEmpty ? nil : message
    }
    @objc private func recordShortcut() { changeShortcut() }
    @objc private func openPermission() { permissionHelp() }
}
