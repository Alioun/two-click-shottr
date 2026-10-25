import AppKit

@MainActor
final class SelectionWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        guard let view = contentView as? SelectionView else {
            super.sendEvent(event)
            return
        }
        switch event.type {
        case .leftMouseDown: view.mouseDown(with: event)
        case .leftMouseUp: view.mouseUp(with: event)
        case .leftMouseDragged: view.mouseDragged(with: event)
        case .mouseMoved: view.mouseMoved(with: event)
        default: super.sendEvent(event)
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            (contentView as? SelectionView)?.cancelOperation(nil)
        } else {
            super.keyDown(with: event)
        }
    }
}

@MainActor
private final class CoordinateView: NSView {
    static let attributes: [NSAttributedString.Key: Any] = {
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black
        shadow.shadowBlurRadius = 2
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        return [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white, .shadow: shadow,
        ]
    }()
    var text = "" {
        didSet { if text != oldValue { needsDisplay = true } }
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) {
        (text as NSString).draw(at: CGPoint(x: 4, y: 4), withAttributes: Self.attributes)
    }
}

@MainActor
final class SelectionView: NSView {
    weak var selection: SelectionController?
    private let shade = CAShapeLayer()
    private let outline = CAShapeLayer()
    private let coordinates = CoordinateView(frame: .zero)
    override var acceptsFirstResponder: Bool { true }
    override var wantsUpdateLayer: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
        shade.fillRule = .evenOdd
        shade.fillColor = NSColor.black.withAlphaComponent(0.22).cgColor
        outline.fillColor = nil
        outline.lineWidth = 1
        layer?.addSublayer(shade)
        layer?.addSublayer(outline)
        addSubview(coordinates)
    }

    required init?(coder: NSCoder) { nil }

    static func prewarm() {
        _ = ("0\n0" as NSString).size(withAttributes: CoordinateView.attributes)
        _ = NSCursor.crosshair.image
    }

    override func mouseDown(with event: NSEvent) { selection?.receive(.down(globalPoint(event))) }
    override func mouseUp(with event: NSEvent) { selection?.receive(.up(globalPoint(event))) }
    override func mouseMoved(with event: NSEvent) { selection?.receive(.move(globalPoint(event))) }
    override func mouseDragged(with event: NSEvent) { selection?.receive(.move(globalPoint(event))) }
    override func cancelOperation(_ sender: Any?) { selection?.receive(.cancel) }

    private func globalPoint(_ event: NSEvent) -> CGPoint {
        if window?.isVisible == true { NSCursor.crosshair.set() }
        return window!.convertPoint(toScreen: event.locationInWindow)
    }

    override func updateLayer() { updateOverlay() }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateOverlay()
    }

    override func layout() {
        super.layout()
        updateOverlay()
    }

    func updateOverlay() {
        guard let selection, let window else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        for shape in [shade, outline] {
            shape.frame = bounds
            shape.contentsScale = window.backingScaleFactor
        }
        let path = CGMutablePath()
        path.addRect(bounds)
        if let preview = selection.state.preview, !preview.isEmpty {
            let rect = convert(window.convertFromScreen(preview), from: nil)
            path.addRect(rect)
            outline.path = CGPath(rect: rect.insetBy(dx: 0.5, dy: 0.5), transform: nil)
        } else {
            outline.path = nil
        }
        shade.path = path
        outline.strokeColor = NSColor.systemYellow.cgColor
        let point = convert(window.convertPoint(fromScreen: selection.pointer), from: nil)
        coordinates.isHidden = !bounds.contains(point)
        guard !coordinates.isHidden else { return }
        let text =
            "\(Int(floor(selection.pointer.x)))\n\(Int(floor(selection.primaryTop - selection.pointer.y)))"
        let size = (text as NSString).size(withAttributes: CoordinateView.attributes)
        var origin = CGPoint(x: point.x + 12, y: point.y + 8)
        if origin.x + size.width > bounds.maxX - 4 { origin.x = point.x - size.width - 12 }
        if origin.y + size.height > bounds.maxY - 4 { origin.y = point.y - size.height - 8 }
        origin.x = max(bounds.minX + 4, min(origin.x, bounds.maxX - size.width - 4))
        origin.y = max(bounds.minY + 4, min(origin.y, bounds.maxY - size.height - 4))
        coordinates.frame = CGRect(origin: origin, size: size).insetBy(dx: -4, dy: -4)
        coordinates.text = text
    }
}

@MainActor
final class SelectionController {
    private(set) var state = SelectionState.waiting
    private(set) var windows: [SelectionWindow] = []
    private(set) var pointer = CGPoint.zero
    private(set) var primaryTop: CGFloat = 0
    private(set) var displayBounds: [CGDirectDisplayID: CGRect] = [:]
    private(set) var mode: SelectionMode
    private let reuseWindows: Bool
    private var preparedWindows: [SelectionWindow] = []
    private var preparedDisplayIDs: [CGDirectDisplayID] = []
    private let completion: (CGRect?) -> Void
    private var displayObserver: NSObjectProtocol?
    private var deactivationObserver: NSObjectProtocol?
    private var cursorObserver: NSObjectProtocol?

