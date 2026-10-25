import AppKit
import Testing

@testable import TwoClickShottr

@MainActor
struct CursorProbeTests {
    @Test func drawingHandlerMatchesNativeRetinaBitmapDespiteDifferentTIFFContainers() throws {
        let image = CapturePreferences().makeCursor().image
        let bitmap = try #require(
            NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: 60, pixelsHigh: 60,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 240, bitsPerPixel: 32))
        let context = try #require(NSGraphicsContext(bitmapImageRep: bitmap))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        image.draw(in: CGRect(x: 0, y: 0, width: 60, height: 60), from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        bitmap.size = image.size
        let raster = NSImage(size: image.size)
        raster.addRepresentation(bitmap)
        #expect(image.tiffRepresentation != raster.tiffRepresentation)
        #expect(CursorProbe.imagesMatch(image, raster))
    }

    @Test func differentGeometryAndStrokeCannotPassCursorComparison() {
        let original = CapturePreferences().makeCursor().image
        var changed = CapturePreferences()
        changed.lineWidth = 4
        #expect(!CursorProbe.imagesMatch(original, changed.makeCursor().image))
        changed.crosshairSize = 60
        #expect(!CursorProbe.imagesMatch(original, changed.makeCursor().image))
        #expect(!CursorProbe.imagesMatch(original, NSCursor.arrow.image))
        let differentShape = NSImage(size: original.size, flipped: false) { rect in
            NSColor.white.setFill()
            rect.fill()
            return true
        }
        #expect(!CursorProbe.imagesMatch(original, differentShape))
    }
}
