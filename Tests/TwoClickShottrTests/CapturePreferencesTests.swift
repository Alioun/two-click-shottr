import AppKit
import Testing

@testable import TwoClickShottr

@MainActor
struct CapturePreferencesTests {
    @Test func preferencesPersistAndInvalidStoredValuesAreBounded() throws {
        let name = "TwoClickShottrTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        #expect(CapturePreferences(defaults: defaults) == CapturePreferences())
        var preferences = CapturePreferences()
        preferences.crosshairSize = 52
        preferences.lineWidth = 3.5
        preferences.coordinateFontSize = 23
        preferences.coordinatePosition = .lowerLeft
        preferences.showInMenuBar = false
        preferences.save(to: defaults)
        #expect(CapturePreferences(defaults: defaults) == preferences)
        defaults.set(1000, forKey: "crosshairSize")
        defaults.set(-10, forKey: "crosshairLineWidth")
        defaults.set("invalid", forKey: "coordinateFontSize")
        defaults.set("invalid", forKey: "coordinatePosition")
        let bounded = CapturePreferences(defaults: defaults)
        #expect(bounded.crosshairSize == CapturePreferences.crosshairSizeRange.upperBound)
        #expect(bounded.lineWidth == CapturePreferences.lineWidthRange.lowerBound)
        #expect(bounded.coordinateFontSize == CapturePreferences().coordinateFontSize)
        #expect(bounded.coordinatePosition == .upperRight)
        #expect(!bounded.showInMenuBar)
    }

    @Test func allQuadrantsStayInsideScreenBoundsAtEveryCorner() {
        let bounds = CGRect(x: -400, y: -200, width: 400, height: 300)
        let center = CGPoint(x: -200, y: -50)
        let size = CGSize(width: 55, height: 40)
        for position in CapturePreferences.CoordinatePosition.allCases {
            let frame = position.frame(at: center, size: size, in: bounds, gap: 20)
            #expect(bounds.contains(frame))
            #expect(frame.contains(center) == false)
            switch position {
            case .upperRight: #expect(frame.minX > center.x && frame.minY > center.y)
            case .upperLeft: #expect(frame.maxX < center.x && frame.minY > center.y)
            case .lowerLeft: #expect(frame.maxX < center.x && frame.maxY < center.y)
            case .lowerRight: #expect(frame.minX > center.x && frame.maxY < center.y)
            }
            for x in [bounds.minX, bounds.maxX] {
                for y in [bounds.minY, bounds.maxY] {
                    #expect(
                        bounds.contains(
                            position.frame(at: CGPoint(x: x, y: y), size: size, in: bounds, gap: 20)))
                }
            }
        }
    }

    @Test func nativeCursorSizeHotspotAndReusedOverlayFollowSettings() throws {
        var preferences = CapturePreferences()
        preferences.crosshairSize = 48
        preferences.lineWidth = 3
        preferences.coordinateFontSize = 24
        preferences.coordinatePosition = .lowerLeft
        let selector = SelectionController(mode: .twoClick, reuseWindows: true) { _ in }
        defer {
            selector.hide()
            selector.discardPreparedWindows()
        }
        let frames = [CGRect(x: 0, y: 0, width: 500, height: 400)]
        selector.prepare(frames: frames)
        selector.apply(preferences)
        #expect(selector.cursor.image.size == CGSize(width: 58, height: 58))
        #expect(selector.cursor.hotSpot == CGPoint(x: 29, y: 29))
        selector.start(frames: frames, visible: false)
        selector.receive(.move(CGPoint(x: 250, y: 200)))
        let window = try #require(selector.windows.first)
        let label = try #require(window.contentView?.subviews.compactMap { $0 as? NSTextField }.first)
        #expect(label.frame.width > 0 && label.frame.height > 0)
        #expect(label.frame.maxX < 250 && label.frame.maxY < 200)
        let font = try #require(
            label.attributedStringValue.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        #expect(font.pointSize == 24)
        selector.receive(.cancel)
        preferences.coordinatePosition = .upperRight
        preferences.coordinateFontSize = 16
        selector.apply(preferences)
        selector.start(frames: frames, visible: false)
        selector.receive(.move(CGPoint(x: 250, y: 200)))
        #expect(selector.windows.first === window)
        #expect(label.frame.minX > 250 && label.frame.minY > 200)
        let smaller = try #require(
            label.attributedStringValue.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        #expect(smaller.pointSize == 16)
    }
}