    init(mode: SelectionMode, reuseWindows: Bool = false, completion: @escaping (CGRect?) -> Void) {
        self.mode = mode
        self.reuseWindows = reuseWindows
        self.completion = completion
    }

    func prepare(frames: [CGRect] = NSScreen.screens.map(\.frame)) {
        precondition(windows.isEmpty)
        let displayIDs = NSScreen.screens.compactMap {
            $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
        }
        guard preparedWindows.map(\.frame) != frames || preparedDisplayIDs != displayIDs else { return }
        discardPreparedWindows()
        preparedDisplayIDs = displayIDs
        displayBounds = Dictionary(uniqueKeysWithValues: displayIDs.map { ($0, CGDisplayBounds($0)) })
        SelectionView.prewarm()
        pointer = NSEvent.mouseLocation
        primaryTop = NSScreen.screens.first?.frame.maxY ?? 0
        for frame in frames {
            let window = SelectionWindow(
                contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = false
            window.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 1)
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            window.acceptsMouseMovedEvents = true
            let view = SelectionView(frame: NSRect(origin: .zero, size: frame.size))
            view.selection = self
            window.contentView = view
            window.makeFirstResponder(view)
            preparedWindows.append(window)
            view.updateOverlay()
            view.displayIfNeeded()
            for subview in view.subviews { subview.displayIfNeeded() }
        }
    }

    func discardPreparedWindows() {
        for window in preparedWindows {
            (window.contentView as? SelectionView)?.selection = nil
            window.close()
        }
        preparedWindows.removeAll()
    }

    func start(
        frames: [CGRect] = NSScreen.screens.map(\.frame), visible: Bool = true,
        mode: SelectionMode? = nil
    ) {
        precondition(windows.isEmpty)
        if let mode { self.mode = mode }
        state = .waiting
        pointer = NSEvent.mouseLocation
        primaryTop = NSScreen.screens.first?.frame.maxY ?? 0
        if visible { NSCursor.crosshair.set() }
        prepare(frames: frames)
        windows = preparedWindows
        preparedWindows.removeAll(keepingCapacity: true)
        for window in windows {
            window.disableCursorRects()
            let view = window.contentView as? SelectionView
            view?.selection = self
            view?.updateOverlay()
            if visible { window.orderFrontRegardless() }
        }
        if visible {
            cursorObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didUpdateNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshCursor() }
            }
            activateCompanion()
            let pointerWindow = windows.first { $0.frame.contains(pointer) } ?? windows.first
            pointerWindow?.makeKey()
            refreshCursor()
        }
        displayObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.receive(.cancel) }
        }
        deactivationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.receive(.cancel) }
        }
    }

    private func refreshCursor() {
        guard NSApp.isActive, windows.contains(where: { $0.isVisible }) else { return }
        NSCursor.crosshair.set()
    }

    func receive(_ event: SelectionEvent) {
        switch state {
        case .completed, .cancelled: return
        default: break
        }
        let previousPointer = pointer
        let previousPreview = state.preview
        switch event {
        case .down(let point), .move(let point), .up(let point): pointer = point
        case .cancel: break
        }
        state.receive(event, mode: mode)
        switch state {
        case .completed(let rect):
            hide()
            completion(rect)
        case .cancelled:
            hide()
            completion(nil)
        default:
            let previewChanged = previousPreview != state.preview
            for window in windows {
                let pointerChangedHere =
                    previousPointer != pointer
                    && (window.frame.contains(previousPointer) || window.frame.contains(pointer))
                if previewChanged || pointerChangedHere {
                    (window.contentView as? SelectionView)?.updateOverlay()
                }
            }
        }
    }

    func hide() {
        let wasVisible = windows.contains { $0.isVisible }
        if let displayObserver { NotificationCenter.default.removeObserver(displayObserver) }
        displayObserver = nil
        if let deactivationObserver { NotificationCenter.default.removeObserver(deactivationObserver) }
        deactivationObserver = nil
        if let cursorObserver { NotificationCenter.default.removeObserver(cursorObserver) }
        cursorObserver = nil
        for window in windows {
            window.enableCursorRects()
            window.orderOut(nil)
            (window.contentView as? SelectionView)?.selection = nil
            if !reuseWindows { window.close() }
        }
        if reuseWindows { preparedWindows = windows }
        windows.removeAll()
        if wasVisible && NSApp.isActive { NSCursor.arrow.set() }
    }
}

@MainActor
func activateCompanion() {
    if #available(macOS 14.0, *) { NSApp.activate() } else { NSApp.activate(ignoringOtherApps: true) }
}
