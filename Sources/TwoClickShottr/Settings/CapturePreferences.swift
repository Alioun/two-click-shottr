import AppKit

struct CapturePreferences: Equatable {
    enum CoordinatePosition: String, CaseIterable {
        case upperRight, upperLeft, lowerLeft, lowerRight

        var title: String {
            switch self {
            case .upperRight: return "Upper right"
            case .upperLeft: return "Upper left"
            case .lowerLeft: return "Lower left"
            case .lowerRight: return "Lower right"
            }
        }

        func frame(at point: CGPoint, size: CGSize, in bounds: CGRect, gap: CGFloat) -> CGRect {
            let left = self == .upperLeft || self == .lowerLeft
            let below = self == .lowerLeft || self == .lowerRight
            var x = left ? point.x - gap - size.width : point.x + gap
            var y = below ? point.y - gap - size.height : point.y + gap
            if x < bounds.minX || x + size.width > bounds.maxX {
                x = left ? point.x + gap : point.x - gap - size.width
            }
            if y < bounds.minY || y + size.height > bounds.maxY {
                y = below ? point.y + gap : point.y - gap - size.height
            }
            return CGRect(
                x: max(bounds.minX, min(x, bounds.maxX - size.width)),
                y: max(bounds.minY, min(y, bounds.maxY - size.height)),
                width: min(size.width, bounds.width), height: min(size.height, bounds.height))
        }
    }

    static let crosshairSizeRange = 12.0...96.0
    static let lineWidthRange = 0.5...8.0
    static let fontSizeRange = 9.0...32.0

    var crosshairSize = 24.0
    var lineWidth = 1.0
    var coordinateFontSize = 11.0
    var coordinatePosition = CoordinatePosition.upperRight
    var showInMenuBar = true

    init() {}

    init(defaults: UserDefaults) {
        func number(_ key: String, fallback: Double, range: ClosedRange<Double>) -> Double {
            guard let value = defaults.object(forKey: key) as? NSNumber, value.doubleValue.isFinite else {
                return fallback
            }
            return min(range.upperBound, max(range.lowerBound, value.doubleValue))
        }
        crosshairSize = number("crosshairSize", fallback: crosshairSize, range: Self.crosshairSizeRange)
        lineWidth = number("crosshairLineWidth", fallback: lineWidth, range: Self.lineWidthRange)
        coordinateFontSize = number(
            "coordinateFontSize", fallback: coordinateFontSize, range: Self.fontSizeRange)
        coordinatePosition =
            CoordinatePosition(rawValue: defaults.string(forKey: "coordinatePosition") ?? "") ?? .upperRight
        if defaults.object(forKey: "showInMenuBar") != nil {
            showInMenuBar = defaults.bool(forKey: "showInMenuBar")
        }
    }

    func save(to defaults: UserDefaults) {
        defaults.set(crosshairSize, forKey: "crosshairSize")
        defaults.set(lineWidth, forKey: "crosshairLineWidth")
        defaults.set(coordinateFontSize, forKey: "coordinateFontSize")
        defaults.set(coordinatePosition.rawValue, forKey: "coordinatePosition")
        defaults.set(showInMenuBar, forKey: "showInMenuBar")
    }

    @MainActor
    func makeCursor() -> NSCursor {
        let padding = lineWidth + 2
        let side = crosshairSize + padding * 2
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            let center = CGPoint(x: rect.midX, y: rect.midY)
            let path = NSBezierPath()
            path.move(to: CGPoint(x: padding, y: center.y))
            path.line(to: CGPoint(x: rect.maxX - padding, y: center.y))
            path.move(to: CGPoint(x: center.x, y: padding))
            path.line(to: CGPoint(x: center.x, y: rect.maxY - padding))
            path.lineWidth = self.lineWidth + 2
            NSColor.black.setStroke()
            path.stroke()
            path.lineWidth = self.lineWidth
            NSColor.white.setStroke()
            path.stroke()
            return true
        }
        return NSCursor(image: image, hotSpot: CGPoint(x: side / 2, y: side / 2))
    }
}
